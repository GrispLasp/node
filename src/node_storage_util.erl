-module(node_storage_util).

-include_lib("node.hrl").

-compile({nowarn_unused_function}).

-compile({nowarn_export_all}).

-compile(export_all).

-define(NODES,  [node@Laymer, node2@Laymer]).
-define(WILDCARD,    "_???").
-define(SEPARATOR,    "_").
-define(MAXPART,    3).
%% API
% -export([save_crdt/2,
%         load_crdt/1]).

%% ===================================================================
%% API functions
%% ===================================================================

flush_crdt(Id, _FilenameOld, Mode) ->
    % TODO : target only sensitive processes for GC
    TableName = node_util:lasp_id_to_atom(Id),
    case Mode of
        % Save table entry to file
        % without removing the values from
        % the set. Local table is erased
        % and querying cannot retrieve previous
        % elements. State convergence is achieved
        % locally with a set containing only results
        % of subsequent operations on the CRDT.
        % If the saved state is loaded back again,
        % it replaces the current state and unsaved mutations
        % that were operated inbetween are lost.
      save_no_rmv_all ->
        % TODO : check if table is empty
          Tmp = ets:new(TableName, [ordered_set, named_table, public]),
          case ets:insert_new(Tmp, ets:take(node(), Id)) of
              true ->
                  {ok, Name} = get_filename(Id),
                  % case ets:tab2file(Tmp, Filename, [{sync, true}]) of
                  case ets:tab2file(Tmp, Name, [{sync, true}]) of
                    ok ->
                      logger:log(info, "Saved CRDT ~p to file ~p ~n", [Id, Name]),
                      true = ets:delete(Tmp),
                      true = ets:delete(node(), Id),
                      {ok, Id, Name};
                    {error, Reason} ->
                      lager:error("Could not save ~p to SD card ~n", [Id]),
                      {error, Reason}
                  end;
              false ->
                lager:error("Could not insert ~p values in tmp table ~n", [Id]),
                {error, insert}
          end;
      % Save table entry to file and remove
      % all local table entries from the state.
      % The set is updated before the flush and
      % the operations are replicated.
      % Convergence is achieved locally with
      % regular delta-based mutations since it
      % is also the global converging state.
      % If the saved state is loaded back again,
      % it replaces the current state and unsaved mutations
      % that were operated inbetween are lost.
      save_rmv_all ->
            % TODO : check if table is empty
            % NOTE : use ets:select() for merging?
          L = values_to_list(Id),
          % {ok, {_Id, _Type, _Metadata, _Val}} = lasp:update(Id, {rmv_all, L}, self()),
          {ok, {NewId, _NewType, _NewMeta, _NewVal}} = lasp:update(Id, {rmv_all, L}, self()),
          Delay = application:get_env(lasp, delta_interval, ?FIVE),
          ?SLEEP(Delay + ?ONE),
          Tmp = case ets:info(TableName) of
              undefined ->
                  ets:new(TableName, [ordered_set, named_table, public]);
              _ ->
                  ets:delete(TableName),
                  ets:new(TableName, [ordered_set, named_table, public])
              end,
          % case ets:insert_new(Tmp, ets:take(node(), Id)) of
          New = ets:take(node(), NewId),
          case ets:insert(Tmp, New) of
              true ->
                  {ok, Name} = get_filename(Id),
                  case ets:tab2file(Tmp, Name, [{sync, true}]) of
                    ok ->
                      logger:log(notice, "Saved CRDT ~p to file ~p ~n", [Id, Name]),
                      % true = ets:delete(Tmp, Id),
                      true = ets:delete(Tmp),
                      % ets:lookup(node(), {<<"states">>,state_orset}).
                      true = ets:delete(node(), Id),
                      logger:log(info, "=== Saved state ===~n"),
                      logger:log(info, "State = ~p ~n", [New]),
                      logger:log(info, "=== Saved state ===~n"),
                      {ok, Id, Name};
                    {error, Reason} ->
                      lager:error("Could not save ~p to SD card ~n", [Id]),
                      {error, Reason}
                  end;
              false ->
                lager:error("Could not insert ~p values in tmp table ~n", [Id]),
                {error, insert}
          end;
        _ -> {error, unknown_mode}
    end.

