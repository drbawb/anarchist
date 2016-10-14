defmodule AnarchistTest do
  use ExUnit.Case
  doctest Anarchist

  @ex_shout1 "WHAT IS GOING ON HERE?"
  @ex_shout2 "I CAN'T BELIEVE THATS NOT BUTTER"

  setup do
    {:ok, shouter} = Anarchist.Shouter.start_link()
    {:ok, shoutserv: shouter}
  end

  test "the truth" do
    assert 1 + 1 == 2
  end

  test "shout server ignores smallcaps", %{shoutserv: shouter} do
    assert Enum.count(GenServer.call shouter, :dump) == 0
    GenServer.call shouter, {:add, "shit"}
    assert Enum.count(GenServer.call shouter, :dump) == 0
  end

  test "shout server remembers allcaps", %{shoutserv: shouter} do
    assert Enum.count(GenServer.call shouter, :dump) == 0
    GenServer.call shouter, {:add, @ex_shout1}
    assert Enum.count(GenServer.call shouter, :dump) == 1
  end

  test "shout server doesn't duplicate shouts", %{shoutserv: shouter} do
    assert Enum.count(GenServer.call shouter, :dump) == 0

    GenServer.call shouter, {:add, @ex_shout1}
    GenServer.call shouter, {:add, @ex_shout1}
    GenServer.call shouter, {:add, @ex_shout2}

    assert Enum.count(GenServer.call shouter, :dump) == 2
  end
end
