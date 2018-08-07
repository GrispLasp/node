-module(datastreamer).

-export([send_data/1,datastream/1,start_datastreamer/1]).

start_datastreamer(Server) ->
  Pid = spawn(datastreamer,send_data,[Server]),
  Output = register(datastream,Pid),
  io:format("Registered process as datastream is ~p ~n",[Output]).

send_data(Server) ->
  Dest = {connector,Server},
  Msg = {node(),connect},
  Dest ! Msg,
  io:format("Message sent is ~p ~n",[Msg]),
  receive
    {server_up} -> io:format("Connection accepted by the server")
  end,
  datastream(Server).

datastream(Server) ->
  Temp = rand:uniform()*30,
  Press = rand:uniform(),
  Time = os:timestamp(),
  {server,Server} ! {node(),Temp,Press,Time},
  timer:sleep(1000),
  datastream(Server).
