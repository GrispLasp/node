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
meteorological_statistics_grisplasp(SampleCount, SampleInterval) ->

  logger:log(notice, "Starting Meteo statistics task benchmark with Lasp on GRiSP ~n"),

  % Must check if module is available
  {pmod_nav, Pid, _Ref} = node_util:get_nav(),
  % meteo = shell:rd(meteo, {press = [], temp = []}),
  % State = #{press => [], temp => [], time => []},
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
          logger:log(notice, "Getting data from nav sensor pr: ~p tmp: ~p", [Pr, Tmp]),
          % [Pr, Tmp] = [1000.234, 29.55555],
          #{press => maps:get(press, AccIn) ++ [Pr],
          temp => maps:get(temp, AccIn) ++ [Tmp],
          time => maps:get(time, AccIn) ++ [T]}
  end,

  M = lists:foldl(FoldFun, State3, lists:seq(1, SampleCount)),
  logger:log(notice, "Done Sampling data"),

  T1Computation = erlang:monotonic_time(millisecond),

  [Pressures, Temperatures, Epochs] = maps:values(M),
  Result = #{measures => lists:zip3(Epochs, Pressures, Temperatures),
      pmean => 'Elixir.Numerix.Statistics':mean(Pressures),
      pvar => 'Elixir.Numerix.Statistics':variance(Pressures),
      tmean => 'Elixir.Numerix.Statistics':mean(Temperatures),
      tvar => 'Elixir.Numerix.Statistics':variance(Temperatures),
      cov => 'Elixir.Numerix.Statistics':covariance(Pressures, Temperatures)},

  T2Computation = erlang:monotonic_time(millisecond),

  {ok, {Id, _, _, _}} = hd(node_util:declare_crdts([node()])),
  {ok, {NewId, NewT, NewM, NewV}} = lasp:update(Id, {add, Result}, self()),

  Self = self(),

  ConvergenceAcknowledgement = fun CA(Acks) ->
    receive
      % Idea 1: To get the real convergence time, when receiving an ACK, send a response to the caller
      % in order for him to measure the time it took to call the remote process here. The caller would
      % then call this process again but this time to indicate how long it took for him to contact the node.
      % We could then substract that time to TConverged thus giving us the true convergence time.

      % Idea 2: Do a best effort acknowledgements reception.
      % Add timeouts to the receive block as some nodes might be unavailable.
      {ack, From} ->
        logger:log(notice, "Received Ack from ~p", [From]),
        TConverged = erlang:monotonic_time(millisecond),
        NodesWithoutMe = lists:delete(node(),?BOARDS(?ALL)),
        NodesCount = length(NodesWithoutMe),
        NewAcks = Acks ++ [{From, TConverged}],
        if length(NewAcks) == NodesCount ->
          logger:log(notice, "Received all acks! Notifying self"),
          Self ! {NewAcks},
          exit(self());
        true ->
          logger:log(notice, "Didn't receive all acks, continue to listen"),
          CA(NewAcks)
        end
    end
  end,

  logger:log(notice, "Spawning Acknowledgement receiver process"),
  % https://stackoverflow.com/questions/571339/erlang-spawning-processes-and-passing-arguments
  PidCA = spawn(fun () -> ConvergenceAcknowledgement([]) end),
  register(convergence_acknowledgement, PidCA),

  receive
      {Acks} ->
        logger:log(notice, "Received all acks ~p", [Acks]),
        logger:log(notice, "CRDT converged on all nodes"),
        ComputationTime = T2Computation - T1Computation,
        logger:log(notice, "Computation time: ~p ms", [ComputationTime]),
        MapFun = fun(Elem) ->
          logger:log(notice, "Elem is ~p", [Elem]),
          {From, TConverged} = Elem,
          TConvergence = TConverged - T2Computation,
          logger:log(notice, "CRDT converged on ~p after ~p ms", [From, TConvergence]),
          TConvergence
        end,
        ListConvergence = lists:map(MapFun, Acks),
        AverageConvergenceTime = average(ListConvergence),
        logger:log(notice, "Average convergence time: ~p ms", [AverageConvergenceTime]),
        exit(PidCA, kill)
   end.

% ==> Send Aggregated data to the AWS Server. The server will do the computation and replication with Lasp on cloud.
% TODO: untested
meteorological_statistics_cloudlasp(SampleCount, SampleInterval) ->

  logger:log(notice, "Starting Meteo statistics task benchmarking for aggregated data on lasp on cloud"),

  % Must check if module is available
  {pmod_nav, Pid, _Ref} = node_util:get_nav(),
  % meteo = shell:rd(meteo, {press = [], temp = []}),
  % State = #{press => [], temp => [], time => []},
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
          % [Pr, Tmp] = [1000.234, 29.55555],
          #{press => maps:get(press, AccIn) ++ [Pr],
          temp => maps:get(temp, AccIn) ++ [Tmp],
          time => maps:get(time, AccIn) ++ [T]}
  end,

  M = lists:foldl(FoldFun, State3, lists:seq(1, SampleCount)),

  % Do computation here or on aws server?
  %
  % T1Computation = erlang:monotonic_time(millisecond),
  %
  % [Pressures, Temperatures, Epochs] = maps:values(M),
  % Result = #{measures => lists:zip3(Epochs, Pressures, Temperatures),
  %     pmean => 'Elixir.Numerix.Statistics':mean(Pressures),
  %     pvar => 'Elixir.Numerix.Statistics':variance(Pressures),
  %     tmean => 'Elixir.Numerix.Statistics':mean(Temperatures),
  %     tvar => 'Elixir.Numerix.Statistics':variance(Temperatures),
  %     cov => 'Elixir.Numerix.Statistics':covariance(Pressures, Temperatures)},
  %
  % T2Computation = erlang:monotonic_time(millisecond),

  AWS_Server = maps:get(main_aws_server, node_config:get(remote_hosts)),

  % Round trip time and computation time
  {ok, {RTT, CT}} = rpc:call(AWS_Server, node_client, receive_meteo_data, [{node(), maps:values(M)}]).


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
