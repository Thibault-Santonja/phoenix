defmodule Portfolio.Bootstrap do
  @moduledoc """
  Contexte responsable du bootstrap de l'application.

  Ce contexte orchestre l'initialisation automatique de l'application,
  notamment la création de l'utilisateur admin initial.

  ## Responsabilités

  - Démarrage du worker de bootstrap via `Portfolio.Bootstrap.Worker`
  - Logique métier de création/promotion de l'admin
  - Configuration centralisée du bootstrap

  ## Configuration

  Le bootstrap est configurable via `config/config.exs` :

      config :portfolio, Portfolio.Bootstrap,
        max_retries: 20,                    # Nombre de tentatives max
        retry_interval_ms: 30_000,          # 30 secondes entre chaque retry
        admin_email: "admin@example.com"    # Email de l'admin initial

  ## Utilisation

  Le bootstrap s'exécute automatiquement au démarrage de l'application.
  Il n'y a généralement rien à faire manuellement.

  ### En développement

      mix phx.server
      # Logs: [info] ✓ Admin user bootstrap completed successfully

  ### En production

      export ADMIN_EMAIL=admin@votredomaine.com
      /app/bin/portfolio start
      # Le bootstrap est automatique

  ## Sécurité

  Le bootstrap utilise `Portfolio.Auth.User.bootstrap_admin_changeset/2` qui est
  le seul moyen de créer un utilisateur avec le rôle :admin sans intervention manuelle.

  Ce changeset n'est utilisé que dans ce contexte et dans les seeds.
  """

  alias Portfolio.Auth.User
  alias Portfolio.Repo

  require Logger

  @doc """
  Exécute le bootstrap de l'admin initial.

  ## Options

  - `:admin_email` - Email de l'admin à créer/promouvoir

  ## Retour

  - `:ok` - Bootstrap réussi
  - `{:error, :repo_not_ready}` - La base de données n'est pas prête
  - `{:error, reason}` - Erreur inattendue

  ## Exemples

      iex> Bootstrap.run(admin_email: "admin@example.com")
      :ok
  """
  @spec run(keyword()) :: :ok | {:error, term()}
  def run(opts \\ []) do
    admin_email = Keyword.get(opts, :admin_email, config(:admin_email))

    if repo_ready?() do
      case Repo.get_by(User, email: admin_email) do
        nil ->
          create_admin(admin_email)

        user ->
          ensure_admin_role(user)
      end

      :ok
    else
      {:error, :repo_not_ready}
    end
  rescue
    error ->
      {:error, error}
  end

  @doc """
  Vérifie si le Repo est prêt.

  ## Exemples

      iex> Bootstrap.repo_ready?()
      true
  """
  @spec repo_ready?() :: boolean()
  def repo_ready? do
    Repo.query("SELECT 1")
    true
  rescue
    _ -> false
  end

  @doc """
  Récupère une valeur de configuration pour le bootstrap.

  ## Exemples

      iex> Bootstrap.config(:max_retries)
      20

      iex> Bootstrap.config(:admin_email)
      "thibault.santonja@pm.me"
  """
  @spec config(atom()) :: term()
  def config(:admin_email) do
    # L'email admin est lu depuis ENV au runtime
    System.get_env("ADMIN_EMAIL") || "thibault.santonja@pm.me"
  end

  def config(key) do
    Application.get_env(:portfolio, __MODULE__, [])
    |> Keyword.get(key)
  end

  # Private functions

  defp create_admin(email) do
    %User{}
    |> User.bootstrap_admin_changeset(%{
      email: email,
      name: extract_name_from_email(email),
      role: :admin
    })
    |> Repo.insert!()
    |> then(fn user ->
      Logger.info("✓ Admin user created: #{user.email}")
    end)
  end

  defp ensure_admin_role(user) do
    if user.role != :admin do
      user
      |> User.admin_changeset(%{role: :admin})
      |> Repo.update!()
      |> then(fn updated_user ->
        Logger.info("✓ User #{updated_user.email} promoted to admin")
      end)
    else
      Logger.debug("✓ Admin user already exists: #{user.email}")
    end
  end

  # Extrait un nom depuis l'email pour l'affichage
  # "thibault.santonja@pm.me" -> "Thibault Santonja"
  defp extract_name_from_email(email) do
    email
    |> String.split("@")
    |> List.first()
    |> String.split(".")
    |> Enum.map(&String.capitalize/1)
    |> Enum.join(" ")
  end
end
