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
Time = erlang:monotonic_time(millisecond),
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
    Msg -> Node = error,logger:log(notice,"Wrong message received ~n"),Pid = 0
  end,
  State = maps:new(),
  State1 = maps:put(press, [], State),
  State2 = maps:put(temp, [], State1),
  State3 = maps:put(time, [], State2),
  Id = spawn(node_generic_tasks_functions_benchmark,server_loop,[Node,Count,State3]),
  register(server,Id),
  {datastream,'node@my_grisp_board_2'} ! {server_up},
  logger:log(notice,"sent ack"),
  meteorological_statistics_cloudlasp(Count).


% ==> "Flood" raw data to the AWS server. The server will do the computation, aggregation and replication with Lasp on cloud.
% TODO: untested
meteorological_statistics_xcloudlasp(Count,LoopCount) ->
  Self = self(),
  logger:log(warning,"Correct Pid is ~p ~n",[Self]),
  Server = node(),
  logger:log(warning,"Task is waiting for clients to send data ~n"),
  receive
    {Node,connect} -> logger:log(warning,"Received connection from ~p ~n",[Node]);
    Msg -> Node = error,logger:log(warning,"Wrong message received ~n"),Pid = 0
  end,
  State = maps:new(),
  State1 = maps:put(press, [], State),
  State2 = maps:put(temp, [], State1),
  State3 = maps:put(time, [], State2),
  Id = spawn(node_generic_tasks_functions_benchmark,server_loop,[Node,Count,1,LoopCount,State3]),
  register(server,Id),
  {datastream,'node@my_grisp_board_2'} ! {server_up},
  logger:log(warning,"sent ack"),
  meteorological_statistics_xcloudlasp(Count,LoopCount).
  %logger:log(notice, "Starting Meteo statistics task benchmarking for non aggregated data on lasp on cloud"),

  % Must check if module is available
  %{pmod_nav, Pid, _Ref} = node_util:get_nav(),
  % meteo = shell:rd(meteo, {press = [], temp = []}),
  % State = #{press => [], temp => [], time => []},
  %State = maps:new(),
  %State1 = maps:put(press, [], State),
  %State2 = maps:put(temp, [], State1),
  %State3 = maps:put(time, [], State2),

  %AWS_Server = maps:get(main_aws_server, node_config:get(remote_hosts)),
  %FoldFun = fun
  %    (Elem, _Map) when is_integer(Elem)->
  %        timer:sleep(SampleInterval),
  %        T = node_stream_worker:maybe_get_time(),
  %        % T = calendar:local_time(),lasp:read(node_util:atom_to_lasp_identifier(Node, state_gset), {cardinality, Cardinality}),

  %        [Pr, Tmp] = gen_server:call(Pid, {read, alt, [press_out, temp_out], #{}}),
  %        % [Pr, Tmp] = [1000.234, 29.55555],
  %        NewValues = #{press => Pr, temp => Tmp, time => T},
  %        {ok, Result} = rpc:call(AWS_Server, node_client, receive_meteo_data, [{node(), NewValues, SampleCount}])
  %end,                    Spawned = whereis(ackreceiver),

  %M = lists:foldl(FoldFun, State3, lists:seq(1, SampleCount)).

  %TODO: Wait for benchmark results from lasp:read(node_util:atom_to_lasp_identifier(Node, state_gset), {cardinality, Cardinality}),


  server_loop(Node,DataCount,Cardi,LoopCount,Measures) ->
    receive
      Data -> {Board,Temp,Press,T} = Data;
      %logger:log(warning,"Data received by the server");
      true -> Press = error, Temp = error, T = error, Board = error
    end,
    NewMeasures = #{press => maps:get(press, Measures) ++ [Press],
    temp => maps:get(temp, Measures) ++ [Temp],
    time => maps:get(time, Measures) ++ [T]},
    Result = numerix_calculation(NewMeasures),
    if
      Cardi > LoopCount -> logger:log(warning,"Server loop is done");
      true ->
                if
                  DataCount == 0 ->
                                %{ok, {Id, _, _, _}} = hd(node_util:declare_crdts([Board])),
                                BeforeUpdate = erlang:monotonic_time(millisecond),
                                lasp:update(node_util:atom_to_lasp_identifier(Board, state_gset), {add, Result}, self()),
                                UpdateTime = erlang:monotonic_time(millisecond),
                                TotalTime = UpdateTime-BeforeUpdate,
                                logger:log(warning,"Time to update ~p",[TotalTime]),
                                Server3 = 'server3@ec2-35-180-138-155.eu-west-3.compute.amazonaws.com',
                                Server1 = 'server1@ec2-18-185-18-147.eu-central-1.compute.amazonaws.com',
                                PidMainReceiver = spawn(node_generic_tasks_functions_benchmark,main_server_ack_receiver,[2,UpdateTime]),
                                register(ackreceiver,PidMainReceiver),
                                {connector,Server1} ! {node(),Board,Cardi},{connector,Server3} ! {node(),Board,Cardi},
                                receive
                                  all_acks -> logger:log(warning,"Received all acks")
                                end,
                                server_loop(Node,100,Cardi+1,LoopCount,NewMeasures);
                  true -> NewCount = DataCount - 1,
                          server_loop(Node,NewCount,Cardi,LoopCount,NewMeasures)
                end
      end.

numerix_calculation(Measures) ->
  [Pressures, Temperatures, Epochs] = maps:values(Measures),
  Result = #{measures => lists:zip3(Epochs, Pressures, Temperatures),
  pmean => 'Elixir.Numerix.Statistics':mean(Pressures),
  pvar => 'Elixir.Numerix.Statistics':variance(Pressures),
  tmean => 'Elixir.Numerix.Statistics':mean(Temperatures),
  tvar => 'Elixir.Numerix.Statistics':variance(Temperatures),
  cov => 'Elixir.Numerix.Statistics':covariance(Pressures, Temperatures)},
  Result.




 main_server_ack_receiver(CountServer,UpdateTime) ->
  if
  CountServer > 0 -> receive
                      {Server,Time,Node} ->
                                              ConvergTime = Time - UpdateTime,
                                              logger:log(warning,"=====Server ~p needed ~p milli to converge set: ~p===== ",[Server,ConvergTime,Node]),
                                              main_server_ack_receiver(CountServer-1,UpdateTime);
                      Meg -> error
                    end;
  true -> server ! all_acks,logger:log(warning,"=====Finish updating=====")
