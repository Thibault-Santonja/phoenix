defmodule Portfolio.Auth.Repositories.MagicLinkRepository do
  @moduledoc """
  Repository pour la gestion de la persistence des MagicLinks.

  Implémente le pattern Repository pour abstraire l'accès aux données des MagicLinks.
  Ce repository se concentre uniquement sur l'accès aux données et isole
  la couche domaine vis-à-vis d'Ecto.

  ## Responsabilités

  - CRUD sur les MagicLinks
  - Requêtes de recherche (par token, par short_code, par user)
  - Marquage comme utilisé
  - Suppression des liens expirés
  - Gestion des erreurs de persistence
  - Isolation de la couche domaine vis-à-vis d'Ecto

  ## Exemples

      iex> MagicLinkRepository.get_by_token("abc123...")
      {:ok, %MagicLink{}}

      iex> MagicLinkRepository.mark_as_used(magic_link)
      {:ok, %MagicLink{used_at: ~U[2024-01-15 10:00:00Z]}}

      iex> MagicLinkRepository.delete_expired()
      {5, nil}
  """

  # warn: false suppresses unused import warnings - query macros are used dynamically
  import Ecto.Query, warn: false
  import Portfolio.Repo.QueryHelpers

  alias Portfolio.Auth.MagicLink
  alias Portfolio.Repo

  # =============================================================================
  # Query Functions
  # =============================================================================

  @doc """
  Récupère un magic link par son token.

  ## Options

  - `:preload` - Associations à précharger (ex: [:user])

  ## Exemples

      iex> get_by_token("valid_token")
      {:ok, %MagicLink{}}

      iex> get_by_token("invalid_token")
      {:error, :not_found}

      iex> get_by_token("valid_token", preload: [:user])
      {:ok, %MagicLink{user: %User{}}}
  """
  @spec get_by_token(String.t(), keyword()) :: {:ok, MagicLink.t()} | {:error, :not_found}
  def get_by_token(token, opts \\ []) when is_binary(token) do
    from(ml in MagicLink, where: ml.token == ^token)
    |> maybe_preload(opts[:preload])
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Récupère un magic link par son code court (short_code).

  ## Options

  - `:preload` - Associations à précharger (ex: [:user])

  ## Exemples

      iex> get_by_short_code("ABC123")
      {:ok, %MagicLink{short_code: "ABC123"}}

      iex> get_by_short_code("INVALID")
      {:error, :not_found}

      iex> get_by_short_code("ABC123", preload: [:user])
      {:ok, %MagicLink{user: %User{}}}
  """
  @spec get_by_short_code(String.t(), keyword()) :: {:ok, MagicLink.t()} | {:error, :not_found}
  def get_by_short_code(short_code, opts \\ []) when is_binary(short_code) do
    from(ml in MagicLink, where: ml.short_code == ^short_code)
    |> maybe_preload(opts[:preload])
    |> Repo.one()
    |> wrap_result()
  end

  @doc """
  Liste les magic links d'un utilisateur.

  ## Options

  - `:limit` - Nombre maximum de résultats (défaut: 100)
  - `:order_by` - Ordre de tri (défaut: [desc: :inserted_at])

  ## Exemples

      iex> list_by_user(user_id)
      [%MagicLink{}, %MagicLink{}]

      iex> list_by_user(user_id, limit: 5)
      [%MagicLink{}, ...]
  """
  @spec list_by_user(Ecto.UUID.t(), keyword()) :: [MagicLink.t()]
  def list_by_user(user_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    order_by = Keyword.get(opts, :order_by, desc: :inserted_at)

    from(ml in MagicLink, where: ml.user_id == ^user_id, order_by: ^order_by)
    |> limit(^limit)
    |> Repo.all()
  end

  # =============================================================================
  # Mutation Functions
  # =============================================================================

  @doc """
  Insère un nouveau magic link.

  ## Exemples

      iex> insert(%{user_id: user_id, token: "abc123...", expires_at: expires_at})
      {:ok, %MagicLink{}}

      iex> insert(%{user_id: nil})
      {:error, %Ecto.Changeset{}}
  """
  @spec insert(map()) :: {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) when is_map(attrs) do
    %MagicLink{}
    |> MagicLink.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Marque un magic link comme utilisé.

  Met à jour le champ `used_at` avec l'horodatage actuel.

  ## Exemples

      iex> mark_as_used(magic_link)
      {:ok, %MagicLink{used_at: ~U[2024-01-15 10:00:00Z]}}
  """
  @spec mark_as_used(MagicLink.t()) :: {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t()}
  def mark_as_used(%MagicLink{} = magic_link) do
    magic_link
    |> Ecto.Changeset.change(%{
      used_at: DateTime.utc_now() |> DateTime.truncate(:second)
    })
    |> Repo.update()
  end

  @doc """
  Met à jour un magic link existant.

  ## Exemples

      iex> update(magic_link, %{used_at: DateTime.utc_now()})
      {:ok, %MagicLink{}}
  """
  @spec update(MagicLink.t(), map()) :: {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t()}
  def update(%MagicLink{} = magic_link, attrs) do
    magic_link
    |> Ecto.Changeset.change(attrs)
    |> Repo.update()
  end

  @doc """
  Supprime un magic link.

  ## Exemples

      iex> delete(magic_link)
      {:ok, %MagicLink{}}
  """
  @spec delete(MagicLink.t()) :: {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t()}
  def delete(%MagicLink{} = magic_link) do
    Repo.delete(magic_link)
  end

  @doc """
  Supprime tous les magic links expirés.

  Retourne le nombre de magic links supprimés.

  ## Exemples

      iex> delete_expired()
      {5, nil}  # 5 magic links expirés supprimés
  """
  @spec delete_expired() :: {integer(), nil}
  def delete_expired do
    now = DateTime.utc_now()

    from(ml in MagicLink, where: ml.expires_at < ^now)
    |> Repo.delete_all()
  end

  @doc """
  Supprime tous les magic links d'un utilisateur.

  ## Exemples

      iex> delete_all_for_user(user_id)
      {3, nil}  # 3 magic links supprimés
  """
  @spec delete_all_for_user(Ecto.UUID.t()) :: {integer(), nil}
  def delete_all_for_user(user_id) do
    from(ml in MagicLink, where: ml.user_id == ^user_id)
    |> Repo.delete_all()
  end

  # =============================================================================
  # Statistics Functions
  # =============================================================================

  @doc """
  Compte le nombre de magic links actifs (non utilisés et non expirés).

  ## Exemples

      iex> count_active()
      12
  """
  @spec count_active() :: non_neg_integer()
  def count_active do
    now = DateTime.utc_now()

    from(ml in MagicLink,
      where: is_nil(ml.used_at) and ml.expires_at > ^now
    )
    |> Repo.aggregate(:count)
  end

  @doc """
  Compte le nombre de magic links pour un utilisateur.

  ## Exemples

      iex> count_for_user(user_id)
      3
  """
  @spec count_for_user(Ecto.UUID.t()) :: non_neg_integer()
  def count_for_user(user_id) do
    from(ml in MagicLink, where: ml.user_id == ^user_id)
    |> Repo.aggregate(:count)
  end
end
