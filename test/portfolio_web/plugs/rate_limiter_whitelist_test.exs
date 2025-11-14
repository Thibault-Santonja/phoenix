defmodule PortfolioWeb.Plugs.RateLimiterWhitelistTest do
  use PortfolioWeb.ConnCase, async: false

  import PortfolioTest.Fixtures.AuthFixtures

  alias Portfolio.Auth.IPWhitelistService
  alias Portfolio.RateLimiter
  alias PortfolioWeb.Plugs.RateLimiterPlug

  setup %{conn: conn} do
    # Fetch session and flash to avoid errors in the plug
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> fetch_flash()

    # Reset rate limits before each test
    on_exit(fn ->
      RateLimiter.reset(:login_attempt, "192.168.1.100")
      RateLimiter.reset(:login_attempt, "10.0.0.1")
    end)

    {:ok, conn: conn}
  end

  describe "rate limiting with whitelist" do
    test "whitelisted IPs are not subject to rate limiting", %{conn: conn} do
      admin = create_user(role: :admin)
      whitelisted_ip = "192.168.1.100"

      # Add the IP to the whitelist
      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: whitelisted_ip}, admin.id)

      # Simulate the IP
      conn = %{conn | remote_ip: {192, 168, 1, 100}}

      # Make 20 requests (beyond the normal limit of 10)
      for _ <- 1..20 do
        conn =
          conn
          |> RateLimiterPlug.call(RateLimiterPlug.init(action: :login_attempt, identifier: :ip))

        # Should never be blocked
        refute conn.halted
      end
    end

    test "non-whitelisted IPs are still subject to rate limiting", %{conn: conn} do
      # Do NOT add the IP to the whitelist
      conn = %{conn | remote_ip: {10, 0, 0, 1}}

      # Make 11 requests (limit = 10)
      results =
        for i <- 1..11 do
          conn =
            conn
            |> RateLimiterPlug.call(RateLimiterPlug.init(action: :login_attempt, identifier: :ip))

          {i, conn.halted}
        end

      # The first 10 should pass
      assert Enum.take(results, 10) |> Enum.all?(fn {_i, halted} -> not halted end)

      # The 11th should be blocked
      assert {11, true} in results
    end

    test "whitelist works with different actions", %{conn: conn} do
      admin = create_user(role: :admin)
      whitelisted_ip = "192.168.1.100"

      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: whitelisted_ip}, admin.id)

      conn = %{conn | remote_ip: {192, 168, 1, 100}}

      # Test magic_link_request (limit = 5)
      for _ <- 1..10 do
        conn =
          conn
          |> RateLimiterPlug.call(
            RateLimiterPlug.init(action: :magic_link_request, identifier: :ip)
          )

        refute conn.halted
      end

      # Test magic_link_verify (limit = 10)
      for _ <- 1..15 do
        conn =
          conn
          |> RateLimiterPlug.call(
            RateLimiterPlug.init(action: :magic_link_verify, identifier: :ip)
          )

        refute conn.halted
      end
    end

    test "removing an IP from whitelist reactivates rate limiting", %{conn: conn} do
      admin = create_user(role: :admin)
      ip = "192.168.1.100"

      # Add the IP
      {:ok, entry} = IPWhitelistService.add_to_whitelist(%{ip_address: ip}, admin.id)

      conn = %{conn | remote_ip: {192, 168, 1, 100}}

      # Should work without limit
      for _ <- 1..15 do
        conn =
          conn
          |> RateLimiterPlug.call(RateLimiterPlug.init(action: :login_attempt, identifier: :ip))

        refute conn.halted
      end

      # Reset counters
      RateLimiter.reset(:login_attempt, ip)

      # Remove from whitelist
      {:ok, _} = IPWhitelistService.remove_from_whitelist(entry.id)

      # Now should be rate limited
      for i <- 1..11 do
        conn =
          conn
          |> RateLimiterPlug.call(RateLimiterPlug.init(action: :login_attempt, identifier: :ip))

        if i <= 10 do
          refute conn.halted, "Request #{i} should not be halted"
        else
          assert conn.halted, "Request #{i} should be halted"
        end
      end
    end

    test "whitelist works with IPv6 addresses", %{conn: conn} do
      admin = create_user(role: :admin)
      ipv6 = "2001:db8::1"

      {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: ipv6}, admin.id)

      # Simulate an IPv6 connection
      conn = %{conn | remote_ip: {0x2001, 0x0DB8, 0, 0, 0, 0, 0, 1}}

      # Should work without limit
      for _ <- 1..15 do
        conn =
          conn
          |> RateLimiterPlug.call(RateLimiterPlug.init(action: :login_attempt, identifier: :ip))

        refute conn.halted
      end
    end
  end

  describe "performance and cache" do
    test "whitelist verification does not significantly impact performance", %{
      conn: conn
    } do
      admin = create_user(role: :admin)

      # Add multiple IPs to the whitelist
      for i <- 1..10 do
        {:ok, _} = IPWhitelistService.add_to_whitelist(%{ip_address: "192.168.1.#{i}"}, admin.id)
      end

      conn = %{conn | remote_ip: {192, 168, 1, 100}}

      # Measure time for 100 verifications
      {time_microseconds, _result} =
        :timer.tc(fn ->
          for _ <- 1..100 do
            RateLimiterPlug.call(
              conn,
              RateLimiterPlug.init(action: :login_attempt, identifier: :ip)
            )
          end
        end)

      # Should be very fast (less than 100ms for 100 requests)
      assert time_microseconds < 100_000,
             "Whitelist check too slow: #{time_microseconds}µs for 100 requests"
    end
  end
end
