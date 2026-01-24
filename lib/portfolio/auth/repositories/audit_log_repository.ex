defmodule Portfolio.Auth.Repositories.AuditLogRepository do
  @moduledoc """
  Repository pour la gestion de la persistence des AuditLogs.

  Implémente le pattern Repository pour abstraire l'accès aux données des AuditLogs.
  Ce repository se concentre uniquement sur l'accès aux données et isole
  la couche domaine vis-à-vis d'Ecto.

  ## Responsabilités

  - Insertion des logs d'audit (insert-only, pas de update/delete)
  - Requêtes de recherche (par resource, par user)
  - Isolation de la couche domaine vis-à-vis d'Ecto

  ## Exemples

      iex> AuditLogRepository.insert(%{action: :user_role_changed, ...})
      {:ok, %AuditLog{}}

      iex> AuditLogRepository.get_by_resource("User", user_id)
      [%AuditLog{}, ...]
  """

  import Ecto.Query, warn: false

  alias Portfolio.Auth.AuditLog
  alias Portfolio.Repo

  # =============================================================================
  # Insert Functions
  # =============================================================================

  @doc """
  Insère un nouveau log d'audit.

  Les logs d'audit sont insert-only (jamais modifiés ni supprimés).

  ## Exemples

      iex> insert(%{action: :user_role_changed, resource_type: "User", resource_id: id})
      {:ok, %AuditLog{}}
  """
  @spec insert(map()) :: {:ok, AuditLog.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) when is_map(attrs) do
    %AuditLog{}
    |> AuditLog.changeset(attrs)
    |> Repo.insert()
  end

  # =============================================================================
  # Query Functions
  # =============================================================================

  @doc """
  Récupère les logs d'audit pour une ressource donnée.

  ## Options

  - `:limit` - Nombre maximum de logs à retourner (défaut: 50)

  ## Exemples

      iex> get_by_resource("User", user_id)
      [%AuditLog{}, ...]

      iex> get_by_resource("User", user_id, limit: 10)
      [%AuditLog{}, ...]
  """
  @spec get_by_resource(String.t(), Ecto.UUID.t(), Keyword.t()) :: [AuditLog.t()]
  def get_by_resource(resource_type, resource_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(log in AuditLog,
      where: log.resource_type == ^resource_type and log.resource_id == ^resource_id,
      order_by: [desc: log.inserted_at],
      limit: ^limit,
      preload: [:performed_by]
    )
    |> Repo.all()
  end

  @doc """
  Récupère les logs d'audit effectués par un utilisateur donné.

  ## Options

  - `:limit` - Nombre maximum de logs à retourner (défaut: 50)

  ## Exemples

      iex> get_by_performer(admin_id)
      [%AuditLog{}, ...]
  """
  @spec get_by_performer(Ecto.UUID.t(), Keyword.t()) :: [AuditLog.t()]
  def get_by_performer(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    from(log in AuditLog,
      where: log.performed_by_id == ^user_id,
      order_by: [desc: log.inserted_at],
      limit: ^limit,
      preload: [:performed_by]
    )
    |> Repo.all()
  end
end
