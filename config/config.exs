# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :portfolio,
  ecto_repos: [Portfolio.Repo],
  env: config_env(),
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Bootstrap configuration
config :portfolio, Portfolio.Bootstrap,
  max_retries: 20,
  retry_interval_ms: 30_000

# Configures the endpoint
config :portfolio, PortfolioWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: PortfolioWeb.ErrorHTML, json: PortfolioWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Portfolio.PubSub,
  live_view: [signing_salt: "1FbtJcpx"]

# Configures the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :portfolio, Portfolio.Mailer, adapter: Swoosh.Adapters.Local
config :portfolio, PortfolioWeb.Gettext, locales: ~w(en fr)

# Configure session settings
config :portfolio, :session,
  # Session cookie max age in seconds (default: 24 hours)
  max_age_seconds: 24 * 60 * 60

# Configure authentication
config :portfolio, :auth,
  # Session inactivity timeout in seconds (default: 2 hours)
  session_expiration_seconds: 2 * 60 * 60

# Configure admin interface
config :portfolio, :admin,
  # Number of albums to display per page in admin interface
  albums_per_page: 30

# Configure file uploads
config :portfolio, :uploads,
  base_path: "priv/static/uploads",
  max_file_size: 10 * 1024 * 1024,
  allowed_mime_types: ["image/webp", "image/jpeg", "image/jpg", "image/png"]

# Configure file storage backend
config :portfolio, :file_storage, backend: Portfolio.Photography.Storage.LocalStorage

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  portfolio: [
    args: ~w(
        js/app.js
        --bundle
        --target=es2017
        --outdir=../priv/static/assets
        --external:/fonts/*
        --external:/images/*
      ),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.4.3",
  portfolio: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    # Photography context metadata
    :album_id,
    :album_slug,
    :photo_id,
    :file_path,
    :hash,
    :count,
    :title,
    :slug,
    :published_at,
    :uploaded_at,
    # Auth context metadata
    :user_id,
    :email,
    :magic_link_id,
    :requested_at,
    :expires_at,
    :verified_at,
    # Storage metadata
    :source,
    :destination,
    :directory,
    # Common metadata
    :result,
    :reason,
    :error,
    :duration_ms
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
