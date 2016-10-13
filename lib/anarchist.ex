defmodule Anarchist do
  use Application

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    import Supervisor.Spec, warn: false

    slack_token = Application.get_env(:anarchist, Anarchist.Endpoint)[:token]

    # Define workers and child supervisors to be supervised
    children = [
      worker(Anarchist.Poller,   [[name: Poller]]),
      worker(Anarchist.Shouter,  [[name: Shouter]]),
      worker(Anarchist.Endpoint, [slack_token]),
    ]

    # See http://elixir-lang.org/docs/stable/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Anarchist.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
