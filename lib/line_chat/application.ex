defmodule LineChat.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias LineChat.Chat.Seeder
  alias LineChat.Chat.Store

  @impl true
  def start(_type, _args) do
    children = [
      LineChatWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:line_chat, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: LineChat.PubSub},
      # In-memory chat store, started before the endpoint so requests can read it
      {Store, []},
      # Start to serve requests, typically the last entry
      LineChatWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: LineChat.Supervisor]
    {:ok, pid} = Supervisor.start_link(children, opts)
    Seeder.seed()

    {:ok, pid}
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    LineChatWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
