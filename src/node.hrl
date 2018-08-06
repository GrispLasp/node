%%%-------------------------------------------------------------------
%% @doc node constants definitions
%% @end
%%%-------------------------------------------------------------------

-include_lib("kernel/include/file.hrl").

%%====================================================================
%% Defaults
%%====================================================================

-define(PMOD_ALS_RANGE, lists:seq(1, 255, 1)).
-define(ALS_DEFAULT_RATE,   ?HMIN).
-define(ALS_DEFAULT_PROPAGATION_TRESHOLD,   20).
-define(ALS_RAW,    case application:get_env(node, emulate_als, false) of
    true ->
        rand:uniform(length(?PMOD_ALS_RANGE));
    _ ->
        pmod_als:raw()
end).

%%====================================================================
%% Time Intervals (ms)
%%====================================================================

-define(MS,             20).
-define(ONE,          1000).
-define(THREE,        3000).
-define(FIVE,         5000).
-define(TEN,         10000).
-define(HMIN,        30000).
-define(MIN,         60000).

%%====================================================================
%% Timers
%%====================================================================

% -define(TIME_MULTIPLIER,      lists:last(tuple_to_list(application:get_env(node, time_multiplier, 1)))).
-define(TIME_MULTIPLIER,          application:get_env(node, time_multiplier, 1)).
-define(SLEEP(Interval),        timer:sleep((round(Interval/?TIME_MULTIPLIER)))).

-define(PAUSEMS,                     ?SLEEP(?MS)).
-define(PAUSE1,                     ?SLEEP(?ONE)).
-define(PAUSE3,                   ?SLEEP(?THREE)).
-define(PAUSE5,                    ?SLEEP(?FIVE)).
-define(PAUSE10,                    ?SLEEP(?TEN)).
-define(PAUSEHMIN,                 ?SLEEP(?HMIN)).
-define(PAUSEMIN,                   ?SLEEP(?MIN)).

%%====================================================================
%% Conversions
%%====================================================================

-define(TOS(Ms),   Ms/?ONE).

%%====================================================================
%% Records
%%====================================================================

-record(shade, {
    measurements = [],
    count = 0
}).

-record(server_state, {
    worker_sup,
    workers
}).

-record(gentasks_state, {
    tasksets
}).

%%====================================================================
%% GRiSP Board References
%%====================================================================


-define(ALL,     lists:seq(1,2) ).
-define(ALEX,     lists:seq(1,6,1) ).
-define(DAN,      lists:seq(1,2,3) ).
-define(IGOR,   lists:seq(10,12,1) ).

% -define(BOARDS(Name),   [ list_to_atom(lists:flatten(unicode:characters_to_list(["node@my_grisp_board", "_", integer_to_list(X)], utf8))) || X <- Name ] ).
-define(BOARDS(Name),   [ list_to_atom(unicode:characters_to_list(["node@my_grisp_board", "_", integer_to_list(X)], utf8)) || X <- Name ] ).

%%====================================================================
%% Child Specifications
%%====================================================================

-define(NODE_WORKER_SUP_SPEC,
	#{id => node_worker_sup,
	  start => {node_worker_sup, start_link, []},
	  restart => temporary, type => supervisor,
	  shutdown => 15000, modules => [node_worker_sup]}).

-define(PINGER_SPEC,
	#{id => node_ping_worker,
	  start => {node_ping_worker, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_ping_worker]}).

-define(SENSOR_SERVER_SPEC,
	#{id => node_sensor_server_worker,
	  start => {node_sensor_server_worker, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_sensor_server_worker]}).

-define(SENSOR_CLIENT_SPEC,
	#{id => node_sensor_client_worker,
	  start => {node_sensor_client_worker, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_sensor_client_worker]}).

-define(GENERIC_SERVER_SPEC,
	#{id => node_generic_server_worker,
	  start => {node_generic_server_worker, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_generic_server_worker]}).

-define(GENERIC_TASKS_SERVER_SPEC,
	#{id => node_generic_tasks_server,
	  start => {node_generic_tasks_server, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_generic_tasks_server]}).

-define(PMOD_ALS_WORKER_SPEC,
	#{id => pmod_als_worker,
	  start => {pmod_als_worker, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill, modules => [pmod_als_worker]}).

-define(GENERIC_TASKS_WORKER_SPEC,
	#{id => node_generic_tasks_worker,
	  start => {node_generic_tasks_worker, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_generic_tasks_worker]}).

-define(NODE_STREAM_WORKER_SPEC(Mode),
	#{id => node_stream_worker,
	  start => {node_stream_worker, start_link, [Mode]},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_stream_worker]}).

-define(NODE_UTILS_SPEC,
	#{id => node_utils_server,
	  start => {node_utils_server, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_utils_server]}).

-define(NODE_STORAGE_SPEC,
	#{id => node_storage_server,
	  start => {node_storage_server, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_storage_server]}).

-define(NODE_BENCHMARK_SPEC,
	#{id => node_benchmark_server,
	  start => {node_benchmark_server, start_link, []},
	  restart => permanent, type => worker,
	  shutdown => brutal_kill,
	  modules => [node_benchmark_server]}).

-define(WORKER_SPECS_MAP,
  #{generic_worker => ?GENERIC_SERVER_SPEC,
    generic_tasks_server => ?GENERIC_TASKS_SERVER_SPEC,
    generic_tasks_worker => ?GENERIC_TASKS_WORKER_SPEC,
    pinger_worker => ?PINGER_SPEC,
    sensor_server_worker => ?SENSOR_SERVER_SPEC,
    pmod_als_worker => ?PMOD_ALS_WORKER_SPEC,
    node_stream_worker => ?NODE_STREAM_WORKER_SPEC(board),
    node_stream_worker_emu => ?NODE_STREAM_WORKER_SPEC(emu),
    sensor_client_worker => ?SENSOR_CLIENT_SPEC,
    node_utils_server => ?NODE_UTILS_SPEC,
    node_storage_server => ?NODE_STORAGE_SPEC,
    node_benchmark_server => ?NODE_BENCHMARK_SPEC}).
