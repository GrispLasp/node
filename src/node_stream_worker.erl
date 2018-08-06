%%%-------------------------------------------------------------------
%% @author Igor Kopestenski <i.kopest@gmail.com>
%%   [https://github.com/Laymer/GrispLasp]
%% @doc This is a <em>simulation sensor data stream</em> module.
%% @end
%%%-------------------------------------------------------------------

-module(node_stream_worker).

-behaviour(gen_server).

-include("node.hrl").

%% API
-export([get_data/0, refresh_webserver/0, start_link/0,
	 start_link/1]).

%% Gen Server Callbacks
-export([code_change/3, handle_call/3, handle_cast/2,
	 handle_info/2, init/1, terminate/2]).

-compile({nowarn_export_all}).

-compile(export_all).

%%====================================================================
%% Macros
%%====================================================================


%%====================================================================
%% Records
%%====================================================================

% NOTE : prepend atom to list to avoid ASCII representation of integer lists
% -record(state,
% 	{luminosity = [lum], sonar = [son], gyro = [gyr]}).
-record(state, {luminosity = [], lasp_id = {}, interval = [], treshold = []}).
% -record(state,
				  % 	{luminosity = #{}, sonar = [], gyro = []}).

%%====================================================================
%% API
%%====================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [],
			  []).

start_link(Mode) ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, {Mode},
			  []).

get_data() -> gen_server:call(?MODULE, {get_data}).

refresh_webserver() ->
    'Webserver.NodeClient':get_nodes().

%%====================================================================
%% Gen Server Callbacks
%%====================================================================

init({Mode}) ->
    _ = rand:seed(exsp),
	% Id = node_util:atom_to_lasp_identifier(states, state_orset).
	[{ok, {Id, _Type, _Metadata, _Value}}] = node_util:declare_crdts([states]),
	% NOTE : declaring interval and treshold during initialization to
	% avoid fetching application environment variables during every
	% singe request handling.
	Interval = node_config:get(als_stream_interval, ?ALS_DEFAULT_RATE),
	Treshold = node_config:get(als_propagation_treshold, ?ALS_DEFAULT_PROPAGATION_TRESHOLD),
    State = #state{luminosity = [], lasp_id = Id, interval = Interval, treshold = Treshold},
    case Mode of
      emu ->
		  logger:log(info, "Starting Emulated stream worker ~n"),
		  % flood(),
		  {ok, State};
      board ->
		  logger:log(info, "Starting stream worker on GRiSP ~n"),
		  {ok, State, ?TEN};
      % {ok, NewMap, 10000};
      _ -> {stop, unknown_launch_mode}
    end.

%%--------------------------------------------------------------------

handle_call({Request}, _From,
	    State = #state{luminosity = Lum}) ->
    case Request of
      % guard clause for snippet
      get_data when is_atom(get_data) ->
	  {reply, {ok, {Lum}}, State = #state{luminosity = Lum}};
      _ -> {reply, unknown_call, State}
    end;
handle_call(_Request, _From, State) ->
    {reply, ignored, State}.

%%--------------------------------------------------------------------

handle_cast(_Msg, State) -> {noreply, State}.

%%--------------------------------------------------------------------

handle_info(timeout,
	    _State = #state{luminosity = Lum, lasp_id = Id, interval = Interval, treshold = Treshold}) ->
	{{Y, Mo, D}, {H, Mi, S}} = maybe_get_time(),
	Raw = {?ALS_RAW, {{Y, Mo, D}, {H, Mi, S}}},
    % Raw = {pmod_als:raw(), {{Y, Mo, D}, {H, Mi, S}}},
    % Raw = pmod_als:raw(),
    NewLum = Lum ++ [Raw],
    NewState = #state{luminosity = NewLum, lasp_id = Id, interval = Interval, treshold = Treshold},
		% Interval = node_config:get(als_stream_interval, ?PMOD_ALS_REFRESH_RATE),
	erlang:send_after(Interval, self(), states),
    {noreply, NewState};
handle_info(states,
	    _State = #state{luminosity = Lum, lasp_id = Id, interval = Interval, treshold = Treshold}) ->
	{{Y, Mo, D}, {H, Mi, S}} = maybe_get_time(),
    Raw = {?ALS_RAW, {{Y, Mo, D}, {H, Mi, S}}},
    % Raw = pmod_als:raw(),
    NewLum = Lum ++ [Raw],
	NewState = if
		length(NewLum) >= Treshold ->
			ok = store_state(Interval, Id, #state{luminosity = NewLum, lasp_id = Id}, node(), self()),
			#state{luminosity = [], lasp_id = Id, interval = Interval, treshold = Treshold};
		true ->
			#state{luminosity = NewLum, lasp_id = Id, interval = Interval, treshold = Treshold}
	end,
	%
    % ok = store_state(Interval, Id,
	% 	     NewState, node(), self()),
	erlang:send_after(Interval, self(), states),
    {noreply, NewState};
handle_info(_Info, State) -> {noreply, State}.
% handle_info(grow_states,
% 	    _State = #state{luminosity = Lum, lasp_id = Id, interval = Interval, treshold = Treshold}) ->
% 	{{Y, Mo, D}, {H, Mi, S}} = maybe_get_time(),
%     Raw = {pmod_als:raw(), {{Y, Mo, D}, {H, Mi, S}}},
%     % Raw = pmod_als:raw(),
%     NewLum = Lum ++ [Raw],
% 	NewState = #state{luminosity = NewLum, lasp_id = Id, interval = Interval, treshold = Treshold},
% 	if
% 		lists:flatlength(NewLum) >= 20 ->
% 			ok = store_state(Interval, Id, NewState, node(), self()),
% 			body
% 	end
%     ok = store_state(Interval, Id,
% 		     NewState, node(), self()),
%     {noreply, NewState};

%%--------------------------------------------------------------------

terminate(_Reason, _State) -> ok.

%%--------------------------------------------------------------------

code_change(_OldVsn, State, _Extra) -> {ok, State}.

%%====================================================================
%% Internal functions
%%====================================================================

stream_data(Rate, Sensor) ->
    erlang:send_after(Rate, self(), Sensor), ok.

%%--------------------------------------------------------------------
store_data(Rate, Type, SensorData, Node, Self,
	   BitString) ->
    ?PAUSE10,
    {ok, Set} = lasp:query({BitString, state_orset}),
    L = sets:to_list(Set),
    case length(L) of
      1 ->
	  % H = hd(L),
	  lasp:update({BitString, state_orset}, {rmv, {Node, L}},
		      Self),
	  lasp:update({BitString, state_orset},
		      {add, {Node, SensorData}}, Self);
      0 ->
	  lasp:update({BitString, state_orset},
		      {add, {Node, SensorData}}, Self),
	  ok;
      _ -> ok
    end,
    % erlang:send_after(Rate, Self, Type),
    ok.

% store_state(Rate, Id, State, Node, Self) ->
store_state(_Rate, Id, State, Node, Self) ->
    % logger:log(info, "State ~p ~n", [State]),
    % BitString = atom_to_binary(Type, latin1),
    {ok, Set} = lasp:query(Id),
    L = sets:to_list(Set),
    MapReduceList = lists:filtermap(fun (Elem) ->
					    case Elem of
					      {Node,
					       _S = #state{luminosity =
							       _Lum, lasp_id = _Id}} ->
						  {true, {Node, State}};
					      _ -> false
					    end
				    end,
				    L),
    case length(L) of
      0 ->
		  lasp:update(Id,
			      {add, {Node, State}}, Self),
		  ok;
      1 when length(MapReduceList) > 0 ->
		  Leaving = hd(L),
		  H = hd(MapReduceList),
		  lasp:update(Id, {rmv, Leaving},
			      Self),
		  lasp:update(Id, {add, H}, Self);
      _ -> ok
    end,
    % erlang:send_after(Rate, Self, states),
    ok.


%% @doc Returns actual time and date if available from the webserver, or the local node time and date.
%%
%%      The GRiSP local time is always 1-Jan-1988::00:00:00
%%      once the board has booted. Therefore the values are irrelevant
%%		and cannot be compared between different boards as nodes
%%		do not boot all at the same time, or can reboot.
%%      But if a node can fetch the actual time and date from a remote server
%%		at least once, the local values can be used as offsets.
% -spec maybe_get_time() -> calendar:datetime().
-spec maybe_get_time() -> Time :: calendar:datetime().
	% ; maybe_get_time(Arg :: term()) -> calendar:datetime().
maybe_get_time() ->
	WS = application:get_env(node, webserver_host),
	maybe_get_time(WS).

-spec maybe_get_time(Args) -> Time :: calendar:datetime() when Args :: tuple()
	; (Arg) -> Time :: calendar:datetime() when Arg :: atom().
maybe_get_time({ok, WS}) ->
	Res = rpc:call(WS, calendar, local_time, []),
	maybe_get_time(Res);

maybe_get_time(undefined) ->
	logger:log(info, "No webserver host found in environment, local time will be used ~n"),
	maybe_get_time(local);

maybe_get_time({{Y,Mo,D},{H,Mi,S}}) ->
	{{Y,Mo,D},{H,Mi,S}};

maybe_get_time({badrpc, Reason}) ->
	logger:log(info, "Failed to get local time from webserver ~n"),
	logger:log(info, "Reason : ~p ~n", [Reason]),
	maybe_get_time(local);

maybe_get_time(local) ->
	calendar:local_time().
