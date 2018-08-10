defmodule Testflow do
  @moduledoc """
  Documentation for Testflow.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Testflow.hello()
      :world

  # maps_update(K, F, V0, Map) ->
  #      try maps:get(K, Map) of
  #          V1 ->
  #              maps:put(K, F(V1), Map)
  #      catch
  #          error:{badkey, K} ->
  #              maps:put(K, V0, Map)
  #      end.
  #
  # maps_merge(Fun, Map1, Map2) ->
  #      maps:fold(fun (K, V1, Map) ->
  #                    maps_update(K, fun (V2) -> Fun(K, V1, V2) end, V1, Map)
  #                end, Map2, Map1).
  def do_maps_deep_merge(map1,map2) do
    Map.merge(map1, map2, fn _k, v1, v2 ->
      # %{:pressures => p1,:temperatures => t1} = v1
      # %{:pressures => p2,:temperatures => t2} = v2
      [p1,t1] = Map.values(v1)
      [p2,t2] = Map.values(v2)
      %{:pressures => Enum.concat(p1,p2),:temperatures => Enum.concat(t1,t2)}
    end)
  end
  #
  # def mapreduce2 do
  #   ds = hello_from_the_other_side()
  #   flow = |> Flow.from_enumerable(max_demand: 100)
  #   |> Flow.partition(max_demand: 5, stages: 10) # instead of 100 and 50
  #   |> Flow.map(&download/1)
  #   |> Flow.partition(max_demand: 5, stages: 4) # instead of 100 and 50
  #   |> Flow.map(&extract/1)
  #   |> Flow.partition(window: Flow.Window.count(100), stages: 1)
  #   |> Flow.reduce(fn -> [] end, fn item, list -> [item | list] end)
  #   |> Flow.emit(:state)
  #   |> Flow.partition(max_demand: 20, stages: 2) # instead of 100 and 10
  #   |> Flow.map(&index/1)
  #   |> Flow.run
  #   flow = Flow.from_enumerable(ds, stages: 1)
  #   |> Flow.group_by_key()
  #   |> Flow.emit(:state)
  #   |> Enum.to_list()
  # end
  def vectorize(maplist) do
      # [time, mes] = Map.to_list(maplist)
      # {time, mes} = maplist
      {time, mes} = maplist
      accin = List.first(mes)
      [foldp,foldt] = List.foldl(mes, accin, fn x, acc ->
        [p,t] = x
        [accp,acct] = acc
        # accout = [accp ++ p, acct ++ t]
        # accout
        [Enum.concat([accp],[p]),Enum.concat([acct],[t])]
      end)
      %{time => %{:pressures => foldp,
                  :temperatures => foldt}}
    end
      # List.foldl(mes, [accin], fn x, acc -> x + acc end)
  # t = %{{1988, 1, 1}, {8, 14, 2}} => [
  #       [1000.0017734010712, 28.727585439607846],
  #       [1000.0017734010712, 28.727585439607846],
  #       map = %{{{1988, 1, 1}, {8, 14, 2}} => [[1003.297, 30.11],[1003.297, 30.11]],{{1988, 1, 1}, {8, 15, 1}} => [[100.297, 32.11],[1023.297, 31.11]]}
  #       # for i <- [:a, :b, :c], j <- [1, 2], do:  {i, j}
  #     ]
  #     # Enum.foldl(L, fn x -> x * 2 end)
  # {t} => [1000.712, 28.72756],[1003.2967477490257, 30.19402384665921]
  #     ]
  def testtag do
    # list = Tuple.to_list({{1988, 1, 1}, {8, 14, 2}})
    # tl = for tup <- list, do: Tuple.to_list(tup)
    # flat = List.flatten(tl)
    Tuple.to_list({{1988, 1, 1}, {8, 14, 2}})
    |> Tuple.to_list()
    |> List.flatten()
    |> List.to_string()
    # |> Enum.each(&Tuple.to_list(&1))
  end

  # def
  # def crunch(times,measures) do
  #   Map.to_list(map)
  #   |>
  # end
  # m = %{}
  # [x,xtail] = list
  """
  def hello_from_the_other_side() do
    # :world
    flow = for index <- 1..1000 do
      hour_offset = Enum.random(1..24)
      minute_offset = Enum.random(1..60)
      second_offset = Enum.random(1..60)
      press_absolute_offset = Enum.random(0..20) * :rand.uniform
      temp_absolute_offset = Enum.random(0..6) * :rand.uniform
      signs = {Enum.random(0..1), Enum.random(0..1)}
      {press_offset, temp_offset} = cond do
        signs == {0,0} -> {1000 - press_absolute_offset, 28 - temp_absolute_offset}
        signs == {0,1} -> {1000 - press_absolute_offset, 28 + temp_absolute_offset}
        signs == {1,1} -> {1000 + press_absolute_offset, 28 + temp_absolute_offset}
        signs == {1,0} -> {1000 + press_absolute_offset, 28 - temp_absolute_offset}
      end
      # {{{1988,1,1},{hour_offset, minute_offset, second_offset}}, [press_offset, temp_offset]}
      key = (hour_offset*60 + minute_offset)
      [key, [press_offset, temp_offset]]
      # {{{1988,1,1},{hour_offset, hour_offset, hour_offset}}, [press_offset, temp_offset]}
    end
  end
  #

  def mapreduce do
    ds = hello_from_the_other_side()
    # flow = Flow.from_enumerable(ds, stages: 1)
    # |> Flow.from_enumerable(ds, stages: 1)
    # |> Flow.group_by_key()
    # |> Enum.map(fn tab -> \)
    # |> Enum.map(&Enum.concat/1)
    # |> Flow.partition(max_demand: 5, stages: 10) # instead of 100 and 5
    # |> Flow.partition(max_demand: 5, stages: 10) # instead of 100 and 5
    # |> Enum.flat_map(&Enum.concat/1)
    # |> Flow.reduce(fn -> [] end, fn item, acc ->
    #   Enum.concat(item, acc)
    # end)
    # |> Flow.map(&Enum.unzip(&1))
    # |> Flow.group_by_key()

    # |> Flow.emit(:state)
    # |> Flow.partition(max_demand: 5, stages: 10) # instead of 100 and 50
    # |> Flow.map(&Enum.unzip/1)
    |> Enum.to_list()
    # |> Flow.reduce(fn -> %{} end, fn [item], acc ->
    #   {{{y,mo,d},{h,m,s}}, tabs} = item
    #   key = h*60 + m
    #     IO.puts("the tab : #{inspect tabs}" )
    #     IO.puts("the key : #{inspect key}" )
    #   Map.update(acc, key, [[],[]], &Enum.concat(&1,tabs))
    # end)
    #   # List.flaitem
    #   Map.update(acc, item, arg3, arg4)[item | acc ]
    # end)

        # Enum.unzip(tabs)
    #   [press,temp] = tabs
    #   # for tab <- tabs, do:
    #   #   for tab <- tabs do Enum.unzip(tab)
    #   #   List.foldl(list, %{vectors => [[],[]], records => tabs}, fn x, acc -> [p,t] = List.unzip(acc)
    #   #   [[p],[t]]
    #   #   [p,t] = x
    #   #   List.update_at(acc, 0, &[p|&1])
    #   #   |> List.update_at(acc, 1, &[t|&2])<
    #
    #   [item | list]
    # end)
    # |> Flow.emit(:state)
    # |> Flow.map()
    # |> Flow.partition(max_demand: 5, stages: 10) # instead of 100 and 50
    # |> Flow.partition(max_demand: 5, stages: 10) # instead of 100 and 50
    # |> Flow.map(&Enum.to_list/1)
    # |> Flow.reduce(fn -> %{} end, fn item, map ->
    # |> Flow.reduce(fn -> [] end, fn item, list ->
    #   [item | list]
    #   # maps_deep_merge(map, item)
    # end)
    # |> Flow.partition(max_demand: 20, stages: 2) # instead of 100 and 10
    # |> Flow.map(:state)
    # {{{1988, 1, 1}, {22, 33, 53}},[a,b,v,d]
    #     [990.0282248074517, 27.42836043839052]}
    # |> Flow.emit(:state)
    # |> Enum.reverse()
    # |> Enum.sort(&(length(Tuple.to_list(&1)) >= length(Tuple.to_list(&2))))
    # IO.puts("Flow = #{inspect(flow)} ~n")
  end
