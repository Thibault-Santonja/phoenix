defmodule PortfolioWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :portfolio

  # The session will be stored in the cookie and signed,
  # this means its contents can be read but not tampered with.
  # Set :encryption_salt if you would also like to encrypt it.
  @session_options [
    store: :cookie,
    key: "_portfolio_key",
    signing_salt: "sisdz80o",
    same_site: "Lax",
    compress: true,
    # Session persistante configurable (défaut: 24h)
    max_age: Application.compile_env(:portfolio, [:session, :max_age_seconds], 24 * 60 * 60),
    # Sécurité: empêche l'accès JavaScript au cookie (XSS protection)
    http_only: true,
    # Sécurité: cookie transmis uniquement via HTTPS en production
    secure: Application.compile_env!(:portfolio, :env) == :prod
  ]

  socket "/live", Phoenix.LiveView.Socket,
    websocket: [connect_info: [session: @session_options]],
    longpoll: [connect_info: [session: @session_options]]

  # Serve at "/" the static files from "priv/static" directory.
  #
  # You should set gzip to true if you are running phx.digest
  # when deploying your static files in production.
  plug Plug.Static,
    at: "/",
    from: :portfolio,
    gzip: false,
    only: PortfolioWeb.static_paths()

  if Code.ensure_loaded?(Tidewave) do
    plug Tidewave
  end

  # Code reloading can be explicitly enabled under the
  # :code_reloader configuration of your endpoint.
  if code_reloading? do
    socket "/phoenix/live_reload/socket", Phoenix.LiveReloader.Socket
    plug Phoenix.LiveReloader
    plug Phoenix.CodeReloader
  end

  plug Phoenix.LiveDashboard.RequestLogger,
    param_key: "request_logger",
    cookie_key: "request_logger"

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  # Content Security Policy
  plug :put_secure_headers

  plug Plug.Parsers,
    parsers: [:urlencoded, :multipart, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options

  # Rate limiting global (100 req/h par IP)
  plug PortfolioWeb.Plugs.RateLimiter

  plug PortfolioWeb.Router

  defp put_secure_headers(conn, _opts) do
    conn
    |> Plug.Conn.put_resp_header(
      "content-security-policy",
      "default-src 'self'; " <>
        "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
        "style-src 'self' 'unsafe-inline'; " <>
        "img-src 'self' data: https:; " <>
        "font-src 'self' data:; " <>
        "connect-src 'self' ws: wss:; " <>
        "frame-ancestors 'none';"
    )
    |> Plug.Conn.put_resp_header("x-frame-options", "DENY")
    |> Plug.Conn.put_resp_header("x-content-type-options", "nosniff")
    # X-XSS-Protection is deprecated and removed (modern browsers ignore it)
    |> Plug.Conn.put_resp_header(
      "strict-transport-security",
      "max-age=31536000; includeSubDomains"
    )
    |> Plug.Conn.put_resp_header(
      "referrer-policy",
      "strict-origin-when-cross-origin"
    )
    |> Plug.Conn.put_resp_header(
      "permissions-policy",
      "geolocation=(), microphone=(), camera=()"
    )
  end
end
