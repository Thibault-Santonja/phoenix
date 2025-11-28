defmodule PortfolioWeb.HealthControllerTest do
  @moduledoc """
  Tests for health check endpoints.

  Verifies that:
  - Basic health check endpoint responds correctly
  - Ready endpoint checks all critical services
  - Response format is valid JSON
  - Status codes are appropriate
  - Timestamps are included in responses
  """
  use PortfolioWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns 200 OK with basic health status", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end

    test "response includes status field", %{conn: conn} do
      conn = get(conn, ~p"/health")
      response = json_response(conn, 200)

      assert response["status"] == "ok"
    end

    test "response includes service name", %{conn: conn} do
      conn = get(conn, ~p"/health")
      response = json_response(conn, 200)

      assert response["service"] == "portfolio"
    end

    test "response includes timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health")
      response = json_response(conn, 200)

      assert is_binary(response["timestamp"])
      # Verify timestamp is valid ISO8601 format
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(response["timestamp"])
    end

    test "response is fast (no database check)", %{conn: conn} do
      start_time = System.monotonic_time(:millisecond)
      _conn = get(conn, ~p"/health")
      end_time = System.monotonic_time(:millisecond)

      # Should be very fast (< 100ms) since it doesn't check database
      duration = end_time - start_time
      assert duration < 100, "Health check took #{duration}ms, should be < 100ms"
    end

    test "returns consistent structure across multiple calls", %{conn: conn} do
      response1 = get(conn, ~p"/health") |> json_response(200)
      response2 = get(conn, ~p"/health") |> json_response(200)

      # Structure should be identical
      assert Map.keys(response1) == Map.keys(response2)
      assert response1["status"] == response2["status"]
      assert response1["service"] == response2["service"]
    end
  end

  describe "GET /health/ready" do
    # Note: In test mode, Oban may not be running, so we accept both 200 and 503

    test "returns valid response (200 or 503 depending on Oban)", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      assert conn.status in [200, 503]
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]
    end

    test "response includes status field", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      # Accept any status code since Oban may not be running in tests
      response = conn |> response(conn.status) |> Jason.decode!()

      assert response["status"] in ["ready", "unhealthy"]
    end

    test "response includes checks map", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = conn |> response(conn.status) |> Jason.decode!()

      assert is_map(response["checks"])
      assert Map.has_key?(response["checks"], "database")
      assert Map.has_key?(response["checks"], "oban")
    end

    test "database check returns ok status", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = conn |> response(conn.status) |> Jason.decode!()

      assert response["checks"]["database"] == "ok"
    end

    test "oban check returns valid status", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = conn |> response(conn.status) |> Jason.decode!()

      # Oban may or may not be running in test mode
      assert response["checks"]["oban"] in ["ok", "not_running"]
    end

    test "response includes timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = conn |> response(conn.status) |> Jason.decode!()

      assert is_binary(response["timestamp"])
      assert {:ok, _datetime, _offset} = DateTime.from_iso8601(response["timestamp"])
    end

    test "all checks return string status", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = conn |> response(conn.status) |> Jason.decode!()

      Enum.each(response["checks"], fn {check_name, status} ->
        assert is_binary(status),
               "Check #{check_name} should return string status, got: #{inspect(status)}"
      end)
    end

    test "response structure is complete", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = conn |> response(conn.status) |> Jason.decode!()

      # Should have exactly these keys
      assert Map.keys(response) |> Enum.sort() == ["checks", "status", "timestamp"]
    end
  end

  describe "health check error scenarios" do
    test "ready endpoint handles all check combinations", %{conn: conn} do
      # This test verifies the endpoint doesn't crash
      # Even if individual checks fail, the endpoint should respond
      conn = get(conn, ~p"/health/ready")

      # Should always return 200 or 503, never crash
      assert conn.status in [200, 503]
    end

    test "basic health check never fails", %{conn: conn} do
      # Make multiple requests to ensure stability
      for _ <- 1..5 do
        conn = get(conn, ~p"/health")
        assert conn.status == 200
      end
    end
  end

  describe "response format validation" do
    test "health endpoint returns valid JSON", %{conn: conn} do
      conn = get(conn, ~p"/health")

      # Should not raise when parsing JSON
      assert is_map(json_response(conn, 200))
    end

    test "ready endpoint returns valid JSON", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      # Should not raise when parsing JSON (accept any status)
      response = conn |> response(conn.status) |> Jason.decode!()
      assert is_map(response)
    end

    test "health response has no extra fields", %{conn: conn} do
      conn = get(conn, ~p"/health")
      response = json_response(conn, 200)

      # Should only have these three fields
      expected_keys = ["service", "status", "timestamp"]
      assert Enum.sort(Map.keys(response)) == Enum.sort(expected_keys)
    end

    test "ready response has expected fields", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = conn |> response(conn.status) |> Jason.decode!()

      # Should only have these three fields
      expected_keys = ["checks", "status", "timestamp"]
      assert Enum.sort(Map.keys(response)) == Enum.sort(expected_keys)
    end
  end

  describe "timestamp format" do
    test "health endpoint timestamp is recent", %{conn: conn} do
      before = DateTime.utc_now()
      conn = get(conn, ~p"/health")
      after_time = DateTime.utc_now()

      response = json_response(conn, 200)
      {:ok, timestamp, 0} = DateTime.from_iso8601(response["timestamp"])

      # Timestamp should be between before and after
      assert DateTime.compare(timestamp, before) in [:gt, :eq]
      assert DateTime.compare(timestamp, after_time) in [:lt, :eq]
    end

    test "ready endpoint timestamp is recent", %{conn: conn} do
      before = DateTime.utc_now()
      conn = get(conn, ~p"/health/ready")
      after_time = DateTime.utc_now()

      response = conn |> response(conn.status) |> Jason.decode!()
      {:ok, timestamp, 0} = DateTime.from_iso8601(response["timestamp"])

      # Timestamp should be between before and after
      assert DateTime.compare(timestamp, before) in [:gt, :eq]
      assert DateTime.compare(timestamp, after_time) in [:lt, :eq]
    end
  end

  describe "monitoring and load balancer usage" do
    test "basic health check is suitable for frequent polling", %{conn: conn} do
      # Simulate frequent health checks (like a load balancer would do)
      results =
        for _ <- 1..10 do
          start = System.monotonic_time(:millisecond)
          conn = get(conn, ~p"/health")
          duration = System.monotonic_time(:millisecond) - start

          {conn.status, duration}
        end

      # All should succeed
      assert Enum.all?(results, fn {status, _duration} -> status == 200 end)

      # All should be fast (average < 50ms)
      avg_duration = results |> Enum.map(&elem(&1, 1)) |> Enum.sum() |> div(length(results))
      assert avg_duration < 50, "Average health check took #{avg_duration}ms, should be < 50ms"
    end

    test "ready check provides detailed service status", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")
      response = conn |> response(conn.status) |> Jason.decode!()

      # Should provide granular information about each service
      checks = response["checks"]
      assert map_size(checks) >= 2, "Should check at least database and oban"

      # Each check should have a clear status
      Enum.each(checks, fn {service, status} ->
        assert status in ["ok", "error", "not_running"],
               "Service #{service} has unclear status: #{status}"
      end)
    end
  end
end
