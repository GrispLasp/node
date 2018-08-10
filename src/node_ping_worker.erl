-module(node_ping_worker).

-behaviour(gen_server).

%% API
-export([full_ping/0, ping/1, start_link/0,
	 terminate/0]).

%% Gen Server Callbacks
-export([code_change/3, handle_call/3, handle_cast/2,
	 handle_info/2, init/1, terminate/2]).

-include("node.hrl").

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, node_ping_worker},
			  ?MODULE, {}, []).

ping(N) ->
    gen_server:call(node_ping_worker, {ping, N}, infinity).

full_ping() ->
    gen_server:call(node_ping_worker, {full_ping},
		    infinity).

terminate() ->
    gen_server:cast(node_ping_worker, {terminate}).

%% ===================================================================
%% Gen Server callbacks
%% ===================================================================

init({}) ->
    logger:log(info, "Initializing Node Pinger~n"),
    process_flag(trap_exit,
		 true), %% Ensure Gen Server gets notified when his supervisor dies
    erlang:send_after(30000, self(),
		      {full_ping}), %% Start full pinger after 5 seconds
    % self() ! {full_ping},
    {ok, []}.

handle_call({terminate}, _From, CurrentList) ->
    logger:log(info, "=== Ping server terminates with Current "
	      "list of Node pinged correctly (~p) ===~n",
	      [CurrentList]),
    {reply, {terminate}, CurrentList};
handle_call(_Message, _From, CurrentList) ->
    {reply, {ok, CurrentList}, CurrentList}.

handle_info({full_ping}, CurrentList) ->
    logger:log(info, "=== Starting a full ping ===~n"),
    T1 = os:timestamp(),
    PingedNodes = ping(),
    T2 = os:timestamp(),
    Time = timer:now_diff(T2, T1),
    logger:log(info, "=== Time to do a full ping ~ps ===~n",
	      [Time / 1000000]),
    logger:log(notice, "=== Nodes that answered back ~p ===~n",
	      [PingedNodes]),
    {noreply, PingedNodes, 60000};
handle_info(timeout, CurrentList) ->
    logger:log(info, "=== Timeout of full ping, restarting "
	      "after 90s ===~n"),
    T1 = os:timestamp(),
    PingedNodes = ping(),
    T2 = os:timestamp(),
    Time = timer:now_diff(T2, T1),
    logger:log(info, "=== Time to do a full ping ~ps ===~n",
	      [Time / 1000000]),
    logger:log(notice, "=== Nodes that answered back ~p ===~n",
	      [PingedNodes]),
    {noreply, PingedNodes, 60000};
handle_info(Msg, CurrentList) ->
    logger:log(info, "=== Unknown message: ~p~n", [Msg]),
    {noreply, CurrentList}.

handle_cast(_Message, CurrentList) ->
    {noreply, CurrentList}.

terminate(_Reason, _CurrentList) -> ok.

code_change(_OldVersion, CurrentList, _Extra) ->
    {ok, CurrentList}.

%%====================================================================
%% Internal functions
%%====================================================================

%% @doc Macros are defined in node.hrl
%% so calling ?BOARDS() with <em>?DAN</em> argument
%% will return a list of the hostnames of the boards Dan usually runs
%% deafult macros are : ?ALL,?ALEX,?DAN,?IGOR
%% but ?BOARDS(X) will return a list of hostnames
%% with any other supplied sequence
%% @end
ping() ->
	Remotes = maps:fold(fun
		(K, V, AccIn) when is_list(V) ->
			AccIn ++ V
	end, [], node_config:get(remote_hosts, #{})),
    % List = (?BOARDS((?IGOR))) ++ ['nodews@Laymer-3'],

		% List = Remotes,

		List = (?BOARDS((?DAN))),
    % List = [node@GrispAdhoc,node2@GrispAdhoc],
		% List =  (?BOARDS(?ALL)) ++ Remotes,
    ListWithoutSelf = lists:delete(node(), List),
		lists:foldl(fun (Node, Acc) ->
			case net_adm:ping(Node) of
				pong ->
					IsARemote = lists:member(Node, Remotes),
					if IsARemote == true ->
						logger:log(info, "=== Node ~p is an aws server", [Node]),
						Acc ++ [Node];
					true ->
						logger:log(info, "=== Attempting to join the node ~p with lasp", [Node]),
						lasp_peer_service:join(Node),
						Acc ++ [Node]
					end;
				pang ->
					logger:log(info, "=== Node ~p is unreachable", [Node]),
					Acc
			end
		end, [],  ListWithoutSelf).
