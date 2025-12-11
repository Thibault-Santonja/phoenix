defmodule PortfolioWeb.HealthControllerTest do
  use PortfolioWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 OK with status", %{conn: conn} do
      conn = get(conn, "/health")

      assert json_response(conn, 200)["status"] == "ok"
      assert json_response(conn, 200)["service"] == "portfolio"
      assert json_response(conn, 200)["timestamp"] != nil
    end

    test "responds quickly (no database check)", %{conn: conn} do
      {time_micros, _result} = :timer.tc(fn -> get(conn, "/health") end)

      # Should respond in under 100ms
      assert time_micros < 100_000
    end
  end

  describe "GET /health/ready" do
    test "returns response with checks", %{conn: conn} do
      conn = get(conn, "/health/ready")

      # May return 200 or 503 depending on Oban status
      response = json_response(conn, conn.status)
      assert response["status"] in ["ready", "unhealthy"]
      assert is_map(response["checks"])
      assert response["timestamp"] != nil
    end

    test "checks database connectivity", %{conn: conn} do
      conn = get(conn, "/health/ready")

      response = json_response(conn, conn.status)
      # Database should always be ok in test
      assert response["checks"]["database"] == "ok"
    end

    test "checks Oban status", %{conn: conn} do
      conn = get(conn, "/health/ready")

      response = json_response(conn, conn.status)
      # Oban may or may not be running in test environment
      assert response["checks"]["oban"] in ["ok", "not_running"]
    end

    test "includes timestamp in response", %{conn: conn} do
      conn = get(conn, "/health/ready")

      response = json_response(conn, conn.status)
      assert is_binary(response["timestamp"])
      # Verify it's a valid ISO8601 timestamp
      assert {:ok, _, _} = DateTime.from_iso8601(response["timestamp"])
    end

    test "returns 503 when a service is unhealthy", %{conn: conn} do
      conn = get(conn, "/health/ready")

      response = json_response(conn, conn.status)

      # If Oban is not running, status should be 503
      if response["checks"]["oban"] == "not_running" do
        assert conn.status == 503
        assert response["status"] == "unhealthy"
      else
        assert conn.status == 200
        assert response["status"] == "ready"
      end
    end
  end
end
