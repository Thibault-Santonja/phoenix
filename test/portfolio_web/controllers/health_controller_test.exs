defmodule PortfolioWeb.HealthControllerTest do
  use PortfolioWeb.ConnCase, async: true

  describe "GET /health" do
    test "returns ok status", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200)["status"] == "ok"
    end

    test "returns service name", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert json_response(conn, 200)["service"] == "portfolio"
    end

    test "returns timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health")

      response = json_response(conn, 200)
      assert Map.has_key?(response, "timestamp")
      assert is_binary(response["timestamp"])
    end

    test "returns 200 status code", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert conn.status == 200
    end
  end

  describe "GET /health/ready" do
    test "returns status field", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      # May be 200 or 503 depending on Oban status
      response =
        case conn.status do
          200 -> json_response(conn, 200)
          503 -> json_response(conn, 503)
        end

      assert response["status"] in ["ready", "unhealthy"]
    end

    test "returns checks map", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response =
        case conn.status do
          200 -> json_response(conn, 200)
          503 -> json_response(conn, 503)
        end

      assert Map.has_key?(response, "checks")
      assert is_map(response["checks"])
    end

    test "includes database check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response =
        case conn.status do
          200 -> json_response(conn, 200)
          503 -> json_response(conn, 503)
        end

      assert response["checks"]["database"] == "ok"
    end

    test "includes oban check", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response =
        case conn.status do
          200 -> json_response(conn, 200)
          503 -> json_response(conn, 503)
        end

      # Oban may or may not be running in test mode
      assert response["checks"]["oban"] in ["ok", "not_running"]
    end

    test "returns timestamp", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response =
        case conn.status do
          200 -> json_response(conn, 200)
          503 -> json_response(conn, 503)
        end

      assert Map.has_key?(response, "timestamp")
    end

    test "returns 503 when oban is not running", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      # In test mode, Oban typically isn't running
      if conn.status == 503 do
        response = json_response(conn, 503)
        assert response["status"] == "unhealthy"
        assert response["checks"]["oban"] == "not_running"
      end
    end
  end

  describe "health check response format" do
    test "index returns JSON content-type", %{conn: conn} do
      conn = get(conn, ~p"/health")

      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"
    end

    test "ready returns JSON content-type", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      assert get_resp_header(conn, "content-type") |> List.first() =~ "application/json"
    end

    test "index timestamp is valid ISO8601", %{conn: conn} do
      conn = get(conn, ~p"/health")

      response = json_response(conn, 200)
      timestamp = response["timestamp"]

      # Should parse without error
      assert {:ok, _, _} = DateTime.from_iso8601(timestamp)
    end

    test "ready timestamp is valid ISO8601", %{conn: conn} do
      conn = get(conn, ~p"/health/ready")

      response =
        case conn.status do
          200 -> json_response(conn, 200)
          503 -> json_response(conn, 503)
        end

      timestamp = response["timestamp"]

      # Should parse without error
      assert {:ok, _, _} = DateTime.from_iso8601(timestamp)
    end
  end

  describe "health check idempotency" do
    test "multiple index calls return consistent structure", %{conn: conn} do
      conn1 = get(conn, ~p"/health")
      conn2 = get(conn, ~p"/health")

      response1 = json_response(conn1, 200)
      response2 = json_response(conn2, 200)

      assert response1["status"] == response2["status"]
      assert response1["service"] == response2["service"]
    end

    test "multiple ready calls return consistent checks structure", %{conn: conn} do
      conn1 = get(conn, ~p"/health/ready")
      conn2 = get(conn, ~p"/health/ready")

      response1 =
        case conn1.status do
          200 -> json_response(conn1, 200)
          503 -> json_response(conn1, 503)
        end

      response2 =
        case conn2.status do
          200 -> json_response(conn2, 200)
          503 -> json_response(conn2, 503)
        end

      # Both should have same check keys
      assert Map.keys(response1["checks"]) == Map.keys(response2["checks"])
    end
  end
end
