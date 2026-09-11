defmodule NskTest do
  use ExUnit.Case
  doctest Nsk

  test "greets the world" do
    assert Nsk.hello() == :world
  end
end
