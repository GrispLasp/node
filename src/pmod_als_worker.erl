-module(pmod_als_worker).

-behaviour(gen_server).

%% API
-export([start_link/0, terminate/0]).

%% Gen Server Callbacks
-export([code_change/3, handle_call/3, handle_cast/2,
	 handle_info/2, init/1, terminate/2]).

%% Records
-define(PMOD_ALS_RANGE, lists:seq(1, 255, 1)).

% -define(LUMINOSITY_LEVELS, [dark, shady, medium, bright, luminous] ).
% -define(LUMINOSITY_MAP, [lists:duplicate(51,X) || X <- ?LUMINOSITY_LEVELS ]).

-record(shade, {measurements = [], count = 0, avg = 0}).

% -record(shade, {
%     measurements = [],
%     count = 0,
%     spectrum_key
% }).

-record(state,
	{luminosity =
	     []}).        % [{dark, #shade{ lower_bound = 0, upper_bound = 51 }},
			  % {shady, #shade{ lower_bound = 52, upper_bound = 103 }},
			  % {medium, #shade{ lower_bound = 104, upper_bound = 155 }},
			  % {bright, #shade{ lower_bound = 156, upper_bound = 207 }},
			  % {luminous, #shade{ lower_bound = 208, upper_bound = 255 }}])
			  % ShadesRec = [#shade{spec = lists:sublist(Range, X, 51), cnt = 0} ||
			  % X <- lists:seq(1,length(Range),51),
			  % Y <- [dark, shady, medium, bright, luminous]].
			  % ShadesRec = [#shade{spec = lists:sublist(Range, X, 51), cnt = 0} ||
			  % X <- lists:seq(1,length(Range),51)].
			  %
			  % [lists:sublist(List, X, 51) || X <- lists:seq(1,length(List),51)],
			  % [#shade{X, Y} || X <- [1,2,3], Y <- [a,b]].
			  % [{#shade{ spectrum = lists:seq(0, 51) }, dark},
			  % {#shade{ spectrum = lists:seq(52, 103) }, shady},
			  % {#shade{ spectrum = lists:seq(104, 155) }, medium},
			  % {#shade{ spectrum = lists:seq(156, 207) }, bright},
			  % {#shade{ spectrum = lists:seq(208, 255) }, luminous}]

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
    logger:log(info, "Starting ambient light worker ~n"),
    application:set_env(grisp, devices, [{spi2, pmod_als}]),
    application:set_env(grisp, devices,
			[{uart, pmod_maxsonar}]),
    Shades = lists:duplicate(255, #shade{}),
    Range = lists:seq(1, 255, 1),
    List = lists:zipwith(fun (X, Y) -> {X, Y} end, Range,
			 Shades),
    Dict = dict:from_list(List),
    State = #state{luminosity = Dict},
    % State = #state{
    %   luminosity = dict:from_list(lists:zipwith(fun
    %     (Key, Shade) when is_record(Shade, shade) ->
    %       {Key, Shade}
    %   % end, [#shade{spectrum = lists:sublist(?PMOD_ALS_RANGE, X, 51)} || X <- lists:seq(1,length(?PMOD_ALS_RANGE),51)], lists:duplicate(255, #state{}) ))
    % end, ?PMOD_ALS_RANGE, lists:duplicate(255, #state{}) ))},
    % [{X, #shade{}} || X <- ]
    % State = #state{
    %     luminosity = dict:from_list()
    % }
    grisp_devices:setup(),
    % {ok, {#state{}}, 20000}.
    {ok, State, 20000}.

handle_call({set_gen_fun, _GenFun}, _From, State) ->
    % {ok, Functions} = lasp:query({<<"functions">>, state_orset}),
    % FunctionsList = sets:to_list(Functions),
    % case length(FunctionsList) of
    %   0 ->
    %     logger:log(info, "=== No other function is present in the CRDT, adding new gen fun ===~n"),
    %     lasp:update({<<"functions">>, state_orset}, {add, GenFun}, self());
    %   1 ->
    %     logger:log(info, "=== Another function is present in the CRDT, removing old fun and adding new one ===~n"),
    %     OldFun = hd(FunctionsList),
    %     lasp:update({<<"functions">>, state_orset}, {rmv, OldFun}, self());
    %   _ ->
    %     logger:log(info, "=== More then one function is present in the CRDT, a new function has been added recently
    %     and the previous one has not yet been removed, waiting for CRDT convergence ===~n")
    % end,
    {reply, ok, State, 5000};
handle_call({set_gen_fun}, _From, State) ->
    % InverseHyperbolicArctanFun = fun() -> logger:log(info, "atanh = ~f~n", [math:atanh(1 - (1/math:pow(6,20)))]) end,
    % lasp:update({<<"functions">>, state_orset}, {add, InverseHyperbolicArctanFun}, self()),
    % logger:log(info, "=== Added Hyperbolic Arctangent Function ===~n"),
    {reply, ok, State, 5000};
% handle_call({get_gen_fun}, _From, State) ->
%   % Function = get_gen_fun(),
%   {reply, Function, State, 5000};
handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_info(timeout, State) ->
    Raw = pmod_als:raw(),
    Sonar = pmod_maxsonar:get(),
    % Shade = dict:fetch(Raw, State#state.luminosity),
    % dict:update(Raw, fun(Shade) -> #shade{measurements = Shade#shade.measurements ++ [Raw], count = Shade#shade.count + 1})
    logger:log(info, "Raw = ~p ~n", [Raw]),
    logger:log(info, "Raw Sonar = ~p ~n", [Sonar]),
    dict:update(Raw,
		fun (Shade) ->
			#shade{measurements = Shade#shade.measurements ++ [Raw],
			       count = Shade#shade.count + 1}
		end,
		State#state.luminosity),
    % dict:update(State#state{spectrum = lists}, fun (Old) -> Old ++ [Val] end, [Val], D),
    %   dict:to_list(
    % 	dict:append(item, value,
    % 		dict:append(item, value2, dict:new())
    % 	)
    % ),
    % State#state.luminosity
    % lists:filtermap(fun
    %   (Raw) when is_integer(Raw) ->
    %     body
    % end, list1)
    % if
    %   lists:member(Raw, State#state.luminosity ->
    %     body
    % end
    % store_ambient_light(State#state.luminosity),
    % logger:log(info, "=== ALS raw value = ~p ~n", [Raw]),
    {noreply, State, 3000};
handle_info(Msg, State) ->
    logger:log(info, "=== Unknown message: ~p~n", [Msg]),
    {noreply, State}.

handle_cast(_Msg, State) -> {noreply, State}.

terminate(Reason, _S) ->
    logger:log(info, "=== Terminating ALS server (reason: "
	      "~p) ===~n",
	      [Reason]),
    ok.

code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%====================================================================
%% Internal functions
%%====================================================================
% store_ambient_light(LuminosityDict) ->
%   Shades = dict:to_list(LuminosityDict),
%   Ambient = lists:filter(pred, list1),
%   % dict:map(
%   % fun(K,V) ->
%   %
%   % end,
%   % LuminosityDict).
%   ok.
% [{dark, #shade{ spectrum = lists:seq(0, 51) }},
% {shady, #shade{ spectrum = lists:seq(52, 103) }},
% {medium, #shade{ spectrum = lists:seq(104, 155) }},
% {bright, #shade{ spectrum = lists:seq(156, 207) }},
% {luminous, #shade{ spectrum = lists:seq(208, 255) }}]
% append(Key, Val, D) ->
%     % dict:update(Key, fun (Old) -> Old ++ [Val] end, [Val], D).
%   Mapfun = fun(Shade) when is_tuple(Shade) andalso is_record(element(2, Tuple)) ->
%                 X + $A - $a;
%                 (X) -> X
%            end,
%   12> Upcase_word =
%         fun(X) ->
%           lists:map(Upcase, X)
%         end.
%   #Fun<erl_eval>
%   13> Upcase_word("Erlang").
%   "ERLANG"
%   14> lists:map(Upcase_word, L).
%   ["I","LIKE","ERLANG"]
%
% % part(List) ->
% %         part(List, []).
% % part([], Acc) ->
% %         lists:reverse(Acc);
% % part([H], Acc) ->
% %         lists:reverse([[H]|Acc]);
% % part([H1,H2|T], Acc) ->
% %         part(T, [[H1,H2]|Acc]).
%
%   14> lists:mapfoldl(fun(Word, Sum) ->
%   14>     {Upcase_word(Word), Sum + length(Word)}
%   14>              end, 0, L).
%   {["I","LIKE","ERLANG"],11}

