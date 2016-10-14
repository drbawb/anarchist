defmodule Anarchist.CatFacts do
  use GenServer
  require Logger

  @api_cat   "https://catfacts-api.appspot.com/api"
  @api_trump "https://api.whatdoestrumpthink.com/api"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def handle_call(:fact, _from, _state) do
    factoid = HTTPoison.get!(@api_cat <> "/facts").body
    |> Poison.decode!()

    {:reply, List.first(factoid["facts"]), nil}
  end

  def handle_call(:trump, _from, _state) do
    factoid = HTTPoison.get!(@api_trump <> "/v1/quotes/random").body
    |> Poison.decode!()

    {:reply, factoid["message"], nil}
  end

end
