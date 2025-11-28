defmodule Portfolio.Auth.Repositories.UserRepository do
  @moduledoc """
  Repository pour la gestion de la persistence des Users.

  Implémente le pattern Repository pour abstraire l'accès aux données des Users.
  Ce repository se concentre uniquement sur l'accès aux données et isole
  la couche domaine vis-à-vis d'Ecto.

  ## Responsabilités

  - CRUD complet sur les Users
  - Requêtes de recherche (par email, par ID)
  - Comptage et statistiques
  - Gestion des erreurs de persistence
  - Isolation de la couche domaine vis-à-vis d'Ecto

  ## Exemples

      iex> UserRepository.get_by_email("admin@example.com")
      {:ok, %User{}}

      iex> UserRepository.insert(%{email: "new@example.com"})
      {:ok, %User{}}

      iex> UserRepository.count_admins()
      2
  """

  import Ecto.Query, warn: false

  alias Portfolio.Auth.User
  alias Portfolio.Repo

  # =============================================================================
  # Query Functions
  # =============================================================================

  @doc """
  Récupère un utilisateur par son email.

  ## Exemples

      iex> get_by_email("admin@example.com")
      {:ok, %User{}}

      iex> get_by_email("unknown@example.com")
      {:error, :not_found}
  """
  @spec get_by_email(String.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get_by_email(email) when is_binary(email) do
    case Repo.get_by(User, email: email) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Récupère un utilisateur par son ID.

  ## Exemples

      iex> get("123e4567-e89b-12d3-a456-426614174000")
      {:ok, %User{}}

      iex> get("invalid-uuid")
      {:error, :not_found}
  """
  @spec get(Ecto.UUID.t()) :: {:ok, User.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(User, id) do
      nil -> {:error, :not_found}
      user -> {:ok, user}
    end
  end

  @doc """
  Récupère un utilisateur par son ID, lève une exception si non trouvé.

  ## Exemples

      iex> get!("123e4567-e89b-12d3-a456-426614174000")
      %User{}

      iex> get!("invalid-uuid")
      ** (Ecto.NoResultsError)
  """
  @spec get!(Ecto.UUID.t()) :: User.t()
  def get!(id), do: Repo.get!(User, id)

  @doc """
  Liste tous les utilisateurs avec filtres optionnels.

  ## Options

  - `:role` - Filtre par rôle (`:admin` ou `:user`)
  - `:preload` - Associations à précharger

  ## Exemples

      iex> list()
      [%User{}, %User{}]

      iex> list(role: :admin)
      [%User{role: :admin}]
  """
  @spec list(keyword()) :: [User.t()]
  def list(opts \\ []) do
    from(u in User)
    |> apply_filters(opts)
    |> Repo.all()
  end

  # =============================================================================
  # Mutation Functions
  # =============================================================================

  @doc """
  Insère un nouvel utilisateur.

  ## Exemples

      iex> insert(%{email: "new@example.com"})
      {:ok, %User{}}

      iex> insert(%{email: nil})
      {:error, %Ecto.Changeset{}}
  """
  @spec insert(map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) do
    %User{}
    |> User.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Met à jour le profil d'un utilisateur.

  Utilise le changeset de profil (name uniquement).

  ## Exemples

      iex> update_profile(user, %{name: "New Name"})
      {:ok, %User{}}

      iex> update_profile(user, %{name: ""})
      {:error, %Ecto.Changeset{}}
  """
  @spec update_profile(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_profile(%User{} = user, attrs) do
    user
    |> User.profile_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Met à jour un utilisateur via l'interface admin.

  Permet de modifier le rôle et le nom de l'utilisateur.

  ## Options

  - `:current_user_id` - ID de l'admin courant (pour protection PU-006)

  ## Exemples

      iex> update_as_admin(user, %{role: :user}, current_user_id: admin.id)
      {:ok, %User{}}

      iex> update_as_admin(user, %{role: :admin}, current_user_id: user.id)
      {:error, %Ecto.Changeset{}}
  """
  @spec update_as_admin(User.t(), map(), keyword()) ::
          {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def update_as_admin(%User{} = user, attrs, opts \\ []) do
    user
    |> User.admin_changeset(attrs, opts)
    |> Repo.update()
  end

  @doc """
  Supprime un utilisateur.

  IMPORTANT: La règle métier PU-006 (protection du dernier admin)
  doit être vérifiée AVANT d'appeler cette fonction.

  ## Exemples

      iex> delete(user)
      {:ok, %User{}}
  """
  @spec delete(User.t()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}
  def delete(%User{} = user) do
    Repo.delete(user)
  end

  # =============================================================================
  # Statistics Functions
  # =============================================================================

  @doc """
  Compte le nombre total d'utilisateurs.

  ## Exemples

      iex> count()
      5
  """
  @spec count() :: non_neg_integer()
  def count do
    Repo.aggregate(User, :count)
  end

  @doc """
  Compte le nombre d'administrateurs.

  ## Exemples

      iex> count_admins()
      2
  """
  @spec count_admins() :: non_neg_integer()
  def count_admins do
    from(u in User, where: u.role == :admin)
    |> Repo.aggregate(:count)
  end

  @doc """
  Compte le nombre d'utilisateurs réguliers.

  ## Exemples

      iex> count_regular_users()
      3
  """
  @spec count_regular_users() :: non_neg_integer()
  def count_regular_users do
    from(u in User, where: u.role == :user)
    |> Repo.aggregate(:count)
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  # Applique les filtres à la query
  @spec apply_filters(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  defp apply_filters(query, []), do: query

  defp apply_filters(query, [{:role, role} | rest]) when is_atom(role) do
    query
    |> where([u], u.role == ^role)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:preload, preloads} | rest]) do
    query
    |> preload(^preloads)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [_other | rest]) do
    apply_filters(query, rest)
  end
end