persist(Id) ->
    % TODO : target only sensitive processes for GC
    TableName = node_util:lasp_id_to_atom(Id),
    TableStr = atom_to_list(TableName),
    Suffix = atom_to_list(temp),
    TN = list_to_atom(unicode:characters_to_list([TableStr, "_", Suffix], utf8)),
    % TODO : check if table is empty
      Tmp = ets:new(TN, [ordered_set, named_table, public]),
      case ets:insert_new(Tmp, ets:take(node(), Id)) of
          true ->
              {ok, Name} = get_filename(Id),
              % case ets:tab2file(Tmp, Filename, [{sync, true}]) of
              case ets:tab2file(Tmp, Name, [{sync, true}]) of
                ok ->
                  logger:log(info, "Saved CRDT ~p to file ~p ~n", [Id, Name]),
                  true = ets:delete(Tmp),
                  true = ets:delete(node(), Id),
                  {ok, Id, Name};
                {error, Reason} ->
                  lager:error("Could not save ~p to SD card ~n", [Id]),
                  {error, Reason}
              end;
          false ->
            lager:error("Could not insert ~p values in tmp table ~n", [Id]),
            {error, insert}
      end.

% save_crdt(Id, Filename) ->
%   Tmp = ets:new(Filename, [ordered_set, named_table, public]),
%   Var = ets:lookup(node(),Id),
%   case ets:insert_new(Tmp, Var) of
%     true ->
      % case ets:tab2file(Tmp, Filename, [{sync, true}]) of
      %   ok ->
      %     logger:log(info, "Saved CRDT ~p to file ~p ~n", [Id, Filename]),
      %     true = ets:delete(Tmp),
      %     % true = ets:delete(node(), Id),
      %     ok;
      %   {error, Reason} ->
      %     lager:error("Could not save ~p to SD card ~n", [Id]),
      %     {error, Reason}
      % end;
  %   false ->
  %     lager:error("Could not insert ~p in tmp table ~n", [Var]),
  %     {error, insert}
  % end.

load_crdt(Id, _FilenameOld, Part) ->
    % TODO : check if table is empty
    % Filename = get_part(Id, Part),
    case get_part(Id, Part) of
        {ok, Filename} ->
            logger:log(info, "Part number ~p of saved state of ~p successfully retrieved ~n", [Part,Id]),
            case ets:file2tab(Filename) of
                {ok, Tab} ->
                    % All = ets:match(Filename, '$1'),
                    L = ets:tab2list(Tab),
                    case ets:insert_new(node(), L) of
                        true ->
                            logger:log(info, "Loaded CRDT from file ~p ~n", [Filename]),
                            {ok, Id, Filename};
                        false ->
                            logger:log(info, "Overriding current state with saved state in ~p ~n", [Filename]),
                            % TODO : attempt merging states using state_orset API
                            ets:insert(node(), L),
                            ets:delete(Tab, L),
                            {ok, Id, Filename}
                            % Set = values_to_set(Id),
                    end;
                {error, Reason} ->
                    lager:error("Could not load CRDT from file ~p ~n", [Filename]),
                    case Reason of
                        cannot_create_table ->
                            ets:delete(node_util:lasp_id_to_atom(Id)),
                            load_crdt(Id, _FilenameOld, Part);
                        _ -> {error, file2tab_unknown_reason}
                    end
            end;
        {error, no_such_part} ->
            logger:log(error, "Part number ~p of saved state of ~p not found ~n", [Part,Id]),
            {error, no_such_part};
        _ ->
            {error, unknown}
    end.

%% ===================================================================
%% Testing functions
%% ===================================================================

run_lasp() ->
  case application:ensure_all_started(lasp) of
    {ok, Deps} ->
      % {ok, {Id, T, M, V}} = lasp:declare({<<"test">>, state_orset}, state_orset),
      {ok, _Set} = lasp:declare({<<"test">>, state_orset}, state_orset),
      % lists:foreach(fun
      %   (Elem) ->
      %     lasp:update(Id, {add, Elem}, self())
      % end, ["hello", "hi", "test"]),
      {ok, New} = update(),
      logger:log(info, "Updated state : ~p ~n", [New]),
      % {ok, {Id, T, M, V}};
      {ok, Deps};
    _ ->
      error
    end.

test_remote() ->
  case application:ensure_all_started(lasp) of
    {ok, Deps} ->
      % [Node] = ?NODES -- [node()],
      Node = node(),
      Remotes = ?BOARDS((?IGOR)) -- [Node],
      logger:log(info, "Target remotes = ~p ~n", [Remotes]),
      logger:log(info, "Current node = ~p ~n", [Node]),
      M = lasp_peer_service:manager(),
      Reached = lists:foldl(fun
          (Elem) ->
              case net_adm:ping(Elem) of
                  pong ->
                      Remote = rpc:call(Node, M, myself, []),
                      ok = lasp_peer_service:join(Remote),
                      [Remote];
                  pang ->
                      [error, Elem]
              end
      end, [], Remotes),
      Nodes = nodes(),
      logger:log(info, "Connected Nodes = ~p ~n", [Nodes]),
      logger:log(info, "Remotes = ~p ~n", [Reached]),
      logger:log(info, "Cluster = ~p ~n", [lasp_peer_service:members()]),
      {ok, Deps};
    _ ->
      error
  end.

