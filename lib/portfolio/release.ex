defmodule Portfolio.Release do
  @moduledoc """
  Release tasks for production deployments.

  These tasks are used to run database migrations and bootstrap
  operations when deploying to production.

  ## Usage

  In your deployment script (e.g., Dockerfile, fly.io config):

      /app/bin/portfolio eval "Portfolio.Release.migrate"
      /app/bin/portfolio eval "Portfolio.Release.bootstrap"

  Or combine both:

      /app/bin/portfolio eval "Portfolio.Release.migrate_and_bootstrap"

  ## Environment Variables

  - `ADMIN_EMAIL` - Email address for the initial admin user (default: "thibault.santonja@pm.me")
  """

  require Logger

  alias Portfolio.Auth.User
  alias Portfolio.Repo

  @app :portfolio

  @doc """
  Run pending database migrations.
  """
  @spec migrate() :: :ok
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc """
  Bootstrap the application with initial admin user.

  This task ensures that the admin user specified by ADMIN_EMAIL
  environment variable (or default) exists in the database.

  Safe to run multiple times - will not create duplicates.
  """
  @spec bootstrap() :: :ok
  def bootstrap do
    load_app()
    start_repo()

    admin_email = System.get_env("ADMIN_EMAIL") || "thibault.santonja@pm.me"

    case Repo.get_by(User, email: admin_email) do
      nil ->
        %User{}
        |> User.bootstrap_admin_changeset(%{
          email: admin_email,
          name: "Thibault Santonja",
          role: :admin
        })
        |> Repo.insert!()
        |> then(fn user ->
          Logger.info("Admin user created: #{user.email}")
        end)

      user ->
        ensure_user_is_admin(user)
    end

    :ok
  end

  @doc """
  Run migrations and bootstrap in one command.

  This is the recommended way to initialize the application in production.
  """
  @spec migrate_and_bootstrap() :: :ok
  def migrate_and_bootstrap do
    migrate()
    bootstrap()
  end

  # Private helpers

  defp load_app do
    _ = Application.load(@app)
    :ok
  end

  defp start_repo do
    Logger.info("Starting Repo...")
    _ = Application.ensure_all_started(:ssl)

    for repo <- repos() do
      {:ok, _} = repo.start_link(pool_size: 2)
    end

    :ok
  end

  # Assure que l'utilisateur a le rôle admin
  defp ensure_user_is_admin(user) do
    if user.role != :admin do
      promote_user_to_admin(user)
    else
      Logger.info("Admin user already exists: #{user.email}")
    end
  end

  # Promeut un utilisateur au rôle admin
  defp promote_user_to_admin(user) do
    user
    |> User.admin_changeset(%{role: :admin})
    |> Repo.update!()
    |> then(fn updated_user ->
      Logger.info("User #{updated_user.email} promoted to admin")
    end)
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
