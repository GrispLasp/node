-module(node_worker_sup).

-behaviour(supervisor).

%% API
-export([start_link/0]).

%% Supervisor callbacks
-export([init/1]).

%% Macros

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    supervisor:start_link({local, node_worker_sup}, ?MODULE,
			  []).

%% ===================================================================
%% Supervisor callbacks
%% ===================================================================

init([]) ->
    SupFlags = #{strategy => one_for_one, intensity => 1,
		 period => 20},
    {ok, {SupFlags, []}}.
