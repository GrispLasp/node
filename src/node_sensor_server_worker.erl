-module(node_sensor_server_worker).

-author('Alex Carlier').

-behaviour(gen_server).

-export([code_change/3, handle_call/3, handle_cast/2,
	 handle_info/2, init/1, terminate/2]).

-export([creates/1, read/1, start_link/0, terminate/1]).

% These are all wrappers for calls to the server
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [],
			  []).

creates(Sensor_type) ->
    gen_server:call(?MODULE, {creates, Sensor_type}).

read(Sensor_type) ->
    gen_server:call(?MODULE, {read, Sensor_type}).

terminate(Sensor_type) ->
    gen_server:call(?MODULE, {terminate, Sensor_type}).

% This is called when a connection is made to the server
init([]) ->
    SensorList = [],
    logger:log(info, "Gen server for sensors has been initialized ~n"),
    {ok, SensorList}.

% handle_call is invoked in response to gen_server:call
handle_call({creates, Sensor_type}, _From,
	    SensorList) ->
    Response = case lists:member(Sensor_type, SensorList) of
		 true ->
		     NewSensorList = SensorList,
		     {already_created, Sensor_type};
		 false ->
		     % create a sensor of type Sensor_type
		     NewSensorList = [Sensor_type] ++ SensorList,
		     ok
	       end,
    {reply, Response, NewSensorList};
handle_call({read, Sensor_type}, _From, SensorList) ->
    Response = case lists:member(Sensor_type, SensorList) of
		 true ->
		     ReadValue = readSensor(Sensor_type), {read, ReadValue};
		 false -> {sensor_not_created, Sensor_type}
	       end,
    {reply, Response, SensorList};
handle_call({terminate, Sensor_type}, _From,
	    SensorList) ->
    NewLibrary = lists:delete(Sensor_type, SensorList),
    {reply, ok, NewLibrary};
handle_call(_Message, _From, SensorList) ->
    {reply, error, SensorList}.

% We get compile warnings from gen_server unless we define these
handle_cast(_Message, SensorList) ->
    {noreply, SensorList}.

handle_info(_Message, SensorList) ->
    {noreply, SensorList}.

terminate(_Reason, _SensorList) -> ok.

code_change(_OldVersion, SensorList, _Extra) ->
    {ok, SensorList}.

readSensor(Sensor_type) ->
    case Sensor_type of
      temp -> math:floor(rand:uniform() * 30);
      press -> rand:uniform();
      _ -> {this_type_of_sensor_was_not_created}
    end.
