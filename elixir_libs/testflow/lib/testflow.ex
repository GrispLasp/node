defmodule Testflow do
  @moduledoc """
  Documentation for Testflow.
  """

  @doc """
  Hello world.

  ## Examples

      iex> Testflow.hello()
      :world

  """
  def hello do
    :world
  end

  def get_key(tup) do
    k = cond do
      {{{y,mo,d},{h,m,s}},p,tmp} = tup ->
        # h*60 + m
        h
    end
    k
  end

  def sortfun(x1,x2) do
    {t1,c1} = x1
    {t2,c2} = x2
    c1 >= c2
  end


  def mapreduce do
    map = %{:cov => -12.941094631619034,
                          :measures =>
                              [{{{1988,1,1},{0,9,16}},290.30908203125,31.914583333333336},
                               {{{1988,1,1},{0,10,16}},1007.046630859375,31.84166666666667},
                               {{{1988,1,1},{0,11,16}},290.30908203125,31.877083333333335}],
                          :pmean => 529.2215983072917,:pvar => 171237.57130004966,
                          :tmean => 31.877777777777787,:tvar => 0.0013295717592593033}
    # a = %{
    #   cov => 12.23156,
    #   measures =>{:calendar.local_time(), 1020.1324, 33.32094}
    #
    # }
    # first = Enum.to_list(Map.get(map, :measures, nil))
    flow = for index <- 1..1000000 do
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
        # else
        #   1000 + press_absolute_offset

        # press_offset = unless sing == 0 do
        #   press_absolute_offset
        # end sign == 0, do:
        #   press_absolute_offset

        # 0 - press_absolute_offset, else 0 + press_absolute_offset
        # rand = {index, {hour_offset, minute_offset, second_offset}, press_offset, temp_offset}
        # rand = {{{1988,1,1},{hour_offset, minute_offset, second_offset}}, press_offset, temp_offset}
        # {{{1988,1,1},{hour_offset, minute_offset, second_offset}}, press_offset, temp_offset}
        # {hour_offset*60+minute_offset, press_offset}
        {hour_offset, press_offset}
        # IO.puts("item = #{inspect(rand)}")
    end
    # [time, press, temp]
    # |> Enum.to_list()
    |> Flow.from_enumerable()
    # |> Flow.flat_map(fn tup -> Tuple.to_list(tup) end)
    |> Flow.partition()
    # |> Flow.reduce(fn -> %{} end, fn tup, acc ->
    #     # {{{day,{h,m,s}},p,t} = tup
    #     key = get_key(tup)
    #     # key = h*60 + m
    #     Map.update(acc, key, 1, &(&1 + 1))
    #   end)
    |> Flow.group_by_key()
    |> Flow.emit(:state)
    # |> Flow.on_trigger(fn acc -> {[acc], [acc]} end)
    |> Enum.to_list()

    List.foldl(flow, List.first(flow), fn x, acc -> Map.merge(x, acc, fn _k, v1, v2 -> v1 ++ v2 end) end)
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
  end
end



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
