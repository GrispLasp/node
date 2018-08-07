-module(datastreamer).

-export([send_data/1,datastream/2]).

send_data(Server) ->
  Pid = self(),
  register(datastream,Pid),
  {connector,Server} ! {node(),connect},
  receive
    {Pid,server_up} -> io:format("Connection accepted by the server the Pid for communicating with the server is ~p ~n",[Pid])
  end,
  datastream(Pid,Server).

datastream(Pid,Server) ->
  Temp = rand:uniform()*30,
  Press = rand:uniform(),
  Time = os:timestamp(),
  {Pid,Server} ! {node(),Temp,Press,Time},
  timer:sleep(1000),
  datastream(Pid,Server).
