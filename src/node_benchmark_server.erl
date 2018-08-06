-module(node_benchmark_server).

-behaviour(gen_server).

-include_lib("node.hrl").

%% API
-export([start_link/0, terminate/0]).
-export([benchmark_meteo_task/0]).

%% Gen Server Callbacks
-export([code_change/3, handle_call/3, handle_cast/2,
	 handle_info/2, init/1, terminate/2]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [],
			  []).

benchmark_meteo_task() -> gen_server:call(?MODULE, {benchmark_meteo_task}).

terminate() -> gen_server:call(?MODULE, {terminate}).

%% ===================================================================
%% Gen Server callbacks
%% ===================================================================



init([]) ->
  logger:log(notice, "Starting a node benchmark server"),
  erlang:send_after(60000, self(), {benchmark_meteo_task}),
	{ok, {}}.


handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.


handle_info({benchmark_meteo_task}, State) ->

  EvaluationMode = node_config:get(evaluation_mode, grisplasp),
  logger:log(notice, "=== Starting meteo task benchmark in mode ~p ===~n", [EvaluationMode]),
  SampleCount = 3,
  SampleInterval = ?MIN,
  node_generic_tasks_server:add_task({tasknav, all, fun () ->
    case EvaluationMode of
      grisplasp ->
				NodesWithoutMe = lists:delete(node(),?BOARDS(?ALL)),
				logger:log(notice, "Node list ~p", [NodesWithoutMe]),
				lists:foreach(fun (Node) ->
					logger:log(notice, "Spawning listener for  ~p", [node_util:atom_to_lasp_id(Node)]),
					spawn(fun() ->
						% {strict, undefined} as the value parameter of lasp:read allows us to
						% block until a CRDT's variable is bound. We spawn this in a new process
						% as lasp:read is a blocking function. Upon detecting that a CRDT is bound, we know that
						% the meteorological stats for the Node X has converged on the currently listening node
						% and we call a remote process waiting for convergence acknowledgements on the Node X.
						% Node X will detect the time it received an ack and will know approximately how long it took
						% for the convergence to happen (minus the remote process call latency time).
	  				ConvergedValue = lasp:read(node_util:atom_to_lasp_id(Node),{strict, undefined}),
						logger:log(notice, "Data from node ~p converged on our node! Sending Acknowledgement", [Node]),
						{convergence_acknowledgement, Node} ! {ack, node()}
					end)
				end, NodesWithoutMe),
        node_generic_tasks_functions_benchmark:meteorological_statistics_grisplasp(SampleCount,SampleInterval);
      cloudlasp ->
        node_generic_tasks_functions_benchmark:meteorological_statistics_cloudlasp(SampleCount,SampleInterval);
      xcloudlasp ->
        node_generic_tasks_functions_benchmark:meteorological_statistics_xcloudlasp(SampleCount,SampleInterval)
      end
   end }),
  node_generic_tasks_worker:start_task(tasknav),
  {noreply, State};

handle_info(Msg, State) ->
    logger:log(info, "=== Unknown message: ~p~n", [Msg]),
    {noreply, State}.

handle_cast(_Msg, State) -> {noreply, State}.

terminate(Reason, _S) ->
    logger:log(info, "=== Terminating node benchmark server (reason: ~p) ===~n",[Reason]),
    ok.

code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%====================================================================
%% Internal functions
%%====================================================================
