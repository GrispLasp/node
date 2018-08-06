-module(pmod_gyro).

-behavior(gen_server).

-include("grisp.hrl").
-include("pmod_gyro.hrl").

% API
-export([start_link/2,read_gyro/0,read_temp/0]).

% Callbacks
-export([init/1]).
-export([handle_call/3]).
-export([handle_cast/2]).
-export([handle_info/2]).
-export([code_change/3]).
-export([terminate/2]).

-define(SPI_MODE, #{cpol => high, cpha => trailing}).

-record(state, {
    slot
}).

%--- API -----------------------------------------------------------------------

% @private
start_link(Slot, _Opts) ->
    gen_server:start_link(?MODULE, Slot, []).
    
read_gyro() ->
 Result = call(gyro),
Result.

read_temp() ->
 Result = call(temp),
Result.

%--- Callbacks -----------------------------------------------------------------

% @private
init(Slot) ->
    %verify_device(Slot),
    CTRL_REG1 = grisp_spi:send_recv(Slot, #{cpol => high, cpha => trailing}, <<1:1, 1:1, 16#20:6>>, 1, 1),
    grisp_spi:send_recv(Slot, #{cpol => high, cpha => trailing}, <<0:1, 1:1, 16#20:6, (grisp_bitmap:set_bits(CTRL_REG1, 4, <<1:1>>))/binary>>, 1, 0),
    grisp_devices:register(Slot, ?MODULE),
    {ok, #state{slot = Slot}}.

% @private
handle_call(temp, From, State) -> 
  Result = get_temp(State#state.slot),
  {reply,{ok,Result},State};
  
handle_call(gyro, From, State) -> 
  Result = get_gyro(State#state.slot),
  {reply,{ok,Result},State}.

% @private
handle_cast(Request, _State) -> error({unknown_cast, Request}).

% @private
handle_info(Info, _State) -> error({unknown_info, Info}).

% @private
code_change(_OldVsn, State, _Extra) -> {ok, State}.

% @private
terminate(_Reason, _State) -> ok.

%--- Internal ------------------------------------------------------------------
call(Call) ->
    Dev = grisp_devices:default(?MODULE),
    gen_server:call(Dev#device.pid, Call).

verify_device(Slot) ->
    case grisp_spi:send_recv(Slot, ?SPI_MODE, <<?RW_READ:1, ?MS_SAME:1, ?WHO_AM_I:6>>, 1, 1) of
        <<?DEVID>> -> ok;
        Other      -> error({device_mismatch, {who_am_i, Other}})
    end.
get_temp(Slot) ->
Result = grisp_spi:send_recv(Slot, #{cpol => high, cpha => trailing}, <<1:1, 1:1, 16#26:6>>, 1, 1),
Result.

get_gyro(Slot) ->
Result = grisp_spi:send_recv(Slot, #{cpol => high, cpha => trailing}, <<1:1, 1:1, 16#28:6>>, 1, 6),
Result.    

