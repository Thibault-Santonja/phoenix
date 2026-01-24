defmodule PortfolioWeb.HealthController do
  @moduledoc """
  Health check endpoint for monitoring and load balancers.

  This controller provides a lightweight endpoint to verify that:
  1. The application is running
  2. The database is accessible
  3. Critical services are operational

  Used by:
  - Docker HEALTHCHECK
  - Kamal health checks
  - Load balancers
  - Monitoring tools (UptimeRobot, etc.)
  """

  use PortfolioWeb, :controller

  alias Portfolio.Repo

  @doc """
  Basic health check endpoint.

  Returns 200 OK with minimal response time.
  Does NOT check database or external services to keep it fast.

  ## Examples

      GET /health
      => 200 OK
      {
        "status": "ok",
        "service": "portfolio"
      }
  """
  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      service: "portfolio",
      timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
    })
  end

  @doc """
  Deep health check endpoint.

  Verifies database connectivity and critical services.
  Use this for monitoring, NOT for load balancer health checks
  (too slow for high-frequency checks).

  ## Examples

      GET /health/ready
      => 200 OK
      {
        "status": "ready",
        "checks": {
          "database": "ok",
          "oban": "ok"
        }
      }

      GET /health/ready
      => 503 Service Unavailable
      {
        "status": "unhealthy",
        "checks": {
          "database": "error"
        }
      }
  """
  def ready(conn, _params) do
    checks = %{
      database: check_database(),
      oban: check_oban()
    }

    all_healthy = Enum.all?(checks, fn {_key, status} -> status == "ok" end)

    if all_healthy do
      json(conn, %{
        status: "ready",
        checks: checks,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    else
      conn
      |> put_status(:service_unavailable)
      |> json(%{
        status: "unhealthy",
        checks: checks,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })
    end
  end

  # Check database connectivity with a simple query
  defp check_database do
    # Simple query that doesn't hit any table (fast)
    _ = Repo.query!("SELECT 1")
    "ok"
  rescue
    _ -> "error"
  end

  # Check if Oban is running
  defp check_oban do
    # Check if Oban supervisor is alive
    case Process.whereis(Oban) do
      nil -> "not_running"
      _pid -> "ok"
    end
  rescue
    _ -> "error"
  end
end
