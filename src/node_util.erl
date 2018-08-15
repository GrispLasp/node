-module(node_util).

-include("node.hrl").

-compile({nowarn_unused_function}).

-compile({nowarn_export_all}).

-compile(export_all).

%%====================================================================
%% Utility functions
%%====================================================================

set_platform() ->
  case os:type() of % Check if application is ran on a grisp or a laptop
    {unix, darwin} -> os:putenv("type", "laptop");
    {unix, linux} -> os:putenv("type", "laptop");
    _ -> os:putenv("type", "grisp")
  end.

process(N) ->
    ?PAUSEHMIN,
    Epoch = (?HMIN) * N,
    logger:log(info, "Data after = ~p seconds ~n", [?TOS(Epoch)]),
    {ok, Lum} = lasp:query({<<"als">>, state_orset}),
    ?PAUSE3,
    LumList = sets:to_list(Lum),
    ?PAUSE3,
    {ok, MS} = lasp:query({<<"maxsonar">>, state_orset}),
    Sonar = sets:to_list(MS),
    ?PAUSE3,
    {ok, Gyr} = lasp:query({<<"gyro">>, state_orset}),
    Gyro = sets:to_list(Gyr),
    logger:log(info, "Raw ALS Data ~n"),
    printer(LumList, luminosity),
    logger:log(info, "Raw Sonar Data ~n"),
    printer(Sonar, sonar),
    logger:log(info, "Raw Gyro Data ~n"),
    printer(Gyro, gyro),
    process(N + 1).

%%--------------------------------------------------------------------

printer([], Arg) ->
    logger:log(info, "nothing left to print for ~p ~n", [Arg]);
printer([H], Arg) ->
    logger:log(info, "Elem = ~p ~n", [H]),
    logger:log(info, "done printing ~p ~n", [Arg]);
printer([H | T], Arg) ->
    ?PAUSEMS,
    logger:log(info, "Elem = ~p ~n", [H]),
    printer(T, Arg).

atom_to_lasp_identifier(Name, Type) ->
    {atom_to_binary(Name, latin1), Type}.

declare_crdts(Vars) ->
    logger:log(info, "Declaring Lasp variables ~n"),
    lists:foldl(fun(Name, Acc) ->
                    [lasp:declare(node_util:atom_to_lasp_identifier(Name,state_orset), state_orset) | Acc]
                  end, [], Vars).

lasp_id_to_atom({BitString, _Type}) ->
    binary_to_atom(BitString, utf8).

atom_to_lasp_id(Id) ->
    {atom_to_binary(Id,utf8), state_orset}.
% https://potatosalad.io/2017/08/05/latency-of-native-functions-for-erlang-and-elixir
% http://erlang.org/pipermail/erlang-questions/2014-July/080037.html

% Erlang.org cpu_sup module doc :

% "The load values are proportional to how long time
% a runnable Unix process has to spend in the run queue before it is scheduled.
% Accordingly, higher values mean more system load."

% CONFIGURE_INIT_TASK_PRIORITY is set to 10 in the RTEMS config erl_main.c
% WPA and DHCP are MAX_PRIO - 1 priority procs

% NB : Grisp RT scheduling is currently being reviewed :
% https://github.com/grisp/grisp/pull/32#issuecomment-398188322
% https://github.com/grisp/grisp/pull/22#issuecomment-404556518

% If other UNIX processes in higher priority queues can preempt Erlang emulator
% the CPU load return value from cpu_sup increases with the waiting time.
% Meanwhile actual system load might be much lower, hence the scheduling
% provides more detail on the global workload of a node.

utilization_sample(S1,S2) ->
  % S1 = scheduler:sample_all(),
  % ?PAUSE10,
  % S2 = scheduler:sample_all(),
  LS = scheduler:utilization(S1,S2),
  % lists:foreach(fun(Scheduler) ->
  %                 case Scheduler of
  %                   {total, F, P} when is_float(F) ->
  %                     logger:log(info, "=== Total usage = ~p ===~n", [P]);
  %                   {weighted, F, P} when is_float(F) ->
  %                     logger:log(info, "=== Weighted usage = ~p ===~n", [P]);
  %                   {normal, Id, F, P} when is_float(F) ->
  %                     logger:log(info, "=== Normal Scheduler ~p usage = ~p ===~n", [Id,P]);
  %                   {cpu, Id, F, P} when is_float(F) ->
  %                     logger:log(info, "=== Dirty-CPU ~p Scheduler usage = ~p ===~n", [Id,P]);
  %                   {io, Id, F, P} when is_float(F) ->
  %                     logger:log(info, "=== Dirty-IO ~p Scheduler usage = ~p ===~n", [Id,P]);
  %                   _ ->
  %                     logger:log(info, "=== Scheduler = ~p ===~n", [Scheduler])
  %                 end
  %               end, LS),
  %   LS.
  LS.


get_nav() ->
    Slot = grisp:device(spi1),
    case Slot of
        {no_device_connected, spi1} ->
            {error, no_device, no_ref};
        {device, spi1, pmod_nav, Pid, Ref} when is_pid(Pid); is_reference(Ref) ->
            {pmod_nav, Pid, Ref};
        _ ->
            {error, unknown, no_ref}
    end.

get_als() ->
    Slot = grisp:device(spi2),
    case Slot of
        {no_device_connected, spi1} ->
            {error, no_device, no_ref};
        {device, spi2, pmod_als, Pid, Ref} when is_pid(Pid); is_reference(Ref) ->
            {pmod_als, Pid, Ref};
        _ ->
            {error, unknown, no_ref}
    end.

%% http://erlang.org/pipermail/erlang-questions/2015-August/085743.html
maps_update(K, F, V0, Map) ->
     try maps:get(K, Map) of
         V1 ->
             maps:put(K, F(V1), Map)
     catch
         error:{badkey, K} ->
             maps:put(K, V0, Map)
     end.

maps_merge(Fun, Map1, Map2) ->
     maps:fold(fun (K, V1, Map) ->
                   maps_update(K, fun (V2) -> Fun(K, V1, V2) end, V1, Map)
               end, Map2, Map1).

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
	{ok, RemoteHosts} = application:get_env(node, remote_hosts),
  Webservers = maps:get(webservers, RemoteHosts),
  % WS = hd(Webservers),
	maybe_get_time({ok, 'ws@GrispAdhoc'}).

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
