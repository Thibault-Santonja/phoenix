import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :portfolio, Portfolio.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "portfolio_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :portfolio, PortfolioWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "sxlebCP09EzixtLZ5ZkeBMZqNNHcJQOHdlcMtP1wk5puEUZnnLyRkt3xHqXa/69X",
  server: false

# In test we don't send emails
config :portfolio, Portfolio.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Configure base URL for magic links in tests
config :portfolio, :base_url, "http://localhost:4002"

# Skip MX validation in most tests to avoid network dependencies
# Can be overridden in specific tests that need to test MX validation
config :portfolio, :skip_mx_validation, true

# Disable event handlers in test to avoid DB ownership issues with Ecto.Sandbox
# Event handlers run in separate processes and cannot access the test's DB connection
config :portfolio, :start_event_handlers, false

# Disable IP whitelist auto-refresh in test (ETS table is created but not populated from DB)
# Tests that need IP whitelist entries will populate the cache explicitly
config :portfolio, :auto_refresh_ip_whitelist, false

# Configure from email
config :portfolio, :from_email, "noreply@portfolio.test"

# Set logger level to warning to allow capture_log to work properly
# Log output is still suppressed by ExUnit unless capture_log is used
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure Oban for tests (disabled to avoid background jobs interfering with tests)
config :portfolio, Oban, testing: :manual
