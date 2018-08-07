-module(node_generic_tasks_functions_benchmark).
-include_lib("node.hrl").
-compile(export_all).


average(X) ->
        average(X, 0, 0).

average([H|T], Length, Sum) ->
        average(T, Length + 1, Sum + H);

average([], Length, Sum) ->
        Sum / Length.


% ==> Aggregation, computation and replication with Lasp on Edge
meteorological_statistics_grisplasp(LoopCount, SampleCount, SampleInterval) ->

  % logger:log(notice, "Starting Meteo statistics task benchmark with Lasp on GRiSP ~n"),

  Self = self(),
  MeteorologicalStatisticsFun = fun MSF (LoopCountRemaining, AccComputations) ->

    logger:log(notice, "Meteo Function remaining iterations: ~p", [LoopCountRemaining]),

    % Must check if module is available
    {pmod_nav, Pid, _Ref} = node_util:get_nav(),
    State = maps:new(),
    State1 = maps:put(press, [], State),
    State2 = maps:put(temp, [], State1),
    State3 = maps:put(time, [], State2),

    FoldFun = fun
        (Elem, AccIn) when is_integer(Elem) andalso is_map(AccIn) ->
            timer:sleep(SampleInterval),
            T = node_stream_worker:maybe_get_time(),
            % T = calendar:local_time(),
            [Pr, Tmp] = gen_server:call(Pid, {read, alt, [press_out, temp_out], #{}}),
            % logger:log(notice, "Getting data from nav sensor pr: ~p tmp: ~p", [Pr, Tmp]),
            % [Pr, Tmp] = [1000.234, 29.55555],
            #{press => maps:get(press, AccIn) ++ [Pr],
            temp => maps:get(temp, AccIn) ++ [Tmp],
            time => maps:get(time, AccIn) ++ [T]}
    end,

    M = lists:foldl(FoldFun, State3, lists:seq(1, SampleCount)),
    % logger:log(notice, "Done Sampling data"),



    T1Computation = erlang:monotonic_time(millisecond),
    % timer:sleep(1500),

    [Pressures, Temperatures, Epochs] = maps:values(M),
    Result = #{measures => lists:zip3(Epochs, Pressures, Temperatures),
        pmean => 'Elixir.Numerix.Statistics':mean(Pressures),
        pvar => 'Elixir.Numerix.Statistics':variance(Pressures),
        tmean => 'Elixir.Numerix.Statistics':mean(Temperatures),
        tvar => 'Elixir.Numerix.Statistics':variance(Temperatures),
        cov => 'Elixir.Numerix.Statistics':covariance(Pressures, Temperatures)},

    T2Computation = erlang:monotonic_time(millisecond),
    lasp:update(node_util:atom_to_lasp_identifier(node(), state_gset), {add, Result}, self()),
    % lasp:update(node_util:atom_to_lasp_identifier(node(), state_gset), {add, {T1Computation, T2Computation}}, self()),

    Cardinality = LoopCount-LoopCountRemaining+1,
    ComputationTime = T2Computation - T1Computation,
    NewAcc = maps:put(Cardinality, {T2Computation, ComputationTime}, AccComputations),
    if LoopCountRemaining > 1 ->
      MSF(LoopCountRemaining-1, NewAcc);
    true ->
      timer:sleep(5000), % Give time to the CA process to finish receiving acks
      convergence_acknowledgement ! {done, NewAcc}
    end
  end,

  ConvergenceAcknowledgementFun = fun CA(Acks) ->
    receive
      % Idea 1: To get the real convergence time, when receiving an ACK, send a response to the caller
      % in order for him to measure the time it took to call the remote process here. The caller would
      % then call this process again but this time to indicate how long it took for him to contact the node.
      % We could then substract that time to TConverged thus giving us the true convergence time.

      % Idea 2: Do a best effort acknowledgements reception.
      % Add timeouts to the receive block as some nodes might be unavailable.
      {ack, From, Cardinality} ->
        % logger:log(notice, "Received Ack from ~p with CRDT cardinality ~p", [From, Cardinality]),
        TConverged = erlang:monotonic_time(millisecond),
        CA([{From, TConverged, Cardinality} | Acks]);
      {done, Computations} -> % Called by the meteo function once it has terminated
        Self ! {done, Computations, Acks}
    end
  end,

  logger:log(notice, "Spawning Acknowledgement receiver process"),
  % https://stackoverflow.com/questions/571339/erlang-spawning-processes-and-passing-arguments
  PidCAF = spawn(fun () -> ConvergenceAcknowledgementFun([]) end),
  PidMSF = spawn(fun () -> MeteorologicalStatisticsFun(LoopCount, #{}) end),
  register(convergence_acknowledgement, PidCAF),

  receive
      % {Acks} ->
      %   logger:log(notice, "Received all acks ~p", [Acks]),
      %   logger:log(notice, "CRDT converged on all nodes"),
      %   MapFun = fun(Elem) ->
      %     logger:log(notice, "Elem is ~p", [Elem]),
      %     {From, TConverged} = Elem,
      %     TConvergence = TConverged - T2Computation,
      %     logger:log(notice, "CRDT converged on ~p after ~p ms", [From, TConvergence]),
      %     TConvergence
      %   end,
      %   ListConvergence = lists:map(MapFun, Acks),
      %   AverageConvergenceTime = average(ListConvergence),
      %   logger:log(notice, "Average convergence time: ~p ms", [AverageConvergenceTime]);
      %
      {done, Computations, Acks} ->
        logger:log(notice, "Meteo task is done, received acks and computations. Calculating computation time + convergence time..."),
        % logger:log(notice, "Computations: ~p - Acks: ~p", [Computations, Acks]),
        AckMap = lists:foldl(
          fun(Ack, Acc) ->
            {From, TConverged, Cardinality} = Ack,
            {T2Computation, _} = maps:get(Cardinality, Computations),
            ConvergenceTime = TConverged - T2Computation,
            case maps:find(From, Acc) of
              {ok, NodeMap} ->
                NewNodeMap = maps:put(Cardinality, ConvergenceTime, NodeMap),
                maps:update(From, NewNodeMap, Acc);
              error ->
                maps:put(From, #{Cardinality => ConvergenceTime}, Acc)
            end
          end , #{}, Acks),
        logger:log(notice, "Ack map is ~p", [AckMap]),
        logger:log(notice, "Computations map is ~p", [Computations]),
        exit(PidCAF, kill),
        exit(PidMSF, kill)
   end.

% ==> Send Aggregated data to the AWS Server. The server will do the computation and replication with Lasp on cloud.
% TODO: untested
meteorological_statistics_cloudlasp(Count) ->
  Self = self(),
  logger:log(notice,"Correct Pid is ~p ~n",[Self]),
  Server = node(),
  logger:log(notice,"Task is waiting for clients to send data ~n"),
  receive
    {Node,connect} -> logger:log(notice,"Received connection from ~p ~n",[Node]);
    Msg -> logger:log(notice,"Wrong message received ~n")
  end,
  %logger:log(notice, "Starting meteo task cloudlasp for node: ~p ~n",[Node]),
  %logger:log(notice, "Server started meteorological task"),
  State = maps:new(),
  State1 = maps:put(press, [], State),
  State2 = maps:put(temp, [], State1),
  State3 = maps:put(time, [], State2),
  Id = spawn(node_generic_tasks_functions_benchmark,server_loop,[Node,Count,State3]),
  register(Node,Id),
  {datastream,Node} ! {Node,server_up},
  meteorological_statistics_cloudlasp(Count).


% ==> "Flood" raw data to the AWS server. The server will do the computation, aggregation and replication with Lasp on cloud.
% TODO: untested
meteorological_statistics_xcloudlasp(SampleCount, SampleInterval) ->

  logger:log(notice, "Starting Meteo statistics task benchmarking for non aggregated data on lasp on cloud"),

  % Must check if module is available
  {pmod_nav, Pid, _Ref} = node_util:get_nav(),
  % meteo = shell:rd(meteo, {press = [], temp = []}),
  % State = #{press => [], temp => [], time => []},
  State = maps:new(),
  State1 = maps:put(press, [], State),
  State2 = maps:put(temp, [], State1),
  State3 = maps:put(time, [], State2),

  AWS_Server = maps:get(main_aws_server, node_config:get(remote_hosts)),
  FoldFun = fun
      (Elem, _Map) when is_integer(Elem)->
          timer:sleep(SampleInterval),
          T = node_stream_worker:maybe_get_time(),
          % T = calendar:local_time(),
          [Pr, Tmp] = gen_server:call(Pid, {read, alt, [press_out, temp_out], #{}}),
          % [Pr, Tmp] = [1000.234, 29.55555],
          NewValues = #{press => Pr, temp => Tmp, time => T},
          {ok, Result} = rpc:call(AWS_Server, node_client, receive_meteo_data, [{node(), NewValues, SampleCount}])
  end,

  M = lists:foldl(FoldFun, State3, lists:seq(1, SampleCount)).

  %TODO: Wait for benchmark results from the remote server

  server_loop(Node,Count,Measures) ->
    if
    Count == 0 ->
                  [Pressures, Temperatures, Epochs] = maps:values(Measures),
                  Result = #{measures => lists:zip3(Epochs, Pressures, Temperatures),
                  pmean => 'Elixir.Numerix.Statistics':mean(Pressures),
                  pvar => 'Elixir.Numerix.Statistics':variance(Pressures),
                  tmean => 'Elixir.Numerix.Statistics':mean(Temperatures),
                  tvar => 'Elixir.Numerix.Statistics':variance(Temperatures),
                  cov => 'Elixir.Numerix.Statistics':covariance(Pressures, Temperatures)},
                  {ok, {NewId, NewT, NewM, NewV}} = lasp:update(Node, {add, Result}, self()),
                  logger:log(notice, "lasp set ~p at the end is ~p", [Node,NewV]);
    true ->
            receive
              Data -> {Board,Temp,Press,T} = Data;
              true -> Press = error, Temp = error, T = error
            end,
            NewMeasures = #{press => maps:get(press, Measures) ++ [Press],
            temp => maps:get(temp, Measures) ++ [Temp],
            time => maps:get(time, Measures) ++ [T]},
            NewCount = Count - 1,
            server_loop(Node,NewCount,NewMeasures)

  end.
