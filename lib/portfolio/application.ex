defmodule Portfolio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  import Cachex.Spec

  alias Portfolio.Auth.IPWhitelistService
  alias Portfolio.ImageProcessing.CircuitBreaker

  @impl true
  def start(_type, _args) do
    # Base children that always start
    base_children = [
      PortfolioWeb.Telemetry,
      Portfolio.Repo,
      {DNSCluster, query: Application.get_env(:portfolio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Portfolio.PubSub},
      # Start the Finch HTTP client for sending emails
      {Finch, name: Portfolio.Finch},
      # Start Oban for background job processing
      {Oban, Application.fetch_env!(:portfolio, Oban)},
      # Start Hammer v7 for rate limiting
      {Portfolio.RateLimiter, clean_period: :timer.minutes(10)},
      # Start Cachex for caching with size limit (max 1000 entries)
      {Cachex,
       name: :portfolio_cache,
       hooks: [
         hook(
           module: Cachex.Limit.Scheduled,
           args: {1000, [], []}
         )
       ]},
      # Bootstrap admin user automatically (skipped in :test env)
      Portfolio.Bootstrap.Worker,
      # Start the session cleaner worker for periodic cleanup
      Portfolio.Auth.SessionCleaner
    ]

    # Event handlers - disabled in test environment to avoid DB ownership issues
    event_handlers =
      if Application.get_env(:portfolio, :start_event_handlers, true) do
        [
          Portfolio.Photography.EventHandlers.AlbumPublishedHandler,
          Portfolio.Photography.EventHandlers.PhotoUploadedHandler,
          Portfolio.Auth.EventHandlers.MagicLinkHandler
        ]
      else
        []
      end

    # Combine all children
    children = base_children ++ event_handlers ++ [PortfolioWeb.Endpoint]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Portfolio.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Initialiser le cache IP whitelist après le démarrage
    IPWhitelistService.init_cache()

    # Install circuit breaker for image processing
    CircuitBreaker.install()

    result
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PortfolioWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
