defmodule Anarchist.CatFacts do
  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def handle_call(:fact, _from, _state) do
    factoid = HTTPoison.get!("https://catfacts-api.appspot.com/api/facts").body
    |> Poison.decode!()

    {:reply, List.first(factoid["facts"]), nil}
  end

end