end.






updater_ack_receiver(Count,LoopCount) ->
  Self = node(),
 if
   Count > LoopCount -> logger:log(warning,"function is over cardinality of ~p reacher",[LoopCount]);
  true ->receive
              {Main,Node,Cardinality} -> logger:log(warning,"=========updating request sent by main server for set ~p with cardinality ~p======",[Node,Cardinality]),
                                        % Time1 = os:system_time(),
                                         %logger:log(warning,"====printing time before read ~p",[Time1]),
                                         TimeB = erlang:monotonic_time(millisecond),
                                         lasp:read(node_util:atom_to_lasp_identifier(Node, state_gset), {cardinality, Cardinality}),
                                         TimeA = erlang:monotonic_time(millisecond),
                                        TotalTime = TimeA - TimeB,
                                         %Time = os:system_time(),
                                         %logger:log(warning,"====printing time after read ~p",[Time]),
                                         %T = Time - Time1,
                                         %TotalTime = T/1000000,
                                         logger:log(warning,"==============Time for blocking read is ~p============",[TotalTime]),
                                         logger:log(warning,"=====blocking read done sending ack back to main======"),
                                         NewCount = Count + 1,
                                         {ackreceiver,Main} ! {Self,TotalTime,Node},
                                         updater_ack_receiver(NewCount,LoopCount);
                                  Msg -> error
            end
  end.
