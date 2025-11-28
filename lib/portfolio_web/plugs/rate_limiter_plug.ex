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
  alias PortfolioWeb.Plugs.IPUtils

  # Dialyzer false positive: it infers whitelisted_ip?/1 always returns true
  # but the function correctly returns boolean based on IP whitelist check
  @dialyzer :no_match

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
    if opts.identifier == :ip and whitelisted_ip?(conn) do
      Logger.debug("Rate limit bypassed for whitelisted IP",
        action: opts.action,
        ip: IPUtils.get_ip_address(conn)
      )

      conn
    else
      do_rate_limit_check(conn, opts)
    end
  end

  # Perform the actual rate limit check
  defp do_rate_limit_check(conn, opts) do
    identifier = get_identifier(conn, opts.identifier, opts.param_name)

    case Portfolio.RateLimiter.check_rate(opts.action, identifier) do
      {:allow, _remaining} ->
        conn

      {:deny, retry_after_ms} ->
        retry_after_seconds = div(retry_after_ms, 1000)

        # Enriched logging with attack context
        ip = IPUtils.get_ip_address(conn)
        user_agent = IPUtils.get_user_agent(conn)
        referer = IPUtils.get_referer(conn)
        path = conn.request_path
        potential_bot = IPUtils.detect_bot?(conn)

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

  # Get the identifier based on the configuration
  defp get_identifier(conn, :ip, _param_name) do
    IPUtils.get_ip_address(conn)
  end

  defp get_identifier(conn, :param, param_name) when not is_nil(param_name) do
    conn.params[to_string(param_name)] || "unknown"
  end

  defp get_identifier(conn, {:custom, func}, _param_name) when is_function(func, 1) do
    func.(conn)
  end

  # Format retry time in a human-readable way
  defp format_retry_time(ms) when is_integer(ms) and ms < 3_600_000 do
    minutes = div(ms, 60_000)
    "#{minutes} minute#{if minutes > 1, do: "s", else: ""}"
  end

  defp format_retry_time(ms) when is_integer(ms) do
    hours = div(ms, 3_600_000)
    "#{hours} heure#{if hours > 1, do: "s", else: ""}"
  end

  # Vérifie si l'IP de la connexion est whitelistée
  defp whitelisted_ip?(conn) do
    ip = conn.remote_ip
    IPWhitelistService.whitelisted?(ip)
  end
end
