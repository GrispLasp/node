-module(node_server).

-behaviour(gen_server).

-include("node.hrl").

%% API
-export([start_link/1, start_worker/1, stop/0,
	 terminate_worker/1]).

-export([start_link/2]).

%% Gen Server Callbacks
-export([code_change/3, handle_call/3, handle_cast/2,
	 handle_info/2, init/1, terminate/2]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link(NodeSup) ->
    gen_server:start_link({local, node_server}, ?MODULE,
			  {NodeSup}, []).

start_link(NodeSup, Sensors) ->
    gen_server:start_link({local, node_server}, ?MODULE,
			  {NodeSup, Sensors}, []).

stop() -> gen_server:call(node_server, stop).

start_worker(WorkerType) when is_atom(WorkerType) ->
    gen_server:call(node_server,
		    {start_worker, WorkerType}).

terminate_worker(Pid) ->
    gen_server:call(node_server, {terminate_worker, Pid}).

%% ===================================================================
%% Gen Server callbacks
%% ===================================================================

init(NodeSup) ->
    logger:log(info, "Initializing Node Server~n"),
    process_flag(trap_exit,
		 true), %% Ensure Gen Server gets notified when his supervisor dies
    case NodeSup of
      {Supervisor} ->
	  self() ! {start_worker_supervisor, Supervisor};
      {Supervisor, _Sensors} ->
	  self() ! {start_worker_supervisor, Supervisor}
    end,
    {ok, #server_state{workers = gb_sets:empty()}}.

handle_call({start_worker, WorkerType}, _From,
	    S = #server_state{worker_sup = WorkerSup, workers = W}) ->
    logger:log(info, "=== Starting new worker (~p) ===~n",
	      [WorkerType]),
    case maps:get(WorkerType, ?WORKER_SPECS_MAP) of
      {badkey, _} ->
	  logger:log(info, "=== Worker Type not found in map ===~n"),
	  {reply, {badkey, worker_type_not_exist}, S};
      ChildSpec ->
	  logger:log(info, "=== Found Worker Spec ~p === ~n",
		    [ChildSpec]),
	  {ok, Pid} = supervisor:start_child(WorkerSup,
					     ChildSpec),
	  Ref = erlang:monitor(process, Pid),
	  {reply, {ok, Pid},
	   S#server_state{workers = gb_sets:add(Ref, W)}}
    end;
handle_call({terminate_worker, WorkerPid}, _From,
	    S = #server_state{worker_sup = WorkerSup}) ->
    logger:log(info, "=== Terminate worker (~p) ===~n",
	      [WorkerPid]),
    case supervisor:terminate_child(WorkerSup, WorkerPid) of
      {error, not_found} ->
	  logger:log(info, "=== Worker with PID ~p was not found "
		    "in the worker supervisor (pid: ~p) ===",
		    [WorkerPid, WorkerSup]),
	  {reply, {error, pid_not_found, WorkerPid}, S};
      ok -> {reply, {ok, killed, WorkerPid}, S}
    end;
handle_call(stop, _From, S) -> {stop, normal, ok, S};
handle_call(_Msg, _From, S) -> {noreply, S}.

handle_cast(_Msg, S) -> {noreply, S}.

handle_info({start_worker_supervisor, NodeSup},
	    S = #server_state{}) ->
    logger:log(info, "=== Start Node Worker Supervisor ===~n"),
    {ok, WorkerSupPid} = supervisor:start_child(NodeSup,
						?NODE_WORKER_SUP_SPEC),
    link(WorkerSupPid),
    logger:log(info, "=== PID of Node Worker Supervisor ~p "
	      "===~n",
	      [WorkerSupPid]),
    {noreply, S#server_state{worker_sup = WorkerSupPid}};
handle_info({'DOWN', Ref, process, Pid, Info},
	    S = #server_state{workers = Refs}) ->
    logger:log(info, "=== Worker ~p is dead (because of ~p), "
	      "removing him from workers set ===~n",
	      [Pid, Info]),
    case gb_sets:is_element(Ref, Refs) of
      true ->
	  erlang:demonitor(Ref),
	  {noreply, S#server_state{workers = gb_sets:delete(Ref, Refs)}};
      false -> {noreply, S}
    end;
handle_info({'EXIT', _From, Reason}, S) ->
    logger:log(info, "=== Supervisor sent an exit signal (reason: "
	      "~p), terminating Gen Server ===~n",
	      [Reason]),
    {stop, Reason, S};
handle_info(Msg, S) ->
    logger:log(info, "=== Unknown message: ~p~n", [Msg]),
    {noreply, S}.

terminate(normal, _S) ->
    logger:log(info, "=== Normal Gen Server termination ===~n"),
    ok;
terminate(shutdown, _S) ->
    logger:log(info, "=== Supervisor asked to terminate Gen "
	      "Server (reason: shutdown) ===~n"),
    ok;
terminate(Reason, _S) ->
    logger:log(info, "=== Terminating Gen Server (reason: "
	      "~p) ===~n",
	      [Reason]),
    ok.

code_change(_OldVsn, S, _Extra) -> {ok, S}.


%% ===================================================================
%% Internal functions
%% ===================================================================
