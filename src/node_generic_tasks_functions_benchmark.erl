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
            % T = node_stream_worker:maybe_get_time(),
            T = calendar:local_time(),
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
      timer:sleep(5000), % Give time to the CAF process to finish receiving acks
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
  register(meteo_stats, PidMSF),

  receive
      {done, Computations, Acks} ->
        grisp_led:color(1, blue),
        grisp_led:color(2, green),
        logger:log(notice, "Meteo task is done, received acks and computations. Calculating computation time + convergence time..."),
        % logger:log(notice, "Computations: ~p - Acks: ~p", [Computations, Acks]),

        NodesConvergenceTime = lists:foldl(
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
          % logger:log(notice, "Nodes convergence times is ~p", [NodesConvergenceTime]),
          NodesConvergenceTimeCalculations = maps:map(fun(Node, ConvergenceTimes) ->
            Convergences = maps:values(ConvergenceTimes),
            SD = 'Elixir.Numerix.Statistics':std_dev(Convergences),
            Var = 'Elixir.Numerix.Statistics':variance(Convergences),
            Avg ='Elixir.Numerix.Statistics':mean(Convergences),
            {{average, Avg}, {standard_deviation, SD}, {variance, Var}}
          end, NodesConvergenceTime),

          SumConvergenceTimes = lists:foldl(fun({{_, Mean},{_,_},{_,_}}, Acc) ->
            Acc + Mean
          end, 0, maps:values(NodesConvergenceTimeCalculations)),
          MeanConvergenceTime = SumConvergenceTimes / length(maps:keys(NodesConvergenceTime)),

          Variances = lists:foldl(fun({{_, _},{_,_},{_, Var}}, Acc) ->
            Acc ++ [Var]
          end, [],  maps:values(NodesConvergenceTimeCalculations)),

          SampleSize1 = length(maps:keys(maps:get(lists:nth(1, maps:keys(NodesConvergenceTime)), NodesConvergenceTime))),
          SampleSize2 = length(maps:keys(maps:get(lists:nth(2, maps:keys(NodesConvergenceTime)), NodesConvergenceTime))),
          PooledVarianceConvergence = (((SampleSize1-1)*lists:nth(1,Variances)) + ((SampleSize2-1)*lists:nth(2,Variances)))/((SampleSize1+SampleSize2)/2),
          PooledStandardDeviationConvergence = math:sqrt(PooledVarianceConvergence),
          ComputationFiltered = maps:map(fun(Cardinality, {T2Computation, ComputationTime}) ->
            ComputationTime
          end, Computations),
          MeanComputationTime = 'Elixir.Numerix.Statistics':mean(maps:values(ComputationFiltered)),
          StandardDeviationComputationTime = 'Elixir.Numerix.Statistics':std_dev(maps:values(ComputationFiltered)),
          VarianceComputationTime = 'Elixir.Numerix.Statistics':variance(maps:values(ComputationFiltered)),
          % logger:log(info, "nodes total converges averages = ~p ~n", [NodesConvergenceTimeAverage]),

        %%%%%%%%%%%%%%%%%%%%%%%
        % Save results to ETS %
        %%%%%%%%%%%%%%%%%%%%%%%
        % TableName = list_to_atom(unicode:characters_to_list([atom_to_list(node()), "_results"], latin1)),
        % Tmp = ets:new(TableName, [ordered_set, named_table, public]),
        % ResultSave = case ets:insert_new(Tmp, {node(), {ComputationFiltered}, {MeanComputationTime}, {VarianceComputationTime}, {NodesConvergenceTime}, {NodesConvergenceTimeCalculations},{MeanConvergenceTime},{PooledVarianceConvergence}}) of
        %     true ->
        %       FileName = node(),
        %       case ets:tab2file(Tmp, FileName, [{sync, true}]) of
        %         ok ->
        %           logger:log(notice, "Saved results to SD card."),
        %           true = ets:delete(Tmp),
        %           ok;
        %         {error, Reason} ->
        %           logger:log(error, "Could not save results to SD card"),
        %           {error, Reason}
        %       end;
        %     false ->
        %       logger:log(error, "Could not insert results in ets"),
        %       {error, insert}
        % end,
        %%%%%%%%%%%%%%%%%%%%%%%%
        % Save results to file %
        %%%%%%%%%%%%%%%%%%%%%%%%
        file:write_file(atom_to_list(node()), io_lib:fwrite("Computations: ~p ~nMean Computation Time: ~pms~nStandard Deviation Computation Time: ~p~nVariance Computation Time: ~p~nNodes Convergence Time: ~p ~nNodes Convergence Calculations: ~p ~nMean Convergence Time: ~pms~nPooled Standard Deviation Convergence Time: ~p~nPooled Variance Convergence Time: ~p~n", [ComputationFiltered, MeanComputationTime, StandardDeviationComputationTime, VarianceComputationTime, NodesConvergenceTime, NodesConvergenceTimeCalculations, MeanConvergenceTime, PooledStandardDeviationConvergence, PooledVarianceConvergence])),
        timer:sleep(2000),
        exit(PidCAF, kill),
        exit(PidMSF, kill)
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
