-module(node).

%% API
-export([kill_worker/1, start/0, start/1,
	 start_all_workers/0, start_lasp/0, start_node/0,
	 start_partisan/0, start_worker/1, stop_child/1,
	 stop_server/0, terminate_worker/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start() -> node_supersup:start_link().

start(all) ->
    logger:log(info, "Starting Partisan, Lasp and Node~n"),
    node_supersup:start_link(all);
start(node) ->
    logger:log(info, "Starting Node~n"),
    node_supersup:start_link(node).

start_node() ->
    logger:log(info, "Starting Node Supervisor~n"),
    node_supersup:start_node().

start_partisan() ->
    logger:log(info, "Starting Partisan~n"),
    node_supersup:start_partisan().

start_lasp() ->
    logger:log(info, "Starting Lasp~n"),
    node_supersup:start_lasp().

stop_child(Name) -> node_supersup:stop_child(Name).

stop_server() -> node_server:stop().

start_all_workers() ->
    node_server:start_worker(pinger_worker),
    node_server:start_worker(sensor_server_worker),
    node_server:start_worker(sensor_client_worker),
    node_server:start_worker(generic_worker).

start_worker(WorkerType) ->
    node_server:start_worker(WorkerType).

terminate_worker(Pid) ->
    node_server:terminate_worker(Pid).

kill_worker(Pid) -> exit(Pid, kill).
