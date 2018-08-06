-module(node_generic_tasks_server).
-behaviour(gen_server).

-include_lib("node.hrl").

%% API
-export([start_link/0, terminate/0, add_task/1, remove_all_tasks/0, remove_task/1, get_all_tasks/0, find_task/1]).

%% Gen Server Callbacks
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

%% Records


%% ===================================================================
%% API functions
%% ===================================================================

start_link() -> gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

terminate() -> gen_server:call(?MODULE, {terminate}).

add_task(Task) -> gen_server:call(?MODULE, {add_task, Task}).

remove_task(Name) -> gen_server:call(?MODULE, {remove_task, Name}).

remove_all_tasks() -> gen_server:call(?MODULE, {remove_all_tasks}).

get_all_tasks() -> gen_server:call(?MODULE, {get_all_tasks}).

find_task(Name) -> gen_server:call(?MODULE, {find_task, Name}).


%% ===================================================================
%% Gen Server callbacks
%% ===================================================================

init([]) ->
  logger:log(info, "Starting a generic tasks server ~n"),
  %% Ensure Gen Server gets notified when his supervisor dies
  Vars = node_config:get(generic_tasks_sets_names, []),
  node_util:declare_crdts(Vars),
  process_flag(trap_exit, true),
  {ok, {}}.

% TODO: add infinite execution of a task
handle_call({add_task, {Name, Targets, Fun}}, _From, State) ->
  logger:log(info, "=== ~p ~p ~p ===~n", [Name, Targets, Fun]),
  Task = {Name, Targets, Fun},
  lasp:update({<<"tasks">>, state_orset}, {add, Task}, self()),
  {reply, ok, State};


handle_call({remove_task, TaskName}, _From, State) ->
  {ok, Tasks} = lasp:query({<<"tasks">>, state_orset}),
  TasksList = sets:to_list(Tasks),
  TaskToRemove = [{Name, Targets, Fun} || {Name, Targets, Fun} <- TasksList, Name =:= TaskName],
  case length(TaskToRemove) of
    1 ->
      ExtractedTask = hd(TaskToRemove),
      logger:log(info, "=== Task to Remove ~p ===~n", [ExtractedTask]),
      lasp:update({<<"tasks">>, state_orset}, {rmv, ExtractedTask}, self());
    0 ->
      logger:log(info, "=== Task does not exist ===~n");
    _ ->
      logger:log(info, "=== Error, more than 1 task === ~n")
  end,
  {reply, ok, State};


handle_call({remove_all_tasks}, _From, State) ->
  {ok, Tasks} = lasp:query({<<"tasks">>, state_orset}),
  TasksList = sets:to_list(Tasks),
  lasp:update({<<"tasks">>, state_orset}, {rmv_all, TasksList}, self()),
  {reply, ok, State};

handle_call({get_all_tasks}, _From, State) ->
  {ok, Tasks} = lasp:query({<<"tasks">>, state_orset}),
  TasksList = sets:to_list(Tasks),
  {reply, TasksList, State};

handle_call({find_task, TaskName}, _From, State) ->
  {ok, Tasks} = lasp:query({<<"tasks">>, state_orset}),
  TasksList = sets:to_list(Tasks),
  Task = [{Name, Targets, Fun} || {Name, Targets, Fun} <- TasksList, Name =:= TaskName],
  case length(Task) of
    0 ->
      {reply, task_not_found, State};
    1 ->
      {reply, {ok, hd(Task)}, State};
    _ ->
      {reply, more_than_one_task, State}
  end;

handle_call(stop, _From, State) ->
  {stop, normal, ok, State}.


handle_info(Msg, State) ->
    logger:log(info, "=== Unknown message: ~p~n", [Msg]),
    {noreply, State}.

handle_cast(_Msg, State) -> {noreply, State}.

terminate(Reason, _S) ->
  logger:log(error, "=== Terminating Generic server (reason: ~p) ===~n",[Reason]),
  ok.

code_change(_OldVsn, S, _Extra) ->
  {ok, S}.


%%====================================================================
%% Internal Functions
%%====================================================================
