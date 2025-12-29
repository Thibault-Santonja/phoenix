import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Auth Configuration
#
# Session expiration time in seconds (default: 2 hours, aligned with config.exs)
# Can be overridden with SESSION_EXPIRATION_SECONDS env var
session_expiration_seconds =
  case System.get_env("SESSION_EXPIRATION_SECONDS") do
    # 2 hours by default (aligned with config.exs :auth configuration)
    nil ->
      2 * 60 * 60

    val ->
      case Integer.parse(val) do
        {int, ""} -> int
        _ -> raise "Invalid SESSION_EXPIRATION_SECONDS: #{val}"
      end
  end

config :portfolio, :auth, session_expiration_seconds: session_expiration_seconds

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/portfolio start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :portfolio, PortfolioWeb.Endpoint, server: true
end

if config_env() == :prod do
  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  host =
    System.get_env("PHX_HOST") ||
      raise """
      environment variable PHX_HOST is missing.
      This is required in production for check_origin and LiveView connections.
      For example: example.com
      """

  port =
    case System.get_env("PORT") do
      nil ->
        4000

      val ->
        case Integer.parse(val) do
          {int, ""} -> int
          _ -> raise "Invalid PORT: #{val}. Must be a valid integer (e.g., 4000)"
        end
    end

  # Database connection pool configuration
  # POOL_SIZE: Number of connections in the pool (default: 10)
  # QUEUE_TARGET: Target time for a connection to be checked out (ms, default: 50)
  # QUEUE_INTERVAL: Interval for pool health checks (ms, default: 1000)
  pool_size =
    case System.get_env("POOL_SIZE") do
      nil ->
        10

      val ->
        case Integer.parse(val) do
          {int, ""} -> int
          _ -> raise "Invalid POOL_SIZE: #{val}. Must be a valid integer (e.g., 10)"
        end
    end

  # IPv6 socket options if ECTO_IPV6 is set
  socket_options = if System.get_env("ECTO_IPV6") == "true", do: [:inet6], else: []

  # SSL configuration
  # DATABASE_SSL: Enable SSL for database connections ("true" to enable)
  # DATABASE_SSL_VERIFY: SSL verification mode ("verify_peer" default, "verify_none" for self-signed)
  # DATABASE_SSL_CACERTFILE: Path to custom CA certificate file (optional, uses system CAs by default)
  ssl_enabled = System.get_env("DATABASE_SSL") == "true"

  ssl_opts =
    if ssl_enabled do
      verify_mode =
        case System.get_env("DATABASE_SSL_VERIFY") do
          "verify_none" -> :verify_none
          _ -> :verify_peer
        end

      base_opts = [verify: verify_mode]

      # Use custom CA cert file if provided, otherwise use system CAs
      case System.get_env("DATABASE_SSL_CACERTFILE") do
        nil -> base_opts ++ [cacerts: :public_key.cacerts_get()]
        path -> base_opts ++ [cacertfile: path]
      end
    else
      []
    end

  # Query timeout in milliseconds (default: 15 seconds)
  # Prevents runaway queries from consuming resources indefinitely
  query_timeout =
    case System.get_env("DATABASE_QUERY_TIMEOUT") do
      nil ->
        15_000

      val ->
        case Integer.parse(val) do
          {int, ""} -> int
          _ -> raise "Invalid DATABASE_QUERY_TIMEOUT: #{val}. Must be a valid integer in ms"
        end
    end

  config :portfolio, Portfolio.Repo,
    url: database_url,
    pool_size: pool_size,
    # Query timeout to prevent runaway queries (15s default)
    timeout: query_timeout,
    # Connection checkout queue settings for handling traffic spikes
    queue_target: 50,
    queue_interval: 1000,
    # Socket options for connection reliability
    socket_options: socket_options,
    # SSL configuration (if DATABASE_SSL is set)
    ssl: ssl_enabled,
    ssl_opts: ssl_opts

  config :portfolio, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :portfolio, PortfolioWeb.Endpoint,
    check_origin: [
      "https://#{host}",
      "https://amvcc.#{host}",
      "https://photo.#{host}",
      "https://tech.#{host}"
    ],
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://hexdocs.pm/bandit/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    # Force SSL with HSTS (HTTP Strict Transport Security)
    # Ensures all traffic is redirected to HTTPS and browsers remember to use HTTPS
    force_ssl: [hsts: true],
    live_view: [
      signing_salt:
        System.get_env("LIVE_VIEW_SIGNING_SALT") ||
          raise("environment variable LIVE_VIEW_SIGNING_SALT is missing")
    ]

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :portfolio, PortfolioWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://hexdocs.pm/plug/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :portfolio, PortfolioWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.

  # ## Configuring the mailer
  #
  # In production you need to configure the mailer to use a different adapter.
  # Also, you may need to configure the Swoosh API client of your choice if you
  # are not using SMTP. Here is an example of the configuration:
  #
  #     config :portfolio, Portfolio.Mailer,
  #       adapter: Swoosh.Adapters.Mailgun,
  #       api_key: System.get_env("MAILGUN_API_KEY"),
  #       domain: System.get_env("MAILGUN_DOMAIN")
  #
  # For this example you need include a HTTP client required by Swoosh API client.
  # Swoosh supports Hackney and Finch out of the box:
  #
  #     config :swoosh, :api_client, Swoosh.ApiClient.Hackney
  #
  # See https://hexdocs.pm/swoosh/Swoosh.html#module-installation for details.
end
