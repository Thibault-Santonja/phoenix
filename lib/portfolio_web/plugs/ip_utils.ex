defmodule PortfolioWeb.Plugs.IPUtils do
  @moduledoc """
  Utility functions for extracting and working with IP addresses from connections.

  Handles extraction of client IP addresses, including support for proxy headers
  like X-Forwarded-For commonly used behind load balancers and reverse proxies.
  """

  import Plug.Conn

  @doc """
  Extracts the client IP address from a connection.

  Checks the X-Forwarded-For header first (for proxies/load balancers),
  falling back to the connection's remote_ip if the header is not present.

  ## Examples

      iex> get_ip_address(conn_with_forwarded_for)
      "192.168.1.100"

      iex> get_ip_address(conn_direct)
      "127.0.0.1"
  """
  @spec get_ip_address(Plug.Conn.t()) :: String.t()
  def get_ip_address(conn) do
    case get_req_header(conn, "x-forwarded-for") do
      [ip | _] ->
        # Take first IP if multiple (original client)
        ip
        |> String.split(",")
        |> List.first()
        |> String.trim()

      [] ->
        # Fallback to remote_ip
        conn.remote_ip
        |> :inet.ntoa()
        |> to_string()
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
