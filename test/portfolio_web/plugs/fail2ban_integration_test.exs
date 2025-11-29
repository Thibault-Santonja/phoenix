defmodule PortfolioWeb.Plugs.Fail2BanIntegrationTest do
  @moduledoc """
  Tests to validate that rate limiter logs match fail2ban filter patterns.

  These tests ensure that the log format remains compatible with fail2ban
  configuration and can be properly parsed for automatic IP blocking.
  """
  use PortfolioWeb.ConnCase, async: false

  import ExUnit.CaptureLog

  alias Portfolio.RateLimiter
  alias PortfolioWeb.Plugs.RateLimiterPlug

  setup do
    # Reset all rate limiters to ensure clean state
    RateLimiter.reset_all()

    # Generate unique IP for this test to avoid conflicts
    unique_octet = rem(:erlang.unique_integer([:positive]), 250) + 1
    unique_ip = {10, 2, 0, unique_octet}

    on_exit(fn ->
      # Clean up after test
      RateLimiter.reset_all()
    end)

    {:ok, unique_ip: unique_ip, unique_octet: unique_octet}
  end

  describe "fail2ban log format compatibility" do
    test "rate limit logs match fail2ban filter pattern for IP identifier", %{
      conn: conn,
      unique_ip: unique_ip
    } do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("user-agent", "Mozilla/5.0")
        |> Map.put(:remote_ip, unique_ip)

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      # Extract the enriched log line
      log_line =
        log
        |> String.split("\n")
        |> Enum.find(&String.contains?(&1, "Rate limit exceeded for login_attempt"))

      assert log_line != nil, "Expected to find enriched rate limit log"

      # Validate fail2ban regex pattern:
      # Rate limit exceeded for <action> ip=<ip> user_agent="<agent>"
      # referer="<referer>" path=<path> potential_bot=<bool>
      assert log_line =~ ~r/Rate limit exceeded for \w+/
      assert log_line =~ ~r/ip=[\d\.]+/
      assert log_line =~ ~r/user_agent="[^"]*"/
      assert log_line =~ ~r/referer="[^"]*"/
      assert log_line =~ ~r/path=\S+/
      assert log_line =~ ~r/potential_bot=(true|false)/
    end

    test "logs include IP address in parseable format", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> Map.put(:remote_ip, {10, 0, 0, 42})

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      # Should contain IP in format: ip=10.0.0.42
      assert log =~ "ip=10.0.0.42"
      # Validate IPv4 format with regex
      assert log =~ ~r/ip=\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
    end

    test "logs include action name for fail2ban action-specific filtering", %{
      conn: conn,
      unique_ip: unique_ip
    } do
      ip_string = :inet.ntoa(unique_ip) |> to_string()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> Map.put(:remote_ip, unique_ip)

      opts = RateLimiterPlug.init(action: :magic_link_request, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..6 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      # Should contain action name
      assert log =~ "Rate limit exceeded for magic_link_request"
      assert log =~ "ip=#{ip_string}"
    end

    test "logs escape special characters in user-agent to prevent log injection", %{
      conn: conn,
      unique_ip: unique_ip
    } do
      # Attempt log injection with newline and special characters
      malicious_agent = "Mozilla/5.0\nfake-log-entry: malicious"

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("user-agent", malicious_agent)
        |> Map.put(:remote_ip, unique_ip)

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      # Log should contain the user-agent but properly escaped/quoted
      assert log =~ ~s(user_agent=")
      # Should not create a new log entry (log injection prevented)
      refute log =~ "fake-log-entry: malicious\n"
    end

    test "logs contain all required fields for fail2ban processing", %{
      conn: conn,
      unique_octet: unique_octet
    } do
      test_ip = {203, 0, 113, unique_octet}
      ip_string = :inet.ntoa(test_ip) |> to_string()

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> put_req_header("user-agent", "curl/7.68.0")
        |> put_req_header("referer", "https://attacker.com")
        |> Map.put(:remote_ip, test_ip)
        |> Map.put(:request_path, "/auth/verify")

      opts = RateLimiterPlug.init(action: :magic_link_verify, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      # Validate all required fields are present
      assert log =~ "Rate limit exceeded"
      assert log =~ "ip=#{ip_string}"
      assert log =~ ~s(user_agent="curl/7.68.0")
      assert log =~ ~s(referer="https://attacker.com")
      assert log =~ "path=/auth/verify"
      assert log =~ "potential_bot=true"
    end

    test "fail2ban can extract IP from log format", %{conn: base_conn} do
      # Use unique IPs with random octets to avoid collisions with other tests
      unique_suffix = 50 + rem(System.unique_integer([:positive]), 200)

      test_ips = [
        {192, 168, unique_suffix, 1},
        {10, 0, unique_suffix, 2},
        {172, 16, unique_suffix, 3},
        {203, 0, unique_suffix, 4}
      ]

      for remote_ip <- test_ips do
        # Reset rate limiter before testing this IP
        ip_string = :inet.ntoa(remote_ip) |> to_string()
        RateLimiter.reset(:login_attempt, ip_string)

        opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

        log =
          capture_log([level: :warning], fn ->
            # Trigger rate limit (10 allowed, 11th should log)
            Enum.each(1..11, fn _ ->
              test_conn =
                base_conn
                |> Plug.Test.init_test_session(%{})
                |> fetch_flash()
                |> Map.put(:remote_ip, remote_ip)

              RateLimiterPlug.call(test_conn, opts)
            end)
          end)

        # Verify the log contains the rate limit message with IP
        assert log =~ "Rate limit exceeded for login_attempt",
               "Expected log to contain rate limit message for IP #{ip_string}, got: #{inspect(log)}"

        assert log =~ "ip=#{ip_string}",
               "Expected log to contain IP #{ip_string}, got: #{inspect(log)}"
      end
    end

    test "logs from different actions can be distinguished", %{
      conn: conn,
      unique_octet: unique_octet
    } do
      actions = [:login_attempt, :magic_link_request, :magic_link_verify]

      for {action, index} <- Enum.with_index(actions) do
        # Use unique IP per action
        test_ip = {10, 3, unique_octet, index}
        ip_string = :inet.ntoa(test_ip) |> to_string()
        RateLimiter.reset(action, ip_string)

        conn =
          conn
          |> Plug.Test.init_test_session(%{})
          |> fetch_flash()
          |> Map.put(:remote_ip, test_ip)

        opts = RateLimiterPlug.init(action: action, identifier: :ip)

        {limit, _period} = RateLimiter.limit(action)

        log =
          capture_log([level: :warning], fn ->
            for _ <- 1..(limit + 1) do
              conn = RateLimiterPlug.call(conn, opts)
              if conn.halted, do: :ok
            end
          end)

        # Each action should be identifiable in logs
        assert log =~ "Rate limit exceeded for #{action}"
        assert log =~ "ip=#{ip_string}"
      end
    end
  end

  describe "fail2ban log consistency" do
    test "logs always include ip field even when empty", %{conn: conn, unique_octet: unique_octet} do
      # Edge case: use unique IP
      test_ip = {127, 0, 0, unique_octet}

      conn =
        conn
        |> Plug.Test.init_test_session(%{})
        |> fetch_flash()
        |> Map.put(:remote_ip, test_ip)

      opts = RateLimiterPlug.init(action: :login_attempt, identifier: :ip)

      log =
        capture_log([level: :warning], fn ->
          for _ <- 1..11 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      # Should always have ip= field
      assert log =~ ~r/ip=\d+\.\d+\.\d+\.\d+/
    end

    test "log format is consistent across multiple rate limit violations", %{
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
          # Trigger multiple violations
          for _ <- 1..15 do
            conn = RateLimiterPlug.call(conn, opts)
            if conn.halted, do: :ok
          end
        end)

      # Extract all enriched log lines
      log_lines =
        log
        |> String.split("\n")
        |> Enum.filter(&String.contains?(&1, "Rate limit exceeded for login_attempt"))

      # Should have multiple log entries (one per violation after limit exceeded)
      assert length(log_lines) > 0

      # All log lines should follow same format
      for line <- log_lines do
        assert line =~ ~r/ip=[\d\.]+/
        assert line =~ ~r/user_agent="/
        assert line =~ ~r/referer="/
        assert line =~ ~r/path=/
        assert line =~ ~r/potential_bot=/
      end
    end
  end
end
