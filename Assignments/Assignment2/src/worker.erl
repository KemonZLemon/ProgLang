-module(worker).

-export([start/2]).

%% A Worker maintains its Worker ID, its name (worker<Id>) and its active
%% state. It saves each chunk it is given under workers/worker<Id>/, counts the
%% exact (case-sensitive) keyword matches in it, and reports the partial count
%% back to the Coordinator together with the analysis ID and chunk ID.
%%
%% Deactivation only changes the Worker's active state. The process stays
%% alive and still completes every chunk that an earlier analysis sent it,
%% even if that chunk is handled after the deactivation message; the
%% Coordinator is what stops giving an inactive Worker new work.

-record(state, {
    id,               % zero-based Worker ID
    name,             % "worker<Id>", also the name of its directory
    active = true     % permanently false once deactivated
}).

%% Do not change this supplied function signature.
start(WorkerId, Coordinator) ->
    State = #state{id = WorkerId, name = "worker" ++ integer_to_list(WorkerId)},
    %% Nothing else to prepare: the Client has already created every
    %% workers/worker<Id>/ directory, and pa2_util:write_chunk/4 makes sure the
    %% directory exists before it writes.
    Coordinator ! {worker_ready, WorkerId, self()},
    loop(State).

loop(State = #state{id = WorkerId}) ->
    receive
        {
            analyze_chunk,
            Coordinator,
            AnalysisId,
            ChunkId,
            _FileName,
            Chunk,
            Keyword
        } ->
            %% Deliberately not guarded by the active state: a chunk that
            %% belongs to an analysis started before the deactivation must
            %% still be completed.
            ok = pa2_util:write_chunk(WorkerId, AnalysisId, ChunkId, Chunk),
            Count = pa2_util:count_word(Chunk, Keyword),
            Coordinator ! {chunk_result, self(), AnalysisId, ChunkId, Count},
            loop(State);

        {deactivate, Coordinator} ->
            Coordinator ! {worker_deactivated, self(), WorkerId},
            loop(State#state{active = false});

        {stop, Coordinator} ->
            Coordinator ! {worker_stopped, self(), WorkerId},
            ok
    end.
