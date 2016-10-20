defmodule Anarchist do
  use Application

  @moduledoc """
  The `@anarchist` chatbot consists of several modules and (at least)
  one endpoint on a chatroom.

  The endpoint is responsible for authenticating & parsing incoming
  commands from the chatroom it is connected to. It can proxy
  these commands to a number of synchronous services known as
  `modules` which provide chatbot behaviors.
  """

  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    slack_token = Application.get_env(:anarchist, Anarchist.Endpoint)[:token]

    children = [
      worker(Anarchist.CatFacts, [[name: CatFacts]]), # fetches random cat fact 
      worker(Anarchist.Dice,     [[name: Dice]]),     # rolls dice angrily
      worker(Anarchist.Poller,   [[name: Poller]]),   # conducts polls (per user)
      worker(Anarchist.Shouter,  [[name: Shouter]]),  # remembers shouts ...
      worker(Anarchist.Backup,   []),                 # backup the shout DB, etc.
      worker(Anarchist.Endpoint, [slack_token]),      # listens to slack RTM

      # manage long polling for the sandwich
      supervisor(Anarchist.Telegram, [], restart: :permanent)
    ]

    opts = [strategy: :one_for_one, name: Anarchist.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
