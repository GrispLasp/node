-module(node_config).

-export([get/1,get/2]).

get(Key) ->
    {ok, Value} = application:get_env(node, Key), Value.

get(Key, Default) -> application:get_env(node, Key, Default).
