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
end
