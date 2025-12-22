defmodule PortfolioWeb.Plugs.IPUtils do
  @moduledoc """
  Utility functions for extracting and working with IP addresses from connections.

  Handles extraction of client IP addresses, including support for proxy headers
  like X-Forwarded-For commonly used behind load balancers and reverse proxies.

  ## Security Considerations

  The X-Forwarded-For header can be spoofed by malicious clients. This module
  uses a "trusted proxies" approach where only the rightmost N IPs are considered
  trustworthy (added by your infrastructure), and the IP just before them is
  the actual client IP.

  Configure the number of trusted proxies via:

      config :portfolio, :trusted_proxy_count, 1

  For example, with `trusted_proxy_count: 2` and header:
  `X-Forwarded-For: spoofed, real-client, proxy1, proxy2`

  The function will return "real-client" (skipping the 2 rightmost trusted proxies).
  """

  import Plug.Conn

  @doc """
  Extracts the client IP address from a connection.

  Uses the configured `trusted_proxy_count` to determine which IP in the
  X-Forwarded-For chain is the actual client. Falls back to conn.remote_ip
  if the header is not present.

  ## Configuration

  Set the number of trusted proxies in your config:

      config :portfolio, :trusted_proxy_count, 1

  ## Security

  - With 0 trusted proxies: Always uses conn.remote_ip (ignores X-Forwarded-For)
  - With N trusted proxies: Takes the IP at position (length - N) from the list
  - If the header has fewer IPs than trusted_proxy_count, uses the first IP

  ## Examples

      # Single proxy (default): X-Forwarded-For: client, proxy
      # Returns "client"

      # Two proxies: X-Forwarded-For: client, proxy1, proxy2
      # With trusted_proxy_count: 2, returns "client"
  """
  @spec get_ip_address(Plug.Conn.t()) :: String.t()
  def get_ip_address(conn) do
    trusted_count = Application.get_env(:portfolio, :trusted_proxy_count, 1)

    case get_req_header(conn, "x-forwarded-for") do
      [header | _] when trusted_count > 0 ->
        extract_client_ip_from_header(header, trusted_count)

      _ ->
        # No X-Forwarded-For header or no trusted proxies configured
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
    end
  end

  # Extracts the client IP from X-Forwarded-For header based on trusted proxy count
  @spec extract_client_ip_from_header(String.t(), non_neg_integer()) :: String.t()
  defp extract_client_ip_from_header(header, trusted_count) do
    ips =
      header
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    case ips do
      [] ->
        "unknown"

      _ ->
        # Calculate index: we want the IP just before the trusted proxies
        # If we have [client, proxy1, proxy2] and trusted_count=2, we want client (index 0)
        # length=3, index = 3 - 2 - 1 = 0
        client_index = max(0, length(ips) - trusted_count - 1)
        Enum.at(ips, client_index, List.first(ips))
    end
  end

  @doc """
  Extracts the User-Agent from request headers.

  Returns "unknown" if the header is not present.
  """
  @spec get_user_agent(Plug.Conn.t()) :: String.t()
  def get_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [user_agent | _] -> user_agent
      [] -> "unknown"
    end
  end

  @doc """
  Extracts the Referer from request headers.

  Returns "none" if the header is not present.
  """
  @spec get_referer(Plug.Conn.t()) :: String.t()
  def get_referer(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] -> referer
      [] -> "none"
    end
  end

  @doc """
  Detects potential bot based on User-Agent patterns.

  Checks for common bot, crawler, and automation tool signatures.
  """
  @spec detect_bot?(Plug.Conn.t()) :: boolean()
  def detect_bot?(conn) do
    user_agent = get_user_agent(conn) |> String.downcase()

    bot_patterns = [
      "bot",
      "crawler",
      "spider",
      "scraper",
      "curl",
      "wget",
      "python-requests",
      "scrapy",
      "selenium",
      "phantomjs",
      "headless"
    ]

    Enum.any?(bot_patterns, fn pattern ->
      String.contains?(user_agent, pattern)
    end)
  end
end
