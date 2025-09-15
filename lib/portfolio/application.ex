defmodule Portfolio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      PortfolioWeb.Telemetry,
      Portfolio.Repo,
      {DNSCluster, query: Application.get_env(:portfolio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Portfolio.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Portfolio.Finch},
      # Start Hammer for rate limiting
      {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 2, cleanup_interval_ms: 60_000 * 10]},
      # Start the session cleaner worker for periodic cleanup
      Portfolio.Auth.SessionCleaner,
      # Start domain event handlers
      Portfolio.Photography.EventHandlers.AlbumPublishedHandler,
      Portfolio.Photography.EventHandlers.PhotoUploadedHandler,
      Portfolio.Auth.EventHandlers.MagicLinkHandler,
      # Start to serve requests, typically the last entry
      PortfolioWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Portfolio.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PortfolioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
