-module(node_sensor_client_worker).

-behaviour(gen_server).

%% API
-export([start_link/0, terminate/0]).

%% Gen Server Callbacks
-export([code_change/3, handle_call/3, handle_cast/2,
	 handle_info/2, init/1, terminate/2]).

%% Records
-record(state, {counter, temps}).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [],
			  []).

terminate() -> gen_server:call(?MODULE, {terminate}).

%% ===================================================================
%% Gen Server callbacks
%% ===================================================================

init([]) ->
    logger:log(info, "Starting a client for the sensor ~n"),
    % logger:log(info, "Adding node: ~p to the set clients ~n",[node()]),
    % Time = os:timestamp(),
    % lasp:update({<<"clients">>,state_orset},{add,{node(),Time}},self()),
    logger:log(info, "Creating a temperature sensor~n"),
    node_sensor_server_worker:creates(temp),
    {ok, #state{counter = 0, temps = []}, 30000}.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_info(timeout,
	    S = #state{counter = Counter, temps = Temps}) ->
    logger:log(info, "=== Counter is at ~p ===~n", [Counter]),
    logger:log(info, "=== Temp list : ~p ===~n", [Temps]),
    {NewCounter, NewTempList} = case Counter of
				  20 ->
				      logger:log(info, "=== Timer has ended, aggregating data "
						"and updating CRDT... === ~n"),
				      AverageTemp = average(Temps),
				      logger:log(info, "=== Average temp in past hour is ~p "
						"===~n",
						[AverageTemp]),
				      {ok, TempsCRDT} = lasp:query({<<"temp">>,
								    state_orset}),
				      TempsList = sets:to_list(TempsCRDT),
				      % logger:log(info, "=== Temps CRDT : ~p ===~n", [TempsList]),
				      OldCrdtData = [{Node, OldAvg, HourCounter}
						     || {Node, OldAvg,
							 HourCounter}
							    <- TempsList,
							Node =:= node()],
				      logger:log(info, "=== Old CRDT data is ~p ===~n",
						[OldCrdtData]),
				      case length(OldCrdtData) of
					0 ->
					    lasp:update({<<"temp">>,
							 state_orset},
							{add,
							 {node(), AverageTemp,
							  1}},
							self());
					1 ->
					    {Node, OldAvg, HourCounter} =
						hd(OldCrdtData),
					    NewAverageTemp = OldAvg *
							       HourCounter
							       /
							       (HourCounter + 1)
							       +
							       AverageTemp *
								 (1 /
								    (HourCounter
								       + 1)),
					    logger:log(info, "=== New average temp : ~p ===~n",
						      [NewAverageTemp]),
					    lasp:update({<<"temp">>,
							 state_orset},
							{rmv,
							 {Node, OldAvg,
							  HourCounter}},
							self()),
					    lasp:update({<<"temp">>,
							 state_orset},
							{add,
							 {node(),
							  NewAverageTemp,
							  HourCounter + 1}},
							self())
				      end,
				      {0, []};
				  _ ->
				      {AnswerTemp, Temp} =
					  node_sensor_server_worker:read(temp),
				      TempList = case AnswerTemp of
						   read -> Temps ++ [Temp];
						   sensor_not_created ->
						       exit(sensor_not_created)
						 end,
				      {Counter + 1, TempList}
				end,
    {noreply,
     S#state{counter = NewCounter, temps = NewTempList},
     30000};
handle_info(Msg, State) ->
    logger:log(info, "=== Unknown message: ~p~n", [Msg]),
    {noreply, State}.

handle_cast(_Msg, State) -> {noreply, State}.

terminate(Reason, _S) ->
    logger:log(info, "=== Terminating Sensor client Gen Server "
	      "(reason: ~p) ===~n",
	      [Reason]),
    ok.

code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%====================================================================
%% Internal functions
%%====================================================================
average(List) -> sum(List) / length(List).

sum([H | T]) -> H + sum(T);
sum([]) -> 0.
