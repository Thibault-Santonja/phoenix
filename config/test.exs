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

# Configure from email
config :portfolio, :from_email, "noreply@portfolio.test"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Configure Hammer for rate limiting in tests
config :hammer,
  backend: {Hammer.Backend.ETS, [expiry_ms: 60_000 * 60 * 2, cleanup_interval_ms: 60_000 * 10]}

# Configure Oban for tests (disabled to avoid background jobs interfering with tests)
config :portfolio, Oban, testing: :manual
