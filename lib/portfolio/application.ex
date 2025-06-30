defmodule Portfolio.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Portfolio.Repo,
      PortfolioWeb.Telemetry,
      {Oban,
       AshOban.config(
         Application.fetch_env!(:portfolio, :ash_domains),
         Application.fetch_env!(:portfolio, Oban)
       )},
      # Start the Finch HTTP client for sending emails
      # Start a worker by calling: Portfolio.Worker.start_link(arg)
      # {Portfolio.Worker, arg},
      # Start to serve requests, typically the last entry
      {DNSCluster, query: Application.get_env(:portfolio, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Portfolio.PubSub},
      {Finch, name: Portfolio.Finch},
      PortfolioWeb.Endpoint,
      {AshAuthentication.Supervisor, [otp_app: :portfolio]}
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
