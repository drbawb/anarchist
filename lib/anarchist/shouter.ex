defmodule Anarchist.Shouter do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    init_state = %{ shouts: [] }

    GenServer.start_link(__MODULE__, init_state, opts)
  end

  def handle_call({:add, shout}, _from, state) do
    {:reply, :ok, %{state | shouts: [shout | state.shouts]}}
  end

  def handle_call(:random, _from, state) do
    random_shout = state.shouts |> Enum.shuffle |> List.first
    {:reply, random_shout, state}
  end

  def handle_call(:persist, _from, state) do
    Logger.debug "dumping shout database to disk ..."
    {:reply, state.shouts, state}
  end
end
