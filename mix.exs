defmodule Anarchist.Mixfile do
  use Mix.Project

  def project do
    [app: :anarchist,
     version: "0.5.0",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps()]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:ecto, :postgrex, :exirc, :logger, :slack, :timex, :yocingo],
     mod: {Anarchist, []}]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:ecto, "~> 2.0"},
     {:postgrex, ">= 0.0.0"},
     {:ex_doc, "~> 0.14", only: :dev},
     {:exirc, "~> 0.11"},
     {:poison, "~> 3.0"},
     {:httpoison, "~> 0.9"},
     {:timex, "~> 3.1"},
     {:slack, "~> 0.7"},
     {:websocket_client, github: "jeremyong/websocket_client"},
     {:yocingo, github: "drbawb/yocingo", branch: "dev/parse-mode"}]
  end
end
