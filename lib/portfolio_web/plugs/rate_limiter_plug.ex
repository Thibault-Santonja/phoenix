defmodule PortfolioWeb.Plugs.RateLimiterPlug do
  @moduledoc """
  Plug for rate limiting HTTP requests.

  Uses Portfolio.RateLimiter (Hammer-based) to prevent abuse of endpoints.

  ## Usage

  In a controller:

      plug PortfolioWeb.Plugs.RateLimiterPlug,
        action: :magic_link_verify,
        identifier: :ip
        when action in [:verify_magic_link]

  ## Options

  - `:action` - Rate limit action type (atom, required)
  - `:identifier` - How to identify the requester (required)
    - `:ip` - Use client IP address
    - `:param` - Use a parameter value (specify `:param_name`)
    - `{:custom, function}` - Custom function that takes conn and returns identifier
  - `:param_name` - Parameter name when using `:param` identifier (atom or string)

  ## Examples

      # Rate limit by IP
      plug RateLimiterPlug, action: :magic_link_verify, identifier: :ip

      # Rate limit by email parameter
      plug RateLimiterPlug,
        action: :magic_link_request,
        identifier: :param,
        param_name: "email"

      # Custom identifier
      plug RateLimiterPlug,
        action: :api_request,
        identifier: {:custom, &get_user_id/1}
  """

  import Plug.Conn
  import Phoenix.Controller

  require Logger

  alias Portfolio.Auth.IPWhitelistService

  @doc """
  Initializes the plug with options.
  """
  def init(opts) do
    action = Keyword.fetch!(opts, :action)
    identifier = Keyword.fetch!(opts, :identifier)
    param_name = Keyword.get(opts, :param_name)

    %{
      action: action,
      identifier: identifier,
      param_name: param_name
    }
  end

  @doc """
  Checks rate limit for the request.

  If the IP is whitelisted, the request bypasses rate limiting.
  Otherwise, if rate limit is exceeded, returns 429 Too Many Requests and halts the connection.
  """
  def call(conn, opts) do
    # Si identifier est :ip, vérifier d'abord la whitelist
    if opts.identifier == :ip && whitelisted_ip?(conn) do
      Logger.debug("Rate limit bypassed for whitelisted IP",
        action: opts.action,
        ip: get_ip_address(conn)
      )

      conn
    else
      identifier = get_identifier(conn, opts.identifier, opts.param_name)

      case Portfolio.RateLimiter.check_rate(opts.action, identifier) do
        {:allow, _remaining} ->
          conn

        {:deny, retry_after_ms} ->
          retry_after_seconds = div(retry_after_ms, 1000)

          # Enriched logging with attack context
          ip = get_ip_address(conn)
          user_agent = get_user_agent(conn)
          referer = get_referer(conn)
          path = conn.request_path
          potential_bot = detect_bot?(conn)

          Logger.warning(
            ~s(Rate limit exceeded for #{opts.action} ip=#{ip} user_agent="#{user_agent}" referer="#{referer}" path=#{path} potential_bot=#{potential_bot}),
            action: opts.action,
            identifier: identifier,
            retry_after_seconds: retry_after_seconds,
            ip: ip,
            user_agent: user_agent,
            referer: referer,
            path: path,
            potential_bot: potential_bot
          )

          conn
          |> put_resp_header("retry-after", to_string(retry_after_seconds))
          |> put_flash(
            :error,
            "Trop de tentatives. Veuillez patienter #{format_retry_time(retry_after_ms)} avant de réessayer."
          )
          |> redirect(to: "/login")
          |> halt()
      end
    end
  end

  # Get the identifier based on the configuration
  defp get_identifier(conn, :ip, _param_name) do
    get_ip_address(conn)
  end

  defp get_identifier(conn, :param, param_name) when not is_nil(param_name) do
    conn.params[to_string(param_name)] || "unknown"
  end

  defp get_identifier(conn, {:custom, func}, _param_name) when is_function(func, 1) do
    func.(conn)
  end

  # Extract IP address from connection
  defp get_ip_address(conn) do
    # Check X-Forwarded-For header first (for proxies/load balancers)
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

  # Format retry time in a human-readable way
  defp format_retry_time(ms) when ms < 60_000 do
    seconds = div(ms, 1000)
    "#{seconds} seconde#{if seconds > 1, do: "s", else: ""}"
  end

  defp format_retry_time(ms) when ms < 3_600_000 do
    minutes = div(ms, 60_000)
    "#{minutes} minute#{if minutes > 1, do: "s", else: ""}"
  end

  defp format_retry_time(ms) do
    hours = div(ms, 3_600_000)
    "#{hours} heure#{if hours > 1, do: "s", else: ""}"
  end

  # Vérifie si l'IP de la connexion est whitelistée
  defp whitelisted_ip?(conn) do
    ip = conn.remote_ip
    IPWhitelistService.whitelisted?(ip)
  end

  # Extract User-Agent from request headers
  defp get_user_agent(conn) do
    case get_req_header(conn, "user-agent") do
      [user_agent | _] -> user_agent
      [] -> "unknown"
    end
  end

  # Extract Referer from request headers
  defp get_referer(conn) do
    case get_req_header(conn, "referer") do
      [referer | _] -> referer
      [] -> "none"
    end
  end

  # Detect potential bot based on User-Agent patterns
  defp detect_bot?(conn) do
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
