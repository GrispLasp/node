-module(node_storage_server).

-behaviour(gen_server).

-include_lib("node.hrl").

%% API
-export([start_link/0, terminate/0]).
-export([get_memory_usage/0]).

%% Gen Server Callbacks
-export([code_change/3, handle_call/3, handle_cast/2,handle_info/2, init/1, terminate/2]).

%% ===================================================================
%% API functions
%% ===================================================================

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [],[]).

get_memory_usage() -> gen_server:call(?MODULE, {get_memory_usage}).

terminate() -> gen_server:call(?MODULE, {terminate}).

%% ===================================================================
%% Gen Server callbacks
%% ===================================================================

init([]) ->
    logger:log(info, "Starting node storage server ~n"),
    Interval = node_config:get(memcheck_interval, ?HMIN),
    erlang:send_after(Interval, self(), {monitor_memory_usage}),
		% {ok, State, 5000}.
		{ok, {}}.

handle_call(stop, _From, State) ->
    {stop, normal, ok, State}.

handle_info({monitor_memory_usage}, State) ->
		MemUsageValue = get_mem_usage(),
		% if MemUsageValue =< 40 ->
		if MemUsageValue > 32 ->
			logger:log(info, "=== Memory usage is high, persisting global CRDT states === ~n"),
			persist_crdts();
		true -> logger:log(notice, "=== Usage ~p mb === ~n", [MemUsageValue])
		end,
    Interval = node_config:get(memcheck_interval, ?HMIN),
    {noreply, State, Interval};

handle_info(timeout, State) ->
	MemUsageValue = get_mem_usage(),
	% if MemUsageValue =< 40 ->
	if MemUsageValue > 32 ->
		logger:log(info, "=== Memory usage is high, persisting global CRDT states === ~n"),
		persist_crdts();
	true -> logger:log(notice, "=== Usage ~p mb === ~n", [MemUsageValue])
	end,
	logger:log(notice, "=== Usage ~p mb === ~n", [MemUsageValue]),
  Interval = node_config:get(memcheck_interval, ?HMIN),
	{noreply, State, Interval}.

handle_cast(_Msg, State) -> {noreply, State}.

terminate(Reason, _S) ->
    logger:log(info, "=== Terminating node storage server (reason: ~p) ===~n",[Reason]),
    ok.

code_change(_OldVsn, S, _Extra) -> {ok, S}.

%%====================================================================
%% Internal functions
%%====================================================================

persist_crdt(CrdtName) ->
	CrdtNameStr = atom_to_list(CrdtName),
	filelib:ensure_dir("data/"),
	FileName = string:concat("data/", CrdtNameStr),
	CrdtNameBitString = list_to_binary(CrdtNameStr),
	{ok, CrdtData} = lasp:query({CrdtNameBitString, state_orset}),
	CrdtDataList = sets:to_list(CrdtData),
	lasp:update({CrdtNameBitString, state_orset}, {rmv_all, CrdtData}, self()),
	{ok, F} = file:open(FileName, [append]),
	lists:foreach( fun(X) -> io:format(F, "~p~n",[X]) end, CrdtDataList),
	file:close(F),
	logger:log(info, "=== Persisted ~p to SD card ===~n", [CrdtNameBitString]).

persist_crdts() ->
	CrdtsNames = node_config:get(data_crdts_names, []),
	logger:log(info, "=== Persisting all CRDTs to SD card ===~n"),
	lists:foreach(fun({CrdtName, FlushCrdt}) ->
		CrdtNameStr = atom_to_list(CrdtName),
		filelib:ensure_dir("data/"),
		FileName = string:concat("data/", CrdtNameStr),
		CrdtNameBitString = list_to_binary(CrdtNameStr),
		{ok, CrdtData} = lasp:query({CrdtNameBitString, state_orset}),
		CrdtDataList = sets:to_list(CrdtData),
		Uptime = element(1, erlang:statistics(wall_clock))/60000,
		if Uptime >= 1440 -> % Force flush of all CRDTs every 24 hours
			% TODO: detect that a force flush has been performed to not loop inside this block
			logger:log(info, "=== Force flush of all CRDTs as uptime is more than 24 hours===~n"),
			lasp:update({CrdtNameBitString, state_orset}, {rmv_all, CrdtDataList}, self());
		true ->
			if FlushCrdt == flush_crdt -> % If flush_crdt instruction is set for this CRDT, flush its CRDT when persisting
				lasp:update({CrdtNameBitString, state_orset}, {rmv_all, CrdtDataList}, self());
			true ->
				ok
			end
		end,
		{ok, F} = file:open(FileName, [append]),
    lists:foreach( fun(X) -> io:format(F, "~p~n",[X]) end, CrdtDataList),
		file:close(F),
		logger:log(info, "=== Persisted ~p to SD card ===~n", [CrdtNameBitString])
	end, CrdtsNames).


get_mem_usage() ->
	MemUsage = lists:filter(fun({Type, Size}) ->
		case Type of
			total -> true; % maybe check other type like atom?
			_ -> false
		end
	end, c:memory()),
	MemUsageValue = element(2,hd(MemUsage)),
	MemUsageValue/1000000.
