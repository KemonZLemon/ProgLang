-module(client).

-export([main/1, run/4]).

%% Do not change these supplied function signatures.
main([NText, ScriptFile, OutputFile, LocationsFile]) ->
    run(list_to_integer(NText), ScriptFile, OutputFile, LocationsFile);
main(_) ->
    erlang:error(bad_arguments).

run(N, ScriptFile, OutputFile, LocationsFile) ->
    ok = pa2_util:reset_output(OutputFile),
    ok = pa2_util:ensure_worker_directories(N),
    WorkerNodes = pa2_util:read_nodes(LocationsFile, N),

    %% The Coordinator is monitored (not linked) so that if it, or one of its
    %% Workers, crashes, every receive below turns that into an error instead
    %% of waiting forever.
    {Coordinator, MonitorRef} =
        spawn_monitor(coordinator, start, [N, WorkerNodes, self()]),
    receive
        {coordinator_ready, Coordinator} ->
            ok;
        {'DOWN', _, process, Coordinator, Reason} ->
            erlang:error({coordinator_failed, Reason})
    end,

    Commands = pa2_util:script_commands(ScriptFile),
    InputDirectory = filename:dirname(filename:absname(ScriptFile)),
    {AnalysisCount, Results0} = run_commands(
        Commands,
        InputDirectory,
        Coordinator,
        OutputFile,
        0,
        #{}
    ),
    _Results = collect_results(
        Coordinator,
        OutputFile,
        AnalysisCount,
        Results0
    ),

    Coordinator ! {stop, self()},
    receive
        {coordinator_stopped, Coordinator} ->
            erlang:demonitor(MonitorRef, [flush]),
            ok;
        {'DOWN', _, process, Coordinator, StopReason} ->
            erlang:error({coordinator_failed, StopReason})
    end.

%% Process the script top to bottom. Results maps the analysis ID of every
%% result received so far to its value. An Analyze command is sent without
%% waiting for its result; an Inactive command is a barrier that waits for the
%% Coordinator's acknowledgement. Since the Client sends all requests to the
%% one Coordinator process and Erlang keeps the order of messages between two
%% processes, the Coordinator sees the commands in script order.
run_commands([], _InputDirectory, _Coordinator, _OutputFile,
             AnalysisCount, Results) ->
    {AnalysisCount, Results};
run_commands(
    [[<<"a">>, FileName, Keyword] | Rest],
    InputDirectory,
    Coordinator,
    OutputFile,
    AnalysisCount,
    Results
) ->
    InputPath = filename:join(InputDirectory, binary_to_list(FileName)),
    {ok, Contents} = file:read_file(InputPath),
    Coordinator ! {analyze, self(), FileName, Contents, Keyword},
    %% Write any results that have already arrived, but never wait for one.
    NewResults = take_available_results(Coordinator, OutputFile, Results),
    run_commands(
        Rest, InputDirectory, Coordinator, OutputFile,
        AnalysisCount + 1, NewResults
    );
run_commands(
    [[<<"i">>, WorkerIdText] | Rest],
    InputDirectory,
    Coordinator,
    OutputFile,
    AnalysisCount,
    Results
) ->
    WorkerId = binary_to_integer(WorkerIdText),
    Coordinator ! {deactivate, self(), WorkerId},
    NewResults = await_deactivation(Coordinator, WorkerId, OutputFile, Results),
    run_commands(
        Rest, InputDirectory, Coordinator, OutputFile,
        AnalysisCount, NewResults
    );
run_commands([Invalid | _], _InputDirectory, _Coordinator, _OutputFile,
             _Count, _Results) ->
    erlang:error({invalid_command, Invalid}).

%% Barrier: wait for the acknowledgement of this deactivation. Results of
%% earlier analyses that arrive in the meantime are written immediately.
await_deactivation(Coordinator, WorkerId, OutputFile, Results) ->
    receive
        {deactivated, Coordinator, WorkerId} ->
            Results;
        {analysis_result, Coordinator, AnalysisId, Value} ->
            await_deactivation(
                Coordinator, WorkerId, OutputFile,
                store_result(OutputFile, AnalysisId, Value, Results)
            );
        {'DOWN', _, process, Coordinator, Reason} ->
            erlang:error({coordinator_failed, Reason})
    end.

%% Write the results that are already in the mailbox; return immediately when
%% there are none.
take_available_results(Coordinator, OutputFile, Results) ->
    receive
        {analysis_result, Coordinator, AnalysisId, Value} ->
            take_available_results(
                Coordinator, OutputFile,
                store_result(OutputFile, AnalysisId, Value, Results)
            )
    after 0 ->
        Results
    end.

%% After the last command: receive until there is one result for every
%% Analyze command, in whatever order they finish.
collect_results(_Coordinator, _OutputFile, AnalysisCount, Results)
        when map_size(Results) >= AnalysisCount ->
    Results;
collect_results(Coordinator, OutputFile, AnalysisCount, Results) ->
    receive
        {analysis_result, Coordinator, AnalysisId, Value} ->
            collect_results(
                Coordinator, OutputFile, AnalysisCount,
                store_result(OutputFile, AnalysisId, Value, Results)
            );
        {'DOWN', _, process, Coordinator, Reason} ->
            erlang:error({coordinator_failed, Reason})
    end.

%% Append one result record to the output file and remember its analysis ID.
%% A repeated result for the same analysis would add a second record, so it is
%% dropped.
store_result(OutputFile, AnalysisId, Value, Results) ->
    case maps:is_key(AnalysisId, Results) of
        true ->
            Results;
        false ->
            ok = pa2_util:append_result(OutputFile, AnalysisId, Value),
            Results#{AnalysisId => Value}
    end.
