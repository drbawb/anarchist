defmodule Anarchist.CatFacts do
  use GenServer
  require Logger
  alias   Timex.Timezone

  @moduledoc """
  CatFacts provides users with interesting quotes from a variety
  of high-quality(TM) online APIs.
  """

  @api_cave    "db/cave.txt"
  @api_cat     "https://catfacts-api.appspot.com/api"
  @api_chuck   "https://api.chucknorris.io"
  @api_ron     "http://ron-swanson-quotes.herokuapp.com"
  @api_trump   "https://api.whatdoestrumpthink.com/api"
  @api_weather "http://api.openweathermap.org/data/2.5"

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, nil, opts)
  end

  def handle_call(:cave, _from, _state) do
    random_line = File.read!(@api_cave) |> String.split("\n") |> Enum.random()

    {:reply, random_line, nil}

  end

  def handle_call(:chuck, _from, _state) do
    factoid = HTTPoison.get!(@api_chuck <> "/jokes/random").body
    |> Poison.decode!()

    {:reply, factoid["value"], nil}
  end

  def handle_call(:fact, _from, _state) do
    factoid = HTTPoison.get!(@api_cat <> "/facts").body
    |> Poison.decode!()

    {:reply, List.first(factoid["facts"]), nil}
  end

  def handle_call(:ron, _from, _state) do
    factoid = HTTPoison.get!(@api_ron <> "/v2/quotes").body
    |> Poison.decode!()

    pretty_quote = """
    "#{List.first(factoid)}"

    -- Ron Swanson
    """

    {:reply, pretty_quote, nil}
  end

  def handle_call(:trump, _from, _state) do
    factoid = HTTPoison.get!(@api_trump <> "/v1/quotes/random").body
    |> Poison.decode!()

    {:reply, factoid["message"], nil}
  end

  def handle_call({:trump, subj}, _from, _state) do
    subject  = URI.encode(subj)
    full_uri = @api_trump <> "/v1/quotes/personalized?q=#{subject}"
    Logger.debug "calling trump api @ #{full_uri}"

    factoid = HTTPoison.get!(@api_trump <> "/v1/quotes/personalized?q=#{subject}").body
    |> Poison.decode!()

    {:reply, factoid["message"], nil}
  end

  def handle_call({:weather, zip}, _from, _state) do
    api_key = "9df6de42237ce586e8d9d1a283249124"
    subject = URI.encode(zip)
    factoid = HTTPoison.get!(@api_weather <> "/weather?zip=#{subject},us&APPID=#{api_key}").body
    |> Poison.decode!

    temp_c  = (factoid["main"]["temp"] - 273.15) |> Float.round(2)
    temp_f  = ((factoid["main"]["temp"] * (9/5)) - 459.67) |> Float.round(2)
    meta    = List.first(factoid["weather"])["description"]

    local_tz = Timezone.get(Timezone.Local.lookup())
    sunrise  = DateTime.from_unix!(factoid["sys"]["sunrise"]) |> Timezone.convert(local_tz)
    sunset   = DateTime.from_unix!(factoid["sys"]["sunset"])  |> Timezone.convert(local_tz)

    Logger.debug("weather @ #{inspect zip} :: #{inspect factoid}")
    {:reply, [raw: factoid, deg_c: temp_c, deg_f: temp_f, meta: meta, sunrise_at: sunrise, sunset_at: sunset], nil}
  end



end
