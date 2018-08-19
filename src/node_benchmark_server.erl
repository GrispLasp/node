-module(node_benchmark_server).

-behaviour(gen_server).

-include_lib("node.hrl").

%% API
-export([start_link/0, terminate/0]).
-export([benchmark_meteo_task/1]).

%% Gen Server Callbacks
-export([code_change/3, handle_call/3, handle_cast/2,
   handle_info/2, init/1, terminate/2]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [],
        []).

benchmark_meteo_task(LoopCount) -> gen_server:call(?MODULE, {benchmark_meteo_task, LoopCount}).

terminate() -> gen_server:call(?MODULE, {terminate}).

%% ===================================================================
%% Gen Server callbacks
%% ===================================================================



init([]) ->
  logger:log(notice, "Starting a node benchmark server"),
	Loop = node_config:get(loopcount, 10),
  DataLoop = node_config:get(dataloop,100),
  erlang:send_after(60000, self(), {benchmark_meteo_task, Loop,DataLoop}),
  {ok, {}}.


handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.


handle_info({benchmark_meteo_task, LoopCount,DataCount}, State) ->
  EvaluationMode = node_config:get(evaluation_mode, grisplasp),
  logger:log(warning, "=== Starting meteo task benchmark in mode ~p ===~n", [EvaluationMode]),
  SampleCount = 5,
  SampleInterval = 5000,
  TaskName = list_to_atom(string:concat("tasknav",atom_to_list(node()))),
  node_generic_tasks_server:add_task({TaskName, node(), fun () ->
    case EvaluationMode of
      grisplasp ->
        % NodeList = [node@GrispAdhoc,node2@GrispAdhoc],
        % NodesWithoutMe = lists:delete(node(),NodeList),
        NodesWithoutMe = lists:delete(node(),?BOARDS(?DAN)),
        % logger:log(notice, "Node list ~p", [NodesWithoutMe]),
        lists:foreach(fun (Node) ->
          logger:log(notice, "Spawning listener for  ~p", [node_util:atom_to_lasp_identifier(Node, state_gset)]),
          spawn(fun() ->
            lists:foreach(fun(Cardinality) ->
              lasp:read(node_util:atom_to_lasp_identifier(Node, state_gset), {cardinality, Cardinality}),
              % logger:log(notice, "CRDT with cardinality ~p from node ~p converged on our node! Sending Acknowledgement", [Cardinality, Node]),
              {convergence_acknowledgement, Node} ! {ack, node(), Cardinality}
            end, lists:seq(1, LoopCount))
          end)
        end, NodesWithoutMe),
        node_generic_tasks_functions_benchmark:meteorological_statistics_grisplasp(LoopCount, SampleCount, SampleInterval);
      cloudlasp ->
        logger:log(warning, "starting meteo cloud lasp task ~n"),
        node_generic_tasks_functions_benchmark:meteorological_statistics_cloudlasp(LoopCount);
      xcloudlasp ->
        node_generic_tasks_functions_benchmark:meteorological_statistics_xcloudlasp(DataCount,LoopCount);
      backupxcloudlasp ->
        logger:log(warning,"Waiting for update to happen on otasknavther server");

      backupcloudlasp ->
        logger:log(warning,"Waiting for update to happen on otasknavther server")


      end
   end }),

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