end
  #
  # def get_key(tup) do
  #   k = cond do
  #     {{{y,mo,d},{h,m,s}},p,tmp} = tup ->
  #       # h*60 + m
  #       h
  #   end
  #   k
  # end
  #
  # def sortfun(x1,x2) do
  #   {t1,c1} = x1
  #   {t2,c2} = x2
  #   c1 >= c2
  # end
    #
    # flow = |> Flow.from_enumerable(ds)
    # # flow = Flow.from_enumerable([foo: 1, foo: 2, bar: 3, foo: 4, bar: 5], stages: 1)
    # |> Flow.group_by_key()
    # |> Flow.map_values(&Enum.sort/1)
    # |> Enum.sort()
    # |> Flow.flat_map()
    # |> Flow.partition()
    # |> Flow.reduce(fn -> %{} end, fn item, map ->
    #   Map.update(map, key, 1, &(&1 + 1))
    # end)
    # # |> Flow.group_by_key()
    # |> Flow.emit(:state)
    # |> Enum.to_list()
# m = %{k => [1213.123]}
    # map = %{:cov => -12.941094631619034,
    #                       :measures =>
    #                           [{{{1988,1,1},{0,9,16}},290.30908203125,31.914583333333336},
    #                            {{{1988,1,1},{0,10,16}},1007.046630859375,31.84166666666667},
    #                            {{{1988,1,1},{0,11,16}},290.30908203125,31.877083333333335}],
    #                       :pmean => 529.2215983072917,:pvar => 171237.57130004966,
    #                       :tmean => 31.877777777777787,:tvar => 0.0013295717592593033}
    # a = %{
    #   cov => 12.23156,
    #   measures =>{:calendar.local_time(), 1020.1324, 33.32094}
    #
    # }
    # first = Enum.to_list(Map.get(map, :measures, nil))
        # else
        #   1000 + press_absolute_offset

        # press_offset = unless sing == 0 do
        #   press_absolute_offset
        # end sign == 0, do:
        #   press_absolute_offset

        # 0 - press_absolute_offset, else 0 + press_absolute_offset
        # rand = {index, {hour_offset, minute_offset, second_offset}, press_offset, temp_offset}
        # rand = {{{1988,1,1},{hour_offset, minute_offset, second_offset}}, press_offset, temp_offset}
        # {hour_offset*60+minute_offset, press_offset}
        # {hour_offset, press_offset}
        # IO.puts("item = #{inspect(rand)}")
    # [time, press, temp]
    # |> Enum.to_list()
    # |> Flow.flat_map(fn tup -> Tuple.to_list(tup) end)
    # |> Flow.reduce(fn -> %{} end, fn tup, acc ->
    #     # {{{day,{h,m,s}},p,t} = tup
    #     key = get_key(tup)
    #     # key = h*60 + m
    #     Map.update(acc, key, 1, &(&1 + 1))
    #   end)

