-module(node_supersup).

-behavior(supervisor).

%% API
-export([delete_child/1, set_config/0, start_lasp/0,
	 start_link/0, start_link/1, start_node/0,
	 start_partisan/0, stop_and_delete_child/1,
	 stop_child/1]).

%% Supervisor callbacks
-export([init/1]).

%% Macros

-define(PARTISAN_SPEC,
	#{id => partisan_sup,
	  start => {partisan_sup, start_link, []},
	  restart => permanent, type => supervisor,
	  shutdown => 15000, modules => [partisan_sup]}).

-define(LASP_SPEC,
	#{id => lasp_sup, start => {lasp_sup, start_link, []},
	  restart => permanent, type => supervisor,
	  shutdown => 15000, modules => [lasp_sup]}).

%-define(LASPPG_SPEC,
%                    #{id => lasp_pg_sup,
%                        start => {lasp_pg_sup, start_link, []},
%                        restart => permanent,
%                        type => supervisor,
%                        shutdown => 15000,
%                        modules => [lasp_pg_sup]}).

% -define(SENSORS_SETUP, true).
-ifdef(SENSORS_SETUP).

-define(PMOD_ALS(Slot), {Slot, pmod_als}).

-define(SENSORS, [{sensors, [?PMOD_ALS(spi2)]}]).

-else.

-define(SENSORS, []).

-endif.

% -define(NODE_SPEC,
%                       #{id => node_sup,
%                       start => {node_sup, start_link, ?SENSORS},
%                       restart => permanent,
%                       type => supervisor,
%                       shutdown => 15000,
%                       modules => [node_sup]}).
-define(NODE_SPEC,
	#{id => node_sup, start => {node_sup, start_link, []},
	  restart => permanent, type => supervisor,
	  shutdown => 15000, modules => [node_sup]}).

%% ===================================================================
%% API functions
%% ===================================================================

set_config() ->
    %% Note: Use app environments variables in config/sys.config instead
    % partisan_config:set(partisan_peer_service_manager, partisan_hyparview_peer_service_manager),
    partisan_config:set(partisan_peer_service_manager,
			partisan_hyparview_peer_service_manager),
    % partisan_config:set(peer_port, 50000),
    ok.

start_link() ->
    % set_config(),
    supervisor:start_link({local, node}, ?MODULE, []).

start_link(Args) ->
    set_config(),
    supervisor:start_link({local, node}, ?MODULE, Args).

start_node() ->
    {ok, NodeSup} = supervisor:start_child(node,
					   ?NODE_SPEC),
    {ok, NodeSup}.

start_partisan() ->
    partisan_config:set(partisan_peer_service_manager,
			partisan_hyparview_peer_service_manager),
    {ok, PartisanSup} = supervisor:start_child(node,
					       ?PARTISAN_SPEC),
    {ok, PartisanSup}.

start_lasp() ->
    {ok, LaspSup} = supervisor:start_child(node,
					   ?LASP_SPEC),
    {ok, LaspSup}.

%start_lasp_pg() ->
%  {ok, LaspPgSup} = supervisor:start_child(node, ?LASPPG_SPEC),
%  {ok, LaspPgSup}.

% OTP application takes care of this
%stop() ->
%    case whereis(node) of
%        P when is_pid(P) ->
%            exit(P, kill);
%        _ -> ok
%    end.

stop_child(Name) ->
    supervisor:terminate_child(node, Name).

delete_child(Name) ->
    supervisor:delete_child(node, Name).

stop_and_delete_child(Name) ->
    supervisor:terminate_child(node, Name),
    supervisor:delete_child(node, Name).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    SupFlags = #{strategy => rest_for_one, intensity => 1,
		 period => 20},
    {ok, {SupFlags, []}};
% Order of children start is respected
% init(all) ->
%     SupFlags = #{strategy => rest_for_one, intensity => 1,
% 		 period => 20},
%     {ok,
%      {SupFlags, [?PARTISAN_SPEC, ?LASP_SPEC, ?NODE_SPEC]}};

init(all) ->
    SupFlags = #{strategy => rest_for_one, intensity => 1,
		 period => 20},
    {ok,
     {SupFlags, [?LASP_SPEC, ?NODE_SPEC]}};
init(node) ->
    SupFlags = #{strategy => one_for_one, intensity => 1,
		 period => 10},
    {ok, {SupFlags, [?NODE_SPEC]}}.
