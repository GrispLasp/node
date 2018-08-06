%%%-------------------------------------------------------------------
%% @doc node application public API
%% @end
%%%-------------------------------------------------------------------

% /!\ NOTE :
% 3.1 Timer Module
% Creating timers using erlang:send_after/3 and erlang:start_timer/3 , is much more efficient than using the timers provided by the timer module in STDLIB.
% The timer module uses a separate process to manage the timers.
% That process can easily become overloaded if many processes create and cancel timers frequently (especially when using the SMP emulator).
% The functions in the timer module that do not manage timers (such as timer:tc/3 or timer:sleep/1),
% do not call the timer-server process and are therefore harmless.

-module(node_app).

-behaviour(application).

-include("node.hrl").

%% Application callbacks
-export([start/2, stop/1]).

%% test call to Numerix
-export([myfit/0]).
-export([laspstream/1]).
-export([laspread/3]).
-export([add_task_meteo_union/0]).
-export([add_task_meteo/0]).



%%====================================================================
%% API
%%====================================================================
% TODO : find a way to exclude lager everywhere?, see commit below
% https://github.com/lasp-lang/lasp/pull/295/commits/e2f948f879145a5ff31cf5458201768ca97b406b

start(_StartType, _StartArgs) ->
    logger:log(notice, "Application Master starting Node app ~n"),
    {ok, Supervisor} = node:start(node),
    % application:ensure_all_started(os_mon),
    node_util:set_platform(),

    % {ok, F} = file:open("z", [write]),
    % group_leader(F, self()),
    % logger:log(notice"Where am I going to appear?~n"),
    start_timed_apps(),

    logger:log(notice, "Application Master started Node app ~n"),
    start_primary_workers(primary_workers),
    start_primary_workers(distributed_workers),
    % add_measurements(),

    LEDs = [1, 2],
    [grisp_led:flash(L, aqua, 500) || L <- LEDs],

    PeerConfig = lasp_partisan_peer_service:manager(),
    logger:log(notice, "The manager used is ~p ~n", [PeerConfig]),

    % node_generic_tasks_server:add_task({tasknav2, all, fun () -> logger:log(notice, "PRESS = ~p ~n", [pmod_nav(alt, [press_out])]) end }),
    % node_generic_tasks_worker:start_task(tasknav),


    % {_Task, _Targets, _Fun, _} = add_task_meteo(),
    % ?PAUSE10,
    % {_Task, _Targets, _Fun, _} = add_task_meteo_union(),

    {ok, Supervisor}.

%%--------------------------------------------------------------------

stop(_State) ->
    logger:log(notice, "Application Master has stopped app~n"), ok.

%%====================================================================
%% Internal functions
%%====================================================================

start_primary_workers(Workers) ->
    PrimaryWorkers = node_config:get(Workers, []),
    lists:foreach(fun(Worker) ->
                    node_server:start_worker(Worker)
                  end, PrimaryWorkers),
    node_util:printer(PrimaryWorkers, workers).

add_measurements() ->
    Measurements = node_config:get(node_sensor_server_worker_measurements, []),
    lists:foreach(fun(Type) ->
      node_sensor_server_worker:creates(Type)
    end, Measurements),
    node_util:printer(Measurements, measurements).

