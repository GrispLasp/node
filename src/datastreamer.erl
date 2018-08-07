-module(datastreamer).

-export([send_data/1,datastream/2,start_datastreamer/1]).

start_datastreamer(Server) ->
  Output = register(datastream,spawn(datastreamer,send_data,[Server])),
  io:format("Registered process as datastream is ~p ~n",[Output]).

send_data(Server) ->
  {connector,Server} ! {node(),connect},
  receive
    {server_up} -> io:format("Connection accepted by the server")
  end,
  datastream(ServerPid,Server).

datastream(ServerPid,Server) ->
  Temp = rand:uniform()*30,
  Press = rand:uniform(),
  Time = os:timestamp(),
  {server,Server} ! {node(),Temp,Press,Time},
  timer:sleep(1000),
  datastream(ServerPid,Server).
