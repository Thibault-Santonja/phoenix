defmodule PortfolioWeb.HealthController do
  @moduledoc """
  Health check endpoint for monitoring and Docker health checks.

  This endpoint is used by:
  - Docker healthcheck (docker-compose.preprod.yml)
  - Load balancers and monitoring services
  - Preproduction validation

  Returns 200 OK if:
  - Application is running
  - Database is accessible

  Returns 503 Service Unavailable if:
  - Database is not accessible
  """

  use PortfolioWeb, :controller

  alias Ecto.Adapters.SQL
  alias Portfolio.Repo

  @doc """
  Health check endpoint.

  Returns JSON with status and timestamp.

  ## Examples

      GET /health
      => 200 OK
      {
        "status": "ok",
        "timestamp": "2025-11-15T10:30:00Z",
        "database": "connected"
      }

      GET /health (when DB down)
      => 503 Service Unavailable
      {
        "status": "error",
        "message": "Database unavailable",
        "timestamp": "2025-11-15T10:30:00Z"
      }
  """
  def index(conn, _params) do
    case check_database() do
      :ok ->
        json(conn, %{
          status: "ok",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601(),
          database: "connected"
        })

      {:error, reason} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{
          status: "error",
          message: "Database unavailable: #{inspect(reason)}",
          timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
        })
    end
  end

  # Private functions

  defp check_database do
    # Simple query to verify database connectivity
    case SQL.query(Repo, "SELECT 1", []) do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  rescue
    error -> {:error, error}
  end
end
