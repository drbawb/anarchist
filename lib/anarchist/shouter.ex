defmodule Anarchist.Shouter do
  use GenServer
  require Logger

  @min_shout_length 10 # chosen arbitrarily by fair dice roll

  def start_link(opts \\ []) do
    init_state = %{ shouts: MapSet.new, last_shout: nil }
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

  def handle_call(:convert, _from, state) do
    new_shouts = state.shouts |> Enum.map(fn shout ->
      %{created_by: nil, created_at: nil, body: shout}
    end) |> MapSet.new

    {:reply, new_shouts, %{state | shouts: new_shouts}}
  end 

  def handle_call(:when, _from, state) do
    if is_nil(state.last_shout) or is_nil(state.last_shout.created_at) do
      {:reply, "Sorry, I'm not sure who said that :-(", state}
    else
      {:reply, "#{state.last_shout.created_by} said that at #{state.last_shout.created_at}", state}
    end
  end

  def handle_call(:who, _from, state) do
    if is_nil(state.last_shout) or is_nil(state.last_shout.created_by) do
      {:reply, "Sorry, I'm not sure who said that :-(", state}
    else
      {:reply, "#{state.last_shout.created_by} said that at #{state.last_shout.created_at}", state}
    end
  end
  
  def handle_call({:add, shout}, _from, state) do
    if valid_shout(shout) do
      entry = %{created_by: nil, created_at: Timex.now, body: shout}

      {:reply, :ok, %{state | shouts: MapSet.put(state.shouts, entry) }}
    else
      {:reply, {:error, "invalid shout, nil or not utf8?"}, state}
    end
  end

  def handle_call({:add_detail, time, subj, body}, _from, state) do
    if valid_shout(body) do
      entry = %{created_at: time, created_by: subj, body: body}

      {:reply, :ok, %{state | shouts: MapSet.put(state.shouts, entry) }}
    else
      {:reply, {:error, "invalid shout, nil or not utf8?"}, state}
    end
  end

  def handle_call(:random, _from, state) do
    random_shout = state.shouts |> Enum.shuffle |> List.first
    {:reply, random_shout, %{state | last_shout: random_shout}}
  end

  def handle_call(:dump, _from, state) do
    {:reply, state.shouts, state}
  end

  def handle_call({:load, path}, _from, state) do
    Logger.debug "loading shout database :: #{inspect path}"
    shouts = path |> File.read! |> Poison.decode!(keys: :atoms) |> MapSet.new

    {:reply, :ok, %{state | shouts: shouts}}
  end

  def handle_call({:persist, path}, _from, state) do
    Logger.debug "dumping shout database to disk ..."
    json_buf  = Poison.encode!(state.shouts)
    io_result = File.write(path, json_buf)

    {:reply, io_result, state}
  end

  defp canonical(text), do: String.replace(text, ~r/[^a-zA-Z]/, "")

  def valid_shout(text, ignore_length \\ false) do
    is_binary(text)
    and String.valid?(text)
    and canonical(text) != ""
    and String.upcase(canonical(text)) == canonical(text)
    and ((String.length(text) >= @min_shout_length) or ignore_length)
  end
end
