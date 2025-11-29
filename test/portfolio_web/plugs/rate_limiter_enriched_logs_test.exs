defmodule PortfolioWeb.Plugs.RateLimiterEnrichedLogsTest do
  use PortfolioWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Portfolio.RateLimiter
  alias PortfolioWeb.Plugs.RateLimiterPlug

  setup do
    # Reset all rate limiters to ensure clean state
    RateLimiter.reset_all()

    # Generate unique IP for this test to avoid conflicts
    unique_ip = {10, 0, 0, :erlang.unique_integer([:positive]) |> rem(255)}

    on_exit(fn ->
      # Clean up after test
      RateLimiter.reset_all()
    end)

    {:ok, unique_ip: unique_ip}
  end

  describe "enriched attack logs" do
    @tag skip_rate_limit_reset: [:login_attempt]
    test "logs include user-agent when rate limit is exceeded", %{
      conn: conn,
      unique_ip: unique_ip
    } do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("user-agent", "Mozilla/5.0 (suspicious bot)")
        |> Map.put(:remote_ip, unique_ip)

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      # Make 11 requests to exceed the limit
      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      assert log =~ "Rate limit exceeded"
      assert log =~ "user_agent"
      assert log =~ "Mozilla/5.0 (suspicious bot)"
    end

    @tag skip_rate_limit_reset: [:login_attempt]
    test "logs include referer when rate limit is exceeded", %{conn: conn, unique_ip: unique_ip} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("referer", "https://attacker.com/login")
        |> Map.put(:remote_ip, unique_ip)

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      assert log =~ "Rate limit exceeded"
      assert log =~ "referer"
      assert log =~ "https://attacker.com/login"
    end

    @tag skip_rate_limit_reset: [:login_attempt]
    test "logs include IP address when rate limit is exceeded", %{
      conn: conn,
      unique_ip: unique_ip
    } do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> Map.put(:remote_ip, unique_ip)

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      assert log =~ "Rate limit exceeded"
      assert log =~ "ip"
      # Check IP is logged (format: 10.0.0.X)
      assert log =~ ~r/10\.0\.0\.\d+/
    end

    @tag skip_rate_limit_reset: [:login_attempt]
    test "logs include request path when rate limit is exceeded", %{
      conn: conn,
      unique_ip: unique_ip
    } do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> Map.put(:remote_ip, unique_ip)
        |> Map.put(:request_path, "/auth/login")

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      assert log =~ "Rate limit exceeded"
      assert log =~ "path"
      assert log =~ "/auth/login"
    end

    @tag skip_rate_limit_reset: [:login_attempt]
    test "logs missing user-agent as unknown", %{conn: conn, unique_ip: unique_ip} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> Map.put(:remote_ip, unique_ip)

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      assert log =~ "Rate limit exceeded"
      assert log =~ "user_agent"
      assert log =~ "unknown"
    end

    @tag skip_rate_limit_reset: [:login_attempt]
    test "logs detect potential bot patterns in user-agent", %{conn: conn} do
      suspicious_agents = [
        "python-requests/2.28.0",
        "curl/7.68.0",
        "Scrapy/2.5.0",
        "bot"
      ]

      for {agent, index} <- Enum.with_index(suspicious_agents) do
        # Use unique IP per agent to avoid rate limit conflicts
        test_ip = {10, 1, 0, index}
        ip_string = "10.1.0.#{index}"
        RateLimiter.reset(:login_attempt, ip_string)

        conn =
          conn
          |> Plug.Test.init_test_session(%{})
          |> fetch_flash()
          |> put_req_header("user-agent", agent)
          |> Map.put(:remote_ip, test_ip)

        opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

        log =
          capture_log([level: :warning], fn ->
            for _ <- 1..11 do
              conn = RateLimiterPlug.call(conn, opts)
              if conn.halted, do: :ok
            end
          end)

        assert log =~ "Rate limit exceeded"
        assert log =~ "potential_bot"
        assert log =~ "true"
      end
    end
  end
end
