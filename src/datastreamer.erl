-module(datastreamer).

-export([send_data/2,datastream/2,start_datastreamer/2]).

start_datastreamer(Server,Timer) ->
  Pid = spawn(datastreamer,send_data,[Server,Timer]),
  Output = register(datastream,Pid),
  io:format("Registered process as datastream is ~p ~n",[Output]).

send_data(Server,Timer) ->
  Dest = {connector,Server},
  Msg = {node(),connect},
  Dest ! Msg,
  io:format("Message sent is ~p ~n",[Msg]),
  receive
    {server_up} -> io:format("Connection accepted by the server")
  end,
  datastream(Server,Timer).

datastream(Server,Timer) ->
  {pmod_nav, Pid, _Ref} = node_util:get_nav(),
  [Press, Temp] = gen_server:call(Pid, {read, alt, [press_out, temp_out], #{}}),
  Time = node_stream_worker:maybe_get_time(),
  {server,Server} ! {node(),Temp,Press,Time},
  timer:sleep(Timer),
  datastream(Server,Timer).
