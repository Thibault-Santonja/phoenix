defmodule PortfolioWeb.Plugs.IPUtilsTest do
  use ExUnit.Case, async: false

  alias PortfolioWeb.Plugs.IPUtils

  setup do
    # Store original value and set default for tests
    original = Application.get_env(:portfolio, :trusted_proxy_count)
    Application.put_env(:portfolio, :trusted_proxy_count, 1)

    on_exit(fn ->
      if original do
        Application.put_env(:portfolio, :trusted_proxy_count, original)
      else
        Application.delete_env(:portfolio, :trusted_proxy_count)
      end
    end)

    :ok
  end

  describe "get_ip_address/1" do
    test "returns remote_ip when no X-Forwarded-For header" do
      conn = %Plug.Conn{
        remote_ip: {192, 168, 1, 100},
        req_headers: []
      }

      assert IPUtils.get_ip_address(conn) == "192.168.1.100"
    end

    test "returns first IP from X-Forwarded-For with single proxy (default config)" do
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "203.0.113.50, 10.0.0.1"}]
      }

      assert IPUtils.get_ip_address(conn) == "203.0.113.50"
    end

    test "handles single IP in X-Forwarded-For" do
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "203.0.113.50"}]
      }

      assert IPUtils.get_ip_address(conn) == "203.0.113.50"
    end

    test "handles whitespace in X-Forwarded-For" do
      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "  203.0.113.50  ,  10.0.0.1  "}]
      }

      assert IPUtils.get_ip_address(conn) == "203.0.113.50"
    end

    test "returns remote_ip when trusted_proxy_count is 0" do
      # Temporarily set trusted_proxy_count to 0
      original = Application.get_env(:portfolio, :trusted_proxy_count)
      Application.put_env(:portfolio, :trusted_proxy_count, 0)

      conn = %Plug.Conn{
        remote_ip: {192, 168, 1, 100},
        req_headers: [{"x-forwarded-for", "spoofed.ip, proxy.ip"}]
      }

      assert IPUtils.get_ip_address(conn) == "192.168.1.100"

      # Restore original value
      if original, do: Application.put_env(:portfolio, :trusted_proxy_count, original)
    end

    test "handles multiple trusted proxies" do
      # Set trusted_proxy_count to 2
      original = Application.get_env(:portfolio, :trusted_proxy_count)
      Application.put_env(:portfolio, :trusted_proxy_count, 2)

      conn = %Plug.Conn{
        remote_ip: {10, 0, 0, 1},
        req_headers: [{"x-forwarded-for", "spoofed, real-client, proxy1, proxy2"}]
      }

      assert IPUtils.get_ip_address(conn) == "real-client"

      # Restore original value
      if original do
        Application.put_env(:portfolio, :trusted_proxy_count, original)
      else
        Application.delete_env(:portfolio, :trusted_proxy_count)
      end
    end

    test "handles IPv6 addresses" do
      conn = %Plug.Conn{
        remote_ip: {0, 0, 0, 0, 0, 0, 0, 1},
        req_headers: []
      }

      assert IPUtils.get_ip_address(conn) == "::1"
    end
  end

  describe "get_user_agent/1" do
    test "returns user-agent header value" do
      conn = %Plug.Conn{
        req_headers: [{"user-agent", "Mozilla/5.0"}]
      }

      assert IPUtils.get_user_agent(conn) == "Mozilla/5.0"
    end

    test "returns 'unknown' when no user-agent header" do
      conn = %Plug.Conn{req_headers: []}

      assert IPUtils.get_user_agent(conn) == "unknown"
    end
  end

  describe "get_referer/1" do
    test "returns referer header value" do
      conn = %Plug.Conn{
        req_headers: [{"referer", "https://example.com"}]
      }

      assert IPUtils.get_referer(conn) == "https://example.com"
    end

    test "returns 'none' when no referer header" do
      conn = %Plug.Conn{req_headers: []}

      assert IPUtils.get_referer(conn) == "none"
    end
  end

  describe "detect_bot?/1" do
    test "detects common bots" do
      bot_agents = [
        "Googlebot/2.1",
        "Mozilla/5.0 (compatible; bingbot/2.0)",
        "python-requests/2.25.1",
        "curl/7.68.0",
        "Scrapy/2.5.0",
        "Mozilla/5.0 HeadlessChrome",
        "PhantomJS"
      ]

      for agent <- bot_agents do
        conn = %Plug.Conn{req_headers: [{"user-agent", agent}]}
        assert IPUtils.detect_bot?(conn), "Should detect bot: #{agent}"
      end
    end

    test "does not flag regular browsers" do
      browser_agents = [
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36",
        "Mozilla/5.0 (iPhone; CPU iPhone OS 14_6 like Mac OS X)"
      ]

      for agent <- browser_agents do
        conn = %Plug.Conn{req_headers: [{"user-agent", agent}]}
        refute IPUtils.detect_bot?(conn), "Should not flag browser: #{agent}"
      end
    end

    test "returns false for unknown user agent" do
      conn = %Plug.Conn{req_headers: []}
      refute IPUtils.detect_bot?(conn)
    end
  end
end
