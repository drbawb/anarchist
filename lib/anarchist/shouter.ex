defmodule Anarchist.Shouter do
  use GenServer
  require Logger

  @min_shout_length 10 # chosen arbitrarily by fair dice roll

  def start_link(opts \\ []) do
    init_state = %{ shouts: MapSet.new }
    GenServer.start_link(__MODULE__, init_state, opts)
  end

  # api

  @doc "Stores the shout in the in-memory list of shouts"
  def add_shout(pid, shout), do: GenServer.call(pid, {:add, shout})

  @doc "Grabs a random shout from the in-memory DB"
  def get_random(pid), do: GenServer.call(pid, :random)

  @doc "Loads a JSON-formatted array from `path` into memory"
  def load(pid, path), do: GenServer.call(pid, {:load, path})

  @doc "Persists the shout database into a JSON formatted array at `path`"
  def persist(pid, path), do: GenServer.call(pid, {:persist, path})


  # callbacks

  def handle_call({:add, shout}, _from, state) do
    if valid_shout(shout) do
      {:reply, :ok, %{state | shouts: MapSet.put(state.shouts, shout) }}
    else
      {:reply, {:error, "invalid shout, nil or not utf8?"}, state}
    end
  end

  def handle_call(:random, _from, state) do
    random_shout = state.shouts |> Enum.shuffle |> List.first
    {:reply, random_shout, state}
  end

  def handle_call(:dump, _from, state) do
    {:reply, state.shouts, state}
  end

  def handle_call({:load, path}, _from, state) do
    Logger.debug "loading shout database :: #{inspect path}"
    shouts = path |> File.read! |> Poison.decode! |> MapSet.new

    {:reply, :ok, %{state | shouts: shouts}}
  end

  def handle_call({:persist, path}, _from, state) do
    Logger.debug "dumping shout database to disk ..."
    json_buf  = Poison.encode!(state.shouts)
    io_result = File.write(path, json_buf)

    {:reply, io_result, state}
  end

  defp valid_shout(text) do
    is_binary(text)
    and String.valid?(text)
    and String.upcase(text) == text
    and String.length(text) >= @min_shout_length
  end
end
