defmodule LineChat.MixProject do
  use Mix.Project

  def project do
    [
      app: :line_chat,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.html": :test,
        "coveralls.threshold": :test
      ]
    ]
  end

  def cli do
    [preferred_envs: ["test.browser": :test, check: :test]]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {LineChat.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  defp deps do
    [
      {:phoenix, "~> 1.8.0"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_live_dashboard, "~> 0.8.3"},
      {:floki, ">= 0.30.0", only: :test},
      {:lazy_html, ">= 0.1.0", only: :test},
      {:esbuild, "~> 0.8", runtime: Mix.env() == :dev},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:dns_cluster, "~> 0.1.1"},
      {:bandit, "~> 1.5"},
      {:credo, "~> 1.7.0", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18.5", only: :test, runtime: false}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  #
  #     $ mix setup
  #
  # See the documentation for `mix help mix.alias` for more information.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["esbuild.install --if-missing"],
      "assets.build": ["esbuild line_chat"],
      "assets.deploy": ["esbuild line_chat --minify", "phx.digest"],
      "test.browser": ["cmd node --test test/browser/*.test.mjs"],
      check: ["format --check-formatted", "credo --strict", "test", "test.browser"]
    ]
  end
end
