defmodule Anarchist.IRC do
  use     GenServer
  require Logger
  alias   ExIrc.Client

  defmodule Config do
    defstruct server:  nil,
              port:    nil,
              pass:    nil,
              nick:    nil,
              user:    nil,
              name:    nil,
              channel: nil,
              client:  nil,
              debug?:  true

  end

  def start_link(opts \\ []) do
    config = %Config{
      server:  "irc.rizon.net",
      port:    6667,
      channel: "#himebot_test",
      nick:    "himebot",
      user:    "himebot",
      pass:    "",
      name:    "himechans bot",
    }

    GenServer.start_link(__MODULE__, [config], opts)
  end

  def init([config]) do
    {:ok, client} = ExIrc.start_client!()
    Client.add_handler client, self()

    server = config.server
    port   = config.port
    Logger.debug "Connecting to #{server}:#{port}"
    Client.connect! client, server, port

    {:ok, %Config{config | :client => client}}
  end

  def handle_info({:connected, server, port}, config) do
    Logger.debug "connected to #{server}:#{port} successfully"
    Logger.debug "setting up nick"
    Client.logon config.client, config.pass, config.nick, config.user, config.name
    {:noreply, config}
  end

  def handle_info(:logged_in, config) do
    Logger.debug "logged into #{config.server}:#{config.port}"
    Logger.debug "joining channel #{config.channel}"
    Client.join config.client, config.channel
    {:noreply, config}
  end

  def handle_info(:disconnected, config) do
    Logger.debug "disconncted from #{config.server}:#{config.port}"
    {:stop, :normal, config}
  end

  def handle_info(msg, config) do
    Logger.info "irc :: #{inspect msg}"
    {:noreply, config}
  end

  def handle_call(msg, config) do
    Logger.info "ircall :: #{inspect msg}"
    {:noreply, config}
  end

  def terminate(_state, config) do
    Client.quit  config.client, "goodbye, cruel world."
    Client.stop! config.client
    :ok
  end
end