test_remote(Node) ->
  case application:ensure_all_started(lasp) of
    {ok, _Deps} ->
      case net_adm:ping(Node) of
        pong ->
          Nodes = nodes(),
          logger:log(info, "Nodes = ~p ~n", [Nodes]),
          M = lasp_peer_service:manager(),
          Remote = rpc:call(Node, M, myself, []),
          ok = lasp_peer_service:join(Remote),
          {ok, Remote};
        pang ->
          ?PAUSE3,
          test_remote(Node)
        end;
    _ ->
      error
  end.

%% ===================================================================
%% Internal Functions
%% ===================================================================

values_to_list(Id) ->
  {ok, Var} = lasp:query(Id),
  sets:to_list(Var).

values_to_set(Id) ->
  {ok, Var} = lasp:query(Id),
  Var.

get_filename({BitString, _Type}) ->
    Filename = binary_to_list(BitString),
    Fullname = filename:join(node_config:get(data_dir, "data"), Filename),
    logger:log(info, "Full base name of destination file : ~p ~n", [Fullname]),
    case filelib:ensure_dir(Fullname) of
        % ok when file:is_dir(Fullname) ->
        ok ->
            IsDir = filelib:is_dir(Fullname),
            if
                true == IsDir ->
                    logger:log(info, "Directory ~p exists ~n", [Fullname]),
                    Part = check_part(Filename, Fullname),
                    logger:log(info, "Part is ~p ~n", [Part]),
                    {ok, filename:join([Fullname, Part])};
                true ->
                    logger:log(info, "Creating Directory ~p ~n", [Fullname]),
                    case file:make_dir(Fullname) of
                        ok ->
                            logger:log(info, "Directory ~p created ~n", [Fullname]),
                            Part = check_part(Filename,Fullname),
                            logger:log(info, "Part is ~p ~n", [Part]),
                            {ok, filename:join([Fullname, Part])};
                        {error, Reason} ->
                            logger:log(error, "Failed to create Directory ~p ~n", [Fullname]),
                            {error, Reason}
                    end
            end;
        _ ->
            {error, unknown}
    end.

check_part(Name,Dir) ->
    Basename = filename:join(Dir,Name),
    L = filelib:wildcard(unicode:characters_to_list([Basename, ?WILDCARD], utf8)),
    Len = length(L),
    % TODO : alert when MAXPART limit is reached
    Offset = integer_to_list(Len),
    Pad = lists:duplicate((?MAXPART - length(Offset)), "0"),
    % Part = unicode:characters_to_list([Name, ?SEPARATOR, Pad, Offset], utf8),
    Part = unicode:characters_to_list([Name, ?SEPARATOR, Pad, Offset], utf8),
    logger:log(info,"Part number ~p ~n", [Part]),
    % ok = filelib:ensure_dir(filename:join(Basename,Part)),
    Part.

get_part({BitString, _Type}, Num) when is_integer(Num); Num >= 0; Num =< ?MAXPART ->
    Filename = binary_to_list(BitString),
    Fullname = filename:join(node_config:get(data_dir, "data"), Filename),
    IsDir = filelib:is_dir(Fullname),
    if
        true == IsDir ->
            % return part
            Offset = integer_to_list(Num),
            Pad = lists:duplicate((?MAXPART - length(Offset)), "0"),
            Part = unicode:characters_to_list([Filename, ?SEPARATOR, Pad, Offset], utf8),
            PartFile = filename:join(Fullname, Part),
            % filelib:wildcard(unicode:characters_to_list([Basename, Part], utf8)),
            % filelib:wildcard(PartFile),
            IsFile = filelib:is_file(PartFile),
            if
                true == IsFile ->
                    {ok, PartFile};
                true ->
                    {error, no_such_part}
            end;
        true ->
            {error, no_such_directory}
    end.

%% ===================================================================
%% Utility Functions
%% ===================================================================

get_test() ->
  lasp:query({<<"test">>, state_orset}).

members() ->
  lasp_peer_service:members().

get_id() -> {<<"test">>, state_orset}.

look() ->
  ets:lookup(node(), get_id()).

update() ->
    update(add_all, ["hello", "hi", "test"]).

update(Op, Elems) ->
    lasp:update(get_id(), {Op, Elems}, self()).

