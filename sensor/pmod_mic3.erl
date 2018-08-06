-module(pmod_mic3).

-behavior(gen_server).

-include("grisp.hrl").

% API
-export([start_link/2]).
-export([raw/1]).
-export([read/2]).
-export([write/2]).
%-export([precise/0]).

% Callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([code_change/3]).
-export([terminate/2]).

-define(SPI_MODE, #{cpol => low, cpha => leading}).

%--- Records -------------------------------------------------------------------

-record(state, {
    slot,
    count,
    values
}).

%--- API -----------------------------------------------------------------------

% @private
start_link(Slot, _Opts) -> gen_server:start_link(?MODULE, Slot, []).

raw(N) ->
    Result = call(raw,N),
    Result.

%--- Callbacks -----------------------------------------------------------------

% @private
init(Slot) ->
    grisp_devices:register(Slot, ?MODULE),
    {ok, #state{slot = Slot,count = 0,values = []}}.

% @private
handle_call({raw,N},From, State) ->
  WritePid = spawn(?MODULE,write,[State#state.values,N]),
  erlang:register(write,WritePid),
  %T1 = os:timestamp(),
  Pid = spawn(?MODULE,read,[State#state.slot,N]),
  %T2 = os:timestamp(),
  %Time = timer:now_diff(T2,T1),
  %io:format("Time to pull ~p data ~p ~n",[N,Time/1000000]),
{reply,ok,State}.

handle_cast(Request, _State) -> error({unknown_cast, Request}).

handle_info({average,Value}, State) ->
io:format("Average has been done ~n"),
io:format("The value for the average noise is ~p ~n",[Value]),
{noreply,State};

handle_info(timeout, State) ->
  T1 = os:timestamp(),
  Raw = grisp_spi:send_recv(State#state.slot, ?SPI_MODE, <<0>>, 0, 1),
  %Raw = get_value(State#state.slot),
  T2 = os:timestamp(),
  Time = timer:now_diff(T2,T1),
  Count = State#state.count + 1,
  Modulo = Count rem 100,
  if
  Modulo == 0 -> io:format("Time to pull data on the mic ~p ~n",[Time/1000000]);
  true -> nothing
end,

  {noreply,#state{slot = State#state.slot,count = Count}}.

code_change(_OldVsn, State, _Extra) -> {ok, State}.

% @private
terminate(_Reason, _State) -> ok.

%--- Internal ------------------------------------------------------------------

call(Call,N) ->
    Dev = grisp_devices:default(?MODULE),
    gen_server:call(Dev#device.pid, {Call,N},10000).
%get_value(Slot,N) when N == 0 ->
%   <<_:4,Resp:12>> = grisp_spi:send_recv(Slot, ?SPI_MODE, <<0>>, 0, 1),
%   Resp;
%%%%%%%%%%%%%%%%GET_VALUE N TIMES OR ONCE%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
get_value(Slot,N) when N == 0->
    grisp_spi:send_recv(Slot, ?SPI_MODE, <<0>>, 0, 1);

get_value(Slot,N) when N >0->
   grisp_spi:send_recv(Slot, ?SPI_MODE, <<0>>, 0, 1),
    get_value(Slot,N-1).

get_value(Slot) ->
    grisp_spi:send_recv(Slot, ?SPI_MODE, <<0>>, 0, 1).
  %%%%%%%%%%%%%%%%%%%READ VALUE N TIMES LUNCHED BY HANDLE_CALL IN ITS OWN PROCESS%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
read(Slot,N) when N == 0 ->
    io:format("DONE READING! ~n");

read(Slot,N) when N > 0->
   <<_:4,Raw:12>> = grisp_spi:send_recv(Slot, ?SPI_MODE, <<0>>, 0, 1),
   io:format("Raw value is : ~p ~n",[Raw]),
   write ! {value,Raw},
   read(Slot,N-1).
 %%%%%%%%%%%%%%%%%%%%WRITE VALUE N TIMES LUNCHED BY HANDLE_CALL IN ITS OWN PROCESS%%%%%%%%%%%%%%%%%%%%%%%%%%%%
write(Values,N) when N > 0 ->
 receive
   {value,Msg} -> write(lists:append([Msg],Values),N-1);
   _ -> io:format("function is done reading here is the list ~p ~n",[Values])
 end;

write(Values,0) ->
 Result = average(Values),
 io:format("The value for the average noise is ~p ~n",[Result]).
%%%%%%%%%%%%%%%%%%%%%%CALCULATION FUNCTIONS%%%%%%%%%%%%%%%%%%%%%%%%%%
average(List) -> sum(List)/length(List).

sum([H|T]) -> H + sum(T);
sum([]) -> 0.

%io:format("List is ~p ~n",[Values]).
