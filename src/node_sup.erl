% @doc node top level supervisor.
% @end
-module(node_sup).

-behavior(supervisor).

%% API
-export([start_link/0]).

-export([start_link/1]).% -export([stream/0]).

%% Supervisor callbacks
-export([init/1]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, node_sup}, ?MODULE, []).

start_link(Args) ->
    supervisor:start_link({local, node_sup}, ?MODULE, Args).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    SupFlags = #{strategy => one_for_all, intensity => 1,
		 period => 20},
    ChildSpecs = [#{id => node_server,
		    start => {node_server, start_link, [self()]},
		    restart => permanent, type => worker, shutdown => 5000,
		    modules => [node_server]}],
    {ok, {SupFlags, ChildSpecs}};
init(_Args) ->
    SupFlags = #{strategy => one_for_all, intensity => 1,
		 period => 20},
    ChildSpecs = [#{id => node_server,
		    start => {node_server, start_link, [self(), _Args]},
		    restart => permanent, type => worker, shutdown => 5000,
		    modules => [node_server]}],
    {ok, {SupFlags, ChildSpecs}}.