diagnose() ->

    % NOTE :
    % Erlang's binaries are of two main types: ProcBins and Refc binaries.
    % Binaries up to 64 bytes are allocated directly on the process's heap,
    % and take the place they use in there.
    % Binaries bigger than that get allocated in a global heap for binaries only,
    % and each process holds a local reference in its local heap.

    % NOTE :
    % Heap binaries are small binaries, up to 64 bytes,
    % and are stored directly on the process heap. They are copied
    % when the process is garbage-collected and when they are sent as a message.
    % They do not require any special handling by the garbage collector.

    % garbage_collect(self(),[{type, 'major'}]),
    % instrument:allocations().
    % instrument:allocations(#{ histogram_start => 128, histogram_width => 15 }).
    % erlang:system_info(atom_count).
    % erlang:system_info(atom_limit).
    % erlang:system_info(ets_limit).
    % erlang:system_info(port_limit).
    % erlang:system_info(port_count).
    % erlang:system_info(process_count).
    % erlang:system_info(process_limit).
    % erlang:system_info(heap_sizes).
    % [{{A, N}, Data} || A <- [eheap_alloc, binary_alloc, ets_alloc,driver_alloc],{instance, N, Data} <- erlang:system_info({allocator,eheap_alloc})].
    % [{{A, N}, Data} || A <- [eheap_alloc],{instance, N, Data} <- erlang:system_info({allocator,eheap_alloc})].
    % bin_leak(N::pos_integer()) -> [proc_attrs()].
    % recon:bin_leak(20).
    % recon_alloc:average_block_sizes(current).
    % recon_alloc:memory(allocated).
    % recon_alloc:memory(used).
    % recon_alloc:memory(usage).
    % garbage_collect(self(),[{type, 'major'}]).
    % recon_alloc:memory(usage).
    % instrument:carriers(#{ histogram_start => 512, histogram_width => 8, allocator_types => [eheap_alloc] }).
    % ok.{ok, S} = lasp:query({<<"states">>,state_orset}).
    % L = sets:to_list(S).
    ok.
gc() ->
    % TODO : compare fragmentation before and after
    % ok = print_alloc(),
    % https://blog.heroku.com/logplex-down-the-rabbit-hole
    % _GC = [erlang:garbage_collect(Proc, [{type, 'major'}]) || Proc <- processes()].

    _ = [logger:log(info, "Mem = ~p ~n", [X]) || X <- mem()],
    _GC = [erlang:garbage_collect(Proc, [{type, 'major'}]) || Proc <- processes()],

    logger:log(notice, "Garbage was collected manually"),
    _ = [logger:log(info, "Mem = ~p ~n", [Y]) || Y <- mem()],
    % ok = print_alloc().
    ok.

% print_alloc() ->
%     logger:log(info, "Allocated memory : ~p kB ~n", [(recon_alloc:memory(allocated)) / 1024]),
%     logger:log(info, "Reported memory usage : ~p kB ~n", [(recon_alloc:memory(usage)) / 1024]),
%     logger:log(info, "Actual memory usage : ~p kB ~n", [(recon_alloc:memory(used)) / 1024]),
%     ok.

mem() ->
  [{X, erlang:round(recon_alloc:memory(X) / 1024)} || X <- [allocated, used, usage]].
    % [{K,V / math:pow(1024,3)} || {K,V} <- erlang:memory()].
    % [erlang:garbage_collect(X) || X <- processes()].
% match_crdt(Id, Tab) ->
%   % [[{MatchedId, Data}] | Rest ] = ets:match(Tab, '$1').
%   _DeltaVal = #dv{},
%   L = ets:match(Tab, {Id, '$1'}),
%   List = lists:flatten(L),
%   List.
% node_storage_util:save_crdt({<<"temp">>, state_orset}, tempfile).
% node_storage_util:load_crdt(tempfile).
% lasp:query({<<"temp">>, state_orset}).
% lasp:query({<<"states">>, state_orset}).
% lasp:query({<<"node@my_grisp_board_1">>, state_gset}).

% node_storage_util:run_lasp().
% node_storage_util:get_test().
% node_storage_util:look().
% node_storage_util:update().
% ets:match(node(), '$1').
% node_storage_util:flush_crdt(node_storage_util:get_id(),save1,save_rmv_all).
% node_storage_util:flush_crdt({<<"states">>,state_orset},save1,save_rmv_all).
% node_storage_util:flush_crdt(node_storage_util:get_id(),save2,save_no_rmv_all).
% node_storage_util:load_crdt(node_storage_util:get_id(),save1).
% node_storage_util:load_crdt(node_storage_util:get_id(),save1,1).
% node_storage_util:load_crdt({<<"states">>,state_orset},save1,0).
% lasp:update(node_storage_util:get_id(), {add_all, ["hello", "hi", "test"]}, self()).
% lasp:update({<<"test1">>, state_orset}, {add_all, ["hello", "hi", "test"]}, self()).
