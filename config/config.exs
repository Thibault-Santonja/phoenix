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
  live_view: [signing_salt: "dev-signing-salt-not-for-production"]

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
  # Duree de vie maximale du cookie de session cote navigateur (24 heures)
  # Note: La session expire reellement selon auth.session_expiration_seconds (2h)
  max_age_seconds: 24 * 60 * 60

# Configure authentication
config :portfolio, :auth,
  # Duree d'inactivite maximale avant expiration de session (2 heures)
  # Une session inactive > 2h est supprimee et l'utilisateur doit se reconnecter
  # Nettoyage automatique par SessionCleanerWorker toutes les 15 minutes
  session_expiration_seconds: 2 * 60 * 60,
  # Throttle des mises a jour de last_activity_at pour reduire la charge DB (5 minutes)
  # last_activity_at n'est mis a jour que si la derniere MAJ remonte a > 5 minutes
  # Impact: reduction ~95% des ecritures DB, marge acceptable de 5 min sur 2h d'expiration
  activity_update_throttle_seconds: 5 * 60,
  # Duree de vie d'un magic link (15 minutes)
  # Un magic link expire 15 minutes apres sa creation
  # Nettoyage automatique par MagicLinkCleanerWorker toutes les heures
  magic_link_ttl_minutes: 15,
  # Duree de vie maximale d'une session (30 jours)
  # Meme si active, une session expire apres 30 jours (renouvellement requis)
  # Utilise pour les evenements et metadata (non enforce en DB actuellement)
  session_max_age_days: 30

# Configure admin interface
config :portfolio, :admin,
  # Number of albums to display per page in admin interface
  albums_per_page: 30

# Configure public timeline
config :portfolio, :timeline,
  # Number of albums to load per page in public timeline (lazy loading)
  albums_per_page: 20

# Configure file uploads
config :portfolio, :uploads,
  base_path: "priv/static/uploads",
  max_file_size: 10 * 1024 * 1024,
  allowed_mime_types: ["image/webp", "image/jpeg", "image/jpg", "image/png"]

# Configure file storage backend
config :portfolio, :file_storage, backend: Portfolio.Photography.Storage.LocalStorage

# Configure image variants for processing
# Aligned with Tailwind CSS breakpoints (ADR-011 Phase 4)
# - thumbnail: 400px WebP (Tailwind xs/sm range, cards/previews)
# - small: 768px WebP (Tailwind md breakpoint, tablets)
# - medium: 1280px WebP (Tailwind xl breakpoint, desktop)
# - large: 1920px AVIF (Full HD, fullscreen display, superior quality)
# Quality increases with size (75 -> 80 -> 85 -> 90) for professional portfolio
# AVIF for large variant: 30-40% better compression + superior perceptual quality
# Effort levels optimized for VPS (2 cores): lower effort on small variants for faster processing
config :portfolio, :image_variants,
  thumbnail: [width: 400, quality: 75, format: :webp, effort: 2],
  small: [width: 768, quality: 80, format: :webp, effort: 2],
  medium: [width: 1280, quality: 85, format: :webp, effort: 4],
  large: [width: 1920, quality: 90, format: :avif, effort: 6]

# Configure photo storage adapter
config :portfolio, :photo_storage_adapter, Portfolio.Photography.Storage.LocalStorage

# Configure Oban image processing queue
config :portfolio, :oban_image_processing, limit: 2

# Configure Oban (job processing)
config :portfolio, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    default: 10,
    image_processing: 2,
    exif_extraction: 5
  ],
  plugins: [
    # Pruner: Supprime les jobs completes/annules de plus de 7 jours
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    # Cron: Planification des taches recurrentes de nettoyage
    {Oban.Plugins.Cron,
     crontab: [
       # MagicLinkCleaner: Supprime les magic links expires (expires_at < now)
       # Frequence: Toutes les heures ("0 * * * *" = minute 0 de chaque heure)
       {"0 * * * *", Portfolio.Workers.MagicLinkCleanerWorker},
       # SessionCleaner: Supprime les sessions inactives (last_activity_at < now - 2h)
       # Frequence: Toutes les 15 minutes ("*/15 * * * *" = minutes 0, 15, 30, 45)
       {"*/15 * * * *", Portfolio.Workers.SessionCleanerWorker}
     ]}
  ],
  repo: Portfolio.Repo

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
    :created_by_id,
    :performed_by_id,
    :resource_type,
    :resource_id,
    :captured_at,
    :camera,
    # Storage metadata
    :source,
    :destination,
    :directory,
    :photo_dir,
    :source_path,
    :output_base_path,
    :expected_base,
    :attempted_path,
    # Common metadata
    :result,
    :reason,
    :error,
    :duration_ms,
    # Image processing metadata
    :variant,
    :width,
    :height,
    :quality,
    :format,
    :effort,
    :output_path,
    :path,
    :variant_count,
    :attempt,
    :max_attempts,
    :image_id,
    :fuse_name,
    # Validation metadata
    :expected_hash,
    :actual_hash,
    :errors,
    :fields,
    :paths,
    # Rate limiting metadata
    :action,
    :identifier,
    :bucket_key,
    :retry_after_seconds,
    :retry_after_ms,
    :remaining,
    :ip,
    :user_agent,
    :referer,
    :potential_bot,
    # CDN metadata
    :message,
    # Session metadata
    :token_prefix,
    # CSP report metadata
    :document_uri,
    :violated_directive,
    :blocked_uri,
    :source_file,
    :line_number,
    :column_number,
    :original_policy,
    :disposition,
    :referrer,
    :remote_ip,
    :raw_params
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
