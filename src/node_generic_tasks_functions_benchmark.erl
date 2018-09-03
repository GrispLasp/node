-module(node_generic_tasks_functions_benchmark).
-include_lib("node.hrl").
-compile(export_all).


% ==> Aggregation, computation and replication with Lasp on Edge
meteorological_statistics_grisplasp(LoopCount, SampleCount, SampleInterval) ->


  % logger:log(notice, "Starting Meteo statistics task benchmark with Lasp on GRiSP ~n"),

  Self = self(),
  SampleSeq = lists:seq(1, SampleCount),
  MeteoMap = #{press => [], temp => [], time => []},
  MeteorologicalStatisticsFun = fun MSF (LoopCountRemaining, AccComputations) ->

    logger:log(notice, "Meteo Function remaining iterations: ~p", [LoopCountRemaining]),

    % Must check if module is available
    {pmod_nav, Pid, _Ref} = node_util:get_nav(),

    % (Elem, AccIn) when is_integer(Elem) andalso is_map(AccIn) ->
    FoldFun =
        fun (Elem, AccIn) ->
            timer:sleep(SampleInterval),
            % T = node_util:maybe_get_time(),
            % T = calendar:local_time(), % Replace by erlang:monotonic_time(second) to reduce size
            [Pr, Tmp] = gen_server:call(Pid, {read, alt, [press_out, temp_out], #{}}),
            % logger:log(notice, "Getting data from nav sensor pr: ~p tmp: ~p", [Pr, Tmp]),
            #{press => [Pr] ++ maps:get(press, AccIn),
            temp => [Tmp] ++ maps:get(temp, AccIn),
            time => [erlang:monotonic_time(second)] ++ maps:get(time, AccIn)}
    end,

    M = lists:foldl(FoldFun, MeteoMap, SampleSeq),
    % logger:log(notice, "Done Sampling data"),

    T1Computation = erlang:monotonic_time(millisecond),

    [Pressures, Temperatures, Epochs] = maps:values(M),
    Result = #{measures => lists:zip3(Epochs, Pressures, Temperatures),
        pmean => 'Elixir.Numerix.Statistics':mean(Pressures),
        pvar => 'Elixir.Numerix.Statistics':variance(Pressures),
        tmean => 'Elixir.Numerix.Statistics':mean(Temperatures),
        tvar => 'Elixir.Numerix.Statistics':variance(Temperatures),
        cov => 'Elixir.Numerix.Statistics':covariance(Pressures, Temperatures)},

    T2Computation = erlang:monotonic_time(millisecond),
    lasp:update(node_util:atom_to_lasp_identifier(node(), state_gset), {add, Result}, self()),

    Cardinality = LoopCount-LoopCountRemaining+1,
    ComputationTime = T2Computation - T1Computation,
    NewAcc = maps:put(Cardinality, {T2Computation, ComputationTime}, AccComputations),

    if LoopCountRemaining > 1 ->
      MSF(LoopCountRemaining-1, NewAcc);
    true ->
      timer:sleep(30000), % Give time to the CAF process to finish receiving acks
      convergence_acknowledgement ! {done, NewAcc}
    end
  end,

  ConvergenceAcknowledgementFun = fun CA(Acks) ->
    receive
      {ack, From, Cardinality} ->
        TConverged = erlang:monotonic_time(millisecond),
        CA([{From, TConverged, Cardinality} | Acks]);
      {done, Computations} -> % Called by the meteo process once it has terminated
        Self ! {done, Computations, Acks}
    end
  end,

  logger:log(notice, "Spawning Acknowledgement receiver process"),
  % https://stackoverflow.com/questions/571339/erlang-spawning-processes-and-passing-arguments
  PidCAF = spawn(fun () -> ConvergenceAcknowledgementFun([]) end),
  register(convergence_acknowledgement, PidCAF),
  timer:sleep(20000),
  PidMSF = spawn(fun () -> MeteorologicalStatisticsFun(LoopCount, #{}) end),
  register(meteo_stats, PidMSF),
  register(meteo_task, self()),

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
        logger:log(info,"Wrote results to file. ~n"),
        grisp_led:color(2, red),
        timer:sleep(2000),
        exit(PidCAF, kill),
        exit(PidMSF, kill)
   end.
