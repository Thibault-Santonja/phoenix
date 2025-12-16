defmodule Portfolio.Auth.Repositories.SessionRepository do
  @moduledoc """
  Repository pour la gestion de la persistence des UserSessions.

  Implémente le pattern Repository pour abstraire l'accès aux données des UserSessions.
  Ce repository se concentre uniquement sur l'accès aux données et isole
  la couche domaine vis-à-vis d'Ecto.

  ## Responsabilités

  - CRUD sur les UserSessions
  - Requêtes de recherche (par token, par ID, par user)
  - Mise à jour de l'activité
  - Suppression des sessions expirées
  - Gestion des erreurs de persistence
  - Isolation de la couche domaine vis-à-vis d'Ecto

  ## Exemples

      iex> SessionRepository.get_by_token("abc123...")
      {:ok, %UserSession{}}

      iex> SessionRepository.update_activity(session)
      {:ok, %UserSession{last_activity_at: ~U[2024-01-15 10:00:00Z]}}

      iex> SessionRepository.delete_expired()
      {10, nil}
  """

  use Portfolio.Repo.RepositoryBase

  alias Portfolio.Auth.UserSession

  # =============================================================================
  # Query Functions
  # =============================================================================

  @doc """
  Récupère une session par son token.

  IMPORTANT: Le token doit être hashé avant d'appeler cette fonction.

  ## Options

  - `:preload` - Associations à précharger (ex: [:user])

  ## Exemples

      iex> hashed_token = UserSession.hash_token_value("raw_token")
      iex> get_by_token(hashed_token)
      {:ok, %UserSession{}}

      iex> get_by_token("invalid_hashed_token")
      {:error, :not_found}

      iex> get_by_token(hashed_token, preload: [:user])
      {:ok, %UserSession{user: %User{}}}
  """
  @spec get_by_token(String.t(), keyword()) :: {:ok, UserSession.t()} | {:error, :not_found}
  def get_by_token(hashed_token, opts \\ []) when is_binary(hashed_token) do
    from(s in UserSession, where: s.token == ^hashed_token)
    |> maybe_preload(opts[:preload])
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Récupère une session par son ID.

  ## Exemples

      iex> get("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %UserSession{}}

      iex> get("invalid-uuid")
      {:error, :not_found}
  """
  @spec get(Ecto.UUID.t()) :: {:ok, UserSession.t()} | {:error, :not_found}
  def get(id) do
    UserSession
    |> Repo.get(id)
    |> wrap_result()
  end

  @doc """
  Récupère une session par son ID, lève une exception si non trouvée.

  ## Exemples

      iex> get!("123e4567-e89b-12d3-a456-426614174000")
      %UserSession{}

      iex> get!("invalid-uuid")
      ** (Ecto.NoResultsError)
  """
  @spec get!(Ecto.UUID.t()) :: UserSession.t()
  def get!(id), do: Repo.get!(UserSession, id)

  @doc """
  Recharge le user d'une session depuis la base de données.

  ## Exemples

      iex> reload_user(session)
      %UserSession{user: %User{}}
  """
  @spec reload_user(UserSession.t()) :: UserSession.t()
  def reload_user(%UserSession{} = session) do
    Repo.preload(session, :user, force: true)
  end

  @doc """
  Liste toutes les sessions d'un utilisateur.

  ## Options

  - `:order_by` - Ordre de tri (défaut: [desc: :last_activity_at])
  - `:limit` - Nombre maximum de résultats

  ## Exemples

      iex> list_by_user(user_id)
      [%UserSession{}, %UserSession{}]

      iex> list_by_user(user_id, limit: 5)
      [%UserSession{}, ...]
  """
  @spec list_by_user(Ecto.UUID.t(), keyword()) :: [UserSession.t()]
  def list_by_user(user_id, opts \\ []) do
    order_by = Keyword.get(opts, :order_by, desc: :last_activity_at)
    limit = Keyword.get(opts, :limit)

    query =
      from s in UserSession,
        where: s.user_id == ^user_id,
        order_by: ^order_by

    query = if limit, do: limit(query, ^limit), else: query

    Repo.all(query)
  end

  # =============================================================================
  # Mutation Functions
  # =============================================================================

  @doc """
  Insère une nouvelle session.

  IMPORTANT: Le token doit être hashé via UserSession.changeset
  avant insertion en DB.

  ## Exemples

      iex> insert(%{user_id: user_id, token: "raw_token", last_activity_at: DateTime.utc_now()})
      {:ok, %UserSession{}}

      iex> insert(%{user_id: nil})
      {:error, %Ecto.Changeset{}}
  """
  @spec insert(map()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) do
    %UserSession{}
    |> UserSession.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Met à jour l'activité d'une session.

  ## Exemples

      iex> update_activity(session, DateTime.utc_now())
      {:ok, %UserSession{last_activity_at: ~U[2024-01-15 10:30:00Z]}}
  """
  @spec update_activity(UserSession.t(), DateTime.t()) ::
          {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def update_activity(%UserSession{} = session, timestamp) do
    session
    |> Ecto.Changeset.change(%{last_activity_at: timestamp})
    |> Repo.update()
  end

  @doc """
  Met à jour une session existante.

  ## Exemples

      iex> update(session, %{last_activity_at: DateTime.utc_now()})
      {:ok, %UserSession{}}
  """
  @spec update(UserSession.t(), map()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def update(%UserSession{} = session, attrs) do
    session
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  @doc """
  Supprime une session.

  ## Exemples

      iex> delete(session)
      {:ok, %UserSession{}}
  """
  @spec delete(UserSession.t()) :: {:ok, UserSession.t()} | {:error, Ecto.Changeset.t()}
  def delete(%UserSession{} = session) do
    Repo.delete(session)
  end

  @doc """
  Supprime toutes les sessions d'un utilisateur.

  ## Exemples

      iex> delete_all_for_user(user_id)
      {3, nil}  # 3 sessions supprimées
  """
  @spec delete_all_for_user(Ecto.UUID.t()) :: {integer(), nil}
  def delete_all_for_user(user_id) do
    from(s in UserSession, where: s.user_id == ^user_id)
    |> Repo.delete_all()
  end

  @doc """
  Supprime toutes les sessions d'un utilisateur sauf celle spécifiée.

  ## Exemples

      iex> delete_all_for_user_except(user_id, current_session_id)
      {2, nil}  # 2 autres sessions supprimées
  """
  @spec delete_all_for_user_except(Ecto.UUID.t(), Ecto.UUID.t()) :: {integer(), nil}
  def delete_all_for_user_except(user_id, current_session_id) do
    from(s in UserSession,
      where: s.user_id == ^user_id and s.id != ^current_session_id
    )
    |> Repo.delete_all()
  end

  @doc """
  Supprime toutes les sessions expirées.

  ## Paramètres

  - `expiry_seconds` - Nombre de secondes d'inactivité avant expiration

  ## Exemples

      iex> delete_expired(30 * 24 * 3600)  # 30 jours
      {10, nil}  # 10 sessions expirées supprimées
  """
  @spec delete_expired(integer()) :: {integer(), nil}
  def delete_expired(expiry_seconds) do
    expiry_date =
      DateTime.utc_now()
      |> DateTime.add(-expiry_seconds, :second)
      |> DateTime.truncate(:second)

    from(s in UserSession, where: s.last_activity_at < ^expiry_date)
    |> Repo.delete_all()
  end

  # =============================================================================
  # Statistics Functions
  # =============================================================================

  @doc """
  Compte le nombre de sessions actives.

  ## Exemples

      iex> count_active(30 * 24 * 3600)  # 30 jours
      42
  """
  @spec count_active(integer()) :: non_neg_integer()
  def count_active(expiry_seconds) do
    expiry_date =
      DateTime.utc_now()
      |> DateTime.add(-expiry_seconds, :second)
      |> DateTime.truncate(:second)

    from(s in UserSession, where: s.last_activity_at >= ^expiry_date)
    |> Repo.aggregate(:count)
  end

  @doc """
  Compte le nombre total de sessions.

  ## Exemples

      iex> count()
      100
  """
  @spec count() :: non_neg_integer()
  def count do
    Repo.aggregate(UserSession, :count)
  end

  @doc """
  Compte le nombre de sessions pour un utilisateur.

  ## Exemples

      iex> count_for_user(user_id)
      3
  """
  @spec count_for_user(Ecto.UUID.t()) :: non_neg_integer()
  def count_for_user(user_id) do
    from(s in UserSession, where: s.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end
end