# |> Flow.on_trigger(fn acc -> {[acc], [acc]} end)
    # List.foldl(flow, List.first(flow), fn x, acc -> Map.merge(x, acc, fn _k, v1, v2 -> v1 ++ v2 end) end)
    #
    # list = Enum.sort(flow, &sortfun(&1, &2))
    # |> Flow.from_enumerable()
    # |> Flow.group_by_key()
    # |> Enum.to_list()
    # |> Enum.map(fn tup ->
    #   {h, sums} = tup
    #   {h, Enum.sum(sums)}
    # end)
    # |> Enum.reverse()
    # |> Enum.flat_map_reduce(acc, fun)
    # Enum.max_by(flow, fn {t,c} -> c end)
    # |> List.first()
    # range = 1..1000
    # Enum.each(range, fn(num) ->
    #
    # end)
    # |> &List.first(&1)
    # |> Stream.map(&IO.inspect(&1))
    # File.stream!("path/to/some/file")
    # Flow.from_enumerable(measures)
    # |> Flow.flat_map(&String.split(&1, " "))
    # |> Flow.each(fn tup ->
    #   IO.puts("Tuple = #{inspect(tup)} ~n")
    #   tup
    # end )
    # |> Flow.partition()
    # |> Flow.reduce(fn -> %{} end, fn tup, acc ->
    # end)
    # |> Enum.to_list()
    # |> &List.duplicate(List.first(&1), 10)



#
# {#{cov => -12.941094631619034,
#                       measures =>
#                           [{{{1988,1,1},{0,9,16}},290.30908203125,31.914583333333336},
#                            {{{1988,1,1},{0,10,16}},1007.046630859375,31.84166666666667},
#                            {{{1988,1,1},{0,11,16}},290.30908203125,31.877083333333335}],
#                       pmean => 529.2215983072917,pvar => 171237.57130004966,
#                       tmean => 31.877777777777787,tvar => 0.0013295717592593033},
#                     [{<<166,228,1,82,63,157,221,65,102,136,185,249,206,135,
#                         225,110,151,110,...>>,
#                       true}]}]}
