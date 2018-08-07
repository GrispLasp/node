defmodule TestflowTest do
  use ExUnit.Case
  doctest Testflow

  test "greets the world" do
    assert Testflow.hello() == :world
  end
end