%% https://github.com/SpaceTime-IoT/erleans/blob/5ee956c3bc656558d56e611ca2b8b75b33ba0962/src/erleans_app.erl#L46
start_timed_apps() ->
  Apps = node_config:get(timed_apps, []),
  T1 = erlang:monotonic_time(second),
  Started = lists:foldl(fun(App, Acc) ->
                  case application:ensure_all_started(App) of
                      {ok, Deps} ->
                          [Deps | Acc];
                      {error, Reason} ->
                          logger:error("Could not start application
                            ~s: reason=~p", [App, Reason]),
                          Acc
                  end
                end, [], Apps),
              T2 = erlang:monotonic_time(second),
              Time = T2 - T1,
              logger:log(notice, "Time to start ~p ~n"
              "is approximately ~p seconds ~n",
              [Started, Time]).

%%====================================================================
%% Useful snippets
%%====================================================================

add_task1() ->
    Interval = node_config:get(temp_stream_interval, ?HMIN),
    node_generic_tasks_server:add_task({task1, all, fun () -> node_generic_tasks_functions:temp_sensor({0, []}, Interval) end }),
    node_generic_tasks_worker:start_task(task1).

add_task_meteo() ->
    % SampleCount = 30,
    % SampleInterval = ?FIVE,
    SampleCount = 50,
    SampleInterval = ?MIN,
    Trigger = 2,
    node_generic_tasks_server:add_task({tasknav, all, fun () -> node_generic_tasks_functions:meteorological_statistics(SampleCount,SampleInterval,Trigger) end }),
    node_generic_tasks_worker:start_task(tasknav).

add_task_meteo_union() ->
    % Union# = (Trigger# -1)
    Id = node_util:atom_to_lasp_id(union1),
    node_generic_tasks_server:add_task({taskunion, all, fun () -> node_generic_tasks_functions:statistics_union(Id) end }),
    node_generic_tasks_worker:start_task(taskunion).


myfit() ->
  {Intercept, Slope} = 'Elixir.Numerix.LinearRegression':fit([1.3, 2.1, 3.7, 4.2], [2.2, 5.8, 10.2, 11.8]),
  {Intercept, Slope}.
% Adding a new task in Lasp :
% node_generic_tasks_server:add_task({task1, all, fun () -> node_generic_tasks_functions:temp_sensor({0, []}, 3000) end }),
% node_generic_tasks_worker:start_task(task1),
% ets:new(Identifier, [ordered_set,named_table,public]).
% lasp:query({<<"meteostats">>,state_orset}).
% lasp:query({<<"node@Laymer">>,state_orset}).
% lasp:query({<<"union2">>,state_orset}).
% lasp:query({<<"chunks">>,state_orset}).
% Generate mock temperature measurements
% Id = {<<"union2">>,state_orset}.
% node_generic_tasks_server:add_task({taskunion, all, fun () -> node_generic_tasks_functions:statistics_union(Id) end }).
% node_generic_tasks_worker:start_task(taskunion).
% node_sensor_server_worker:creates(temp),
% lasp:union({<<"node2@Laymer">>, state_orset}, {<<"node3@Laymer">>, state_orset}, UnionId).
% lasp:declare({<<"union2">>,state_orset},state_orset).
% lasp:union({<<"node@Laymer">>, state_orset}, {<<"union">>, state_orset}, {<<"union2">>,state_orset}).
laspstream(Name) ->
    % [H|T] = lasp:query(Id),
    Id = node_util:atom_to_lasp_id(Name),
    lasp:stream(Id, fun
        (_X) ->
            logger:log(notice, "Chunks updated ~n")
    end).


laspread(Name,Type,Value) ->
    % [H|T] = lasp:query(Id),
    % F = fun(N,T,V) ->
    % end,
    % spawn(?MODULE, fun(N,T,V) ->
    %     Id = node_util:atom_to_lasp_identifier(N,T),
    %     lasp:read(Id, {value, V}),
    %     io:format("3 chunks collected!")
    % end, [Name,Type,Value]).
    % spawn(lasp, read, [Id,{value, Value}]).
    % node_app:laspread(name,val,type).
    spawn(fun() ->
        % Id = node_util:atom_to_lasp_identifier(chunks,state_gcounter),
        Id = node_util:atom_to_lasp_identifier(executors,state_gset),
        % NOTE : lasp:read() WILL block current process regardless
        % if the minimim value has been reached, must ALWAYS be spawned in subprocess
        lasp:read(Id, {cardinality, 3}),
        io:format("3 chunks visible ~n"),
        {ok, Set} = lasp:query({"<<meteostats>>", state_orset}),
        % {ok, Set} = lasp:query({"<<executors>>", state_gset}),
        io:format("Values = ~p ~n", sets:to_list(Set))
    end).
    % spawn(fun() -> lasp:read({"<<executors>>", state_gset}, {cardinality, 10}), io:format("hi !~n") end).
    % is_process_alive(<0.1114.0>).
    % {ok, Set} = lasp:query(Id),
    % UniondId = hd(node_util:declare_crdts([union])),
    %
    % [ lasp:union(Elem, UniondId, UniondId) || Elem <- sets:to_list(Set) ].
    % Fun = fun
    %     (Elem) ->
    %         lasp:union(Elem, UniodId, UnionId)
    % end,
    % lists:foreach(Fun, L).
