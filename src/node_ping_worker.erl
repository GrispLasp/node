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
    erlang:send_after(5000, self(),
		      {full_ping}), %% Start full pinger after 5 seconds
    % self() ! {full_ping},
    {ok, []}.

handle_call({ping, Number, Timer}, _From,
	    CurrentList) ->
    logger:log(info, "=== Current list of Node pinged correctly "
	      "(~p) ===~n",
	      [CurrentList]),
    PingedNodes = ping(CurrentList, Number, partial),
    self() ! {timer, Timer},
    {reply, {ok, PingedNodes}, PingedNodes};
handle_call({terminate}, _From, CurrentList) ->
    logger:log(info, "=== Ping server terminates with Current "
	      "list of Node pinged correctly (~p) ===~n",
	      [CurrentList]),
    {reply, {terminate}, CurrentList};
handle_call(_Message, _From, CurrentList) ->
    {reply, {ok, CurrentList}, CurrentList}.

handle_info({full_ping}, CurrentList) ->
    logger:log(notice, "=== Starting a full ping ===~n"),
    T1 = os:timestamp(),
    PingedNodes = ping(CurrentList, 1, full),
    T2 = os:timestamp(),
    Time = timer:now_diff(T2, T1),
    logger:log(info, "=== Time to do a full ping ~ps ===~n",
	      [Time / 1000000]),
    logger:log(notice, "=== Nodes that answered back ~p ===~n",
	      [PingedNodes]),
    {noreply, PingedNodes, 30000};
handle_info(timeout, CurrentList) ->
    logger:log(notice, "=== Timeout of full ping, restarting "
	      "after 90s ===~n"),
    T1 = os:timestamp(),
    PingedNodes = ping(CurrentList, 1, full),
    T2 = os:timestamp(),
    Time = timer:now_diff(T2, T1),
    logger:log(info, "=== Time to do a full ping ~ps ===~n",
	      [Time / 1000000]),
    logger:log(notice, "=== Nodes that answered back ~p ===~n",
	      [PingedNodes]),
    {noreply, PingedNodes, 30000};
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
ping(PingList, N, Type) when N > 0 ->
    % List = [node@my_grisp_board_1,node@my_grisp_board_2,node@my_grisp_board_3,node@my_grisp_board_4,node@my_grisp_board_5,node@my_grisp_board_6,node@my_grisp_board_7,node@my_grisp_board_8,node@my_grisp_board_9,node@my_grisp_board_10,node@my_grisp_board_11,node@my_grisp_board_12],
    % List = [node@my_grisp_board_10,node@my_grisp_board_11,node@my_grisp_board_12],
    % List = ?BOARDS(?IGOR),
	Remotes = maps:fold(fun
		(K, V, AccIn) when is_list(V) ->
			AccIn ++ V
	end, [], node_config:get(remote_hosts, #{})),
    % List = (?BOARDS((?IGOR))) ++ ['nodews@Laymer-3'],
    % List = (?BOARDS((?DAN))) ++ Remotes,
		% List = ['node@GrispAdhoc', 'node2@GrispAdhoc'],
		List = (?BOARDS((?ALL))),
    % List = [generic_node_1@GrispAdhoc,generic_node_2@GrispAdhoc],
    ListWithoutSelf = lists:delete(node(), List),
    Ping = fun (X) -> net_adm:ping(X) == pong end,
    case Type of
      full -> ToPing = ListWithoutSelf;
      partial -> ToPing = PingList;
      _ -> ToPing = []
    end,
    ListToJoin = lists:filter(Ping, ToPing),
    if Type == full -> ping(ListToJoin, 0, full);
       true ->
	   % grisp_led:flash(1, blue, 500),
	   ping(ListToJoin, N - 1, partial)
    end;
ping(PingList, 0, _Type) ->
    % grisp_led:color(1, green),
    Join = fun (X) -> lasp_peer_service:join(X) end,
    lists:foreach(Join, PingList),
    PingList.
