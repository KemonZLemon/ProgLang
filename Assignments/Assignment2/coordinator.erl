-module(coordinator).

-export([start/3]).

-record(worker_info, {
    id,
    pid,
    active = true
}).

%% State kept for one analysis that has been dispatched but not yet finished.
-record(analysis, {
    client,        % PID that gets the final result
    outstanding,   % chunk IDs whose partial count has not arrived yet
    total = 0      % sum of the partial counts received so far
}).

%% Do not change this supplied function signature.
start(N, WorkerNodes, Client) ->
    Workers = create_workers(N, WorkerNodes),
    ok = await_workers_ready(Workers),
    Client ! {coordinator_ready, self()},
    loop(0, Workers, #{}).

%% AnalysisId is the ID the next Analyze command will get; Pending maps the
%% ID of every unfinished analysis to its #analysis{} record.
%%
%% The loop never waits for the chunks of an analysis. It dispatches them,
%% remembers them in Pending and goes straight back to receive, so a later
%% Analyze or Inactive command is accepted while earlier analyses are still
%% collecting partial counts. Every chunk_result carries its analysis ID and
%% chunk ID, so results of overlapping analyses are never mixed.
loop(AnalysisId, Workers, Pending) ->
    receive
        {analyze, Client, FileName, Contents, Keyword} ->
            ActiveWorkers = [W || W = #worker_info{active = true} <- Workers],
            case ActiveWorkers of
                [] ->
                    %% No Worker is active: ERROR, and no chunk file is made.
                    Client ! {analysis_result, self(), AnalysisId, error},
                    loop(AnalysisId + 1, Workers, Pending);
                _ ->
                    Chunks = pa2_util:split_chunks(Contents, length(ActiveWorkers)),
                    NewPending = dispatch(
                        AnalysisId, Client, FileName, Keyword,
                        Chunks, ActiveWorkers, Pending
                    ),
                    loop(AnalysisId + 1, Workers, NewPending)
            end;

        {chunk_result, _WorkerPid, ResultAnalysisId, ChunkId, Count} ->
            NewPending = record_chunk_result(
                ResultAnalysisId, ChunkId, Count, Pending
            ),
            loop(AnalysisId, Workers, NewPending);

        {deactivate, Client, WorkerId} ->
            NewWorkers = deactivate_worker(WorkerId, Workers),
            Client ! {deactivated, self(), WorkerId},
            loop(AnalysisId, NewWorkers, Pending);

        {stop, Client} ->
            ok = stop_workers(Workers),
            Client ! {coordinator_stopped, self()},
            ok
    end.

%% Spawn Worker i on element i of WorkerNodes (or on this node when
%% WorkerNodes is empty, i.e. in concurrent mode). The Workers are linked to
%% the Coordinator, so a Worker that crashes (or whose node disappears) takes
%% the Coordinator down instead of leaving the run hanging; the Client
%% monitors the Coordinator and reports the failure.
create_workers(N, WorkerNodes) ->
    [
        #worker_info{
            id = Id,
            pid = spawn_link(
                worker_node(Id, WorkerNodes), worker, start, [Id, self()]
            ),
            active = true
        }
        || Id <- lists:seq(0, N - 1)
    ].

worker_node(_Id, []) ->
    node();
worker_node(Id, WorkerNodes) ->
    lists:nth(Id + 1, WorkerNodes).

%% Block until every Worker has reported ready. Nothing else can be in the
%% mailbox yet: the Client has not been told that we are ready.
await_workers_ready(Workers) ->
    lists:foreach(
        fun(#worker_info{id = Id, pid = Pid}) ->
            receive
                {worker_ready, Id, Pid} -> ok
            end
        end,
        Workers
    ).

%% Split the active Workers' share of this analysis into chunks, send them all
%% asynchronously, and record the analysis in Pending. pa2_util:split_chunks/2
%% returns at most one chunk per active Worker, with sizes that differ by at
%% most one word and are non-increasing. Giving chunk i to the i-th active
%% Worker therefore keeps every active Worker's load within one word of every
%% other (Workers beyond the chunk count get zero, which is also allowed
%% because then each chunk is a single word).
dispatch(AnalysisId, Client, _FileName, _Keyword, [], _ActiveWorkers, Pending) ->
    %% No words in the input: no chunks, and the count is 0.
    Client ! {analysis_result, self(), AnalysisId, 0},
    Pending;
dispatch(AnalysisId, Client, FileName, Keyword, Chunks, ActiveWorkers, Pending) ->
    ChunkIds = lists:seq(0, length(Chunks) - 1),
    Targets = lists:sublist(ActiveWorkers, length(Chunks)),
    lists:foreach(
        fun({ChunkId, #worker_info{pid = Pid}, Chunk}) ->
            Pid ! {
                analyze_chunk, self(), AnalysisId, ChunkId,
                FileName, Chunk, Keyword
            }
        end,
        lists:zip3(ChunkIds, Targets, Chunks)
    ),
    Pending#{AnalysisId => #analysis{client = Client, outstanding = ChunkIds}}.

%% Add one partial count to its analysis. Once every chunk of that analysis
%% has answered, send the total to the Client and forget the analysis. A
%% repeated or unknown (analysis, chunk) pair is ignored, so a count can never
%% be added twice or to the wrong analysis.
record_chunk_result(AnalysisId, ChunkId, Count, Pending) ->
    case maps:find(AnalysisId, Pending) of
        {ok, Analysis = #analysis{outstanding = Outstanding, total = Total}} ->
            case lists:member(ChunkId, Outstanding) of
                false ->
                    Pending;
                true ->
                    Remaining = lists:delete(ChunkId, Outstanding),
                    NewTotal = Total + Count,
                    case Remaining of
                        [] ->
                            Client = Analysis#analysis.client,
                            Client ! {analysis_result, self(), AnalysisId, NewTotal},
                            maps:remove(AnalysisId, Pending);
                        _ ->
                            Pending#{AnalysisId => Analysis#analysis{
                                outstanding = Remaining,
                                total = NewTotal
                            }}
                    end
            end;
        error ->
            Pending
    end.

%% Mark the Worker inactive for all later analyses. A Worker that is still
%% active is told to deactivate and we wait for its acknowledgement, which
%% the Client needs before it may send the next command. That wait is short
%% and cannot deadlock: the Worker never waits for the Coordinator, and
%% chunks sent to it earlier are handled first (message order is preserved
%% between two processes), so none of them is cancelled. Partial counts that
%% arrive meanwhile simply stay in the mailbox. Deactivating a Worker that is
%% already inactive changes nothing.
deactivate_worker(WorkerId, Workers) ->
    case lists:keyfind(WorkerId, #worker_info.id, Workers) of
        Worker = #worker_info{pid = Pid, active = true} ->
            Pid ! {deactivate, self()},
            receive
                {worker_deactivated, Pid, WorkerId} -> ok
            end,
            lists:keyreplace(
                WorkerId, #worker_info.id, Workers,
                Worker#worker_info{active = false}
            );
        _AlreadyInactiveOrUnknown ->
            Workers
    end.

%% Stop every Worker (active or not) and wait for each acknowledgement.
stop_workers(Workers) ->
    lists:foreach(
        fun(#worker_info{pid = Pid}) -> Pid ! {stop, self()} end,
        Workers
    ),
    lists:foreach(
        fun(#worker_info{id = Id, pid = Pid}) ->
            receive
                {worker_stopped, Pid, Id} -> ok
            end
        end,
        Workers
    ).
