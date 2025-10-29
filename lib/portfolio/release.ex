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
  """

  @app :portfolio

  @doc """
  Run pending database migrations.
  """
  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  @doc """
  Bootstrap the application with initial admin user.

  This task ensures that the admin user specified by ADMIN_EMAIL
  environment variable (or default) exists in the database.

  Safe to run multiple times - will not create duplicates.
  """
  def bootstrap do
    load_app()
    start_repo()

    alias Portfolio.Auth.User
    alias Portfolio.Repo

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
          IO.puts("✓ Admin user created: #{user.email}")
        end)

      user ->
        # If user exists but is not admin, promote them
        if user.role != :admin do
          user
          |> User.admin_changeset(%{role: :admin})
          |> Repo.update!()
          |> then(fn updated_user ->
            IO.puts("✓ User #{updated_user.email} promoted to admin")
          end)
        else
          IO.puts("✓ Admin user already exists: #{user.email}")
        end
    end
  end

  @doc """
  Run migrations and bootstrap in one command.

  This is the recommended way to initialize the application in production.
  """
  def migrate_and_bootstrap do
    migrate()
    bootstrap()
  end

  # Private helpers

  defp load_app do
    Application.load(@app)
  end

  defp start_repo do
    IO.puts("Starting Repo...")
    {:ok, _} = Application.ensure_all_started(:ssl)

    for repo <- repos() do
      {:ok, _} = repo.start_link(pool_size: 2)
    end
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end
end
