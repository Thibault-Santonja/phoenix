defmodule Portfolio.Photography.Repositories.AlbumRepository do
  @moduledoc """
  Repository pour la gestion de la persistence des Albums.

  Implémente le pattern Repository pour abstraire l'accès aux données des Albums.
  Toutes les opérations de base de données pour les Albums passent par ce module.

  ## Responsabilités

  - CRUD complet sur les Albums
  - Requêtes métier (filtres, groupements)
  - Gestion des erreurs de persistence
  - Isolation de la couche domaine vis-à-vis d'Ecto

  ## Exemples

      iex> AlbumRepository.list()
      [%Album{}, %Album{}]

      iex> AlbumRepository.get(album_id)
      {:ok, %Album{}}

      iex> AlbumRepository.get("invalid-id")
      {:error, :not_found}

  """

  import Ecto.Query, warn: false

  alias Portfolio.Photography.Album
  alias Portfolio.Repo

  @doc """
  Liste tous les albums avec filtres optionnels.

  ## Filtres disponibles

  - `:type` - Filtre par type d'album (atom)
  - `:published` - Filtre par statut de publication (boolean)
  - `:preload` - Liste des associations à précharger (liste d'atoms)

  ## Exemples

      iex> list()
      [%Album{}, %Album{}]

      iex> list(type: :wedding)
      [%Album{type: :wedding}, %Album{type: :wedding}]

      iex> list(published: true)
      [%Album{published: true}]

      iex> list(preload: [:photos])
      [%Album{photos: [%Photo{}]}]

  """
  @spec list(keyword()) :: [Album.t()]
  def list(filters \\ []) do
    Album
    |> apply_filters(filters)
    |> apply_preload(filters[:preload])
    |> Repo.all()
  end

  @doc """
  Récupère un album par son ID.

  Retourne `{:ok, album}` si trouvé, `{:error, :not_found}` sinon.

  ## Exemples

      iex> get(album_id)
      {:ok, %Album{}}

      iex> get("invalid-id")
      {:error, :not_found}

  """
  @spec get(Ecto.UUID.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
  def get(id, opts \\ []) do
    query = from a in Album, where: a.id == ^id

    query
    |> apply_preload(opts[:preload])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      album -> {:ok, album}
    end
  end

  @doc """
  Récupère un album par son ID, lève une exception si non trouvé.

  ## Exemples

      iex> get!(album_id)
      %Album{}

      iex> get!("invalid-id")
      ** (Ecto.NoResultsError)

  """
  @spec get!(Ecto.UUID.t(), keyword()) :: Album.t()
  def get!(id, opts \\ []) do
    query = from a in Album, where: a.id == ^id

    query
    |> apply_preload(opts[:preload])
    |> Repo.one!()
  end

  @doc """
  Insère un nouvel album.

  ## Exemples

      iex> insert(%{title: "Mon Album", type: :wedding, date_prise_vue: ~D[2024-01-01]})
      {:ok, %Album{}}

      iex> insert(%{title: ""})
      {:error, %Ecto.Changeset{}}

  """
  @spec insert(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) do
    %Album{}
    |> Album.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Met à jour un album existant.

  ## Exemples

      iex> update(album, %{title: "Nouveau titre"})
      {:ok, %Album{}}

      iex> update(album, %{title: ""})
      {:error, %Ecto.Changeset{}}

  """
  @spec update(Album.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def update(%Album{} = album, attrs) do
    album
    |> Album.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Supprime un album.

  Les photos associées sont supprimées en cascade (ON DELETE CASCADE).

  ## Exemples

      iex> delete(album)
      {:ok, %Album{}}

      iex> delete(album_with_constraint)
      {:error, %Ecto.Changeset{}}

  """
  @spec delete(Album.t()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Album{} = album) do
    Repo.delete(album)
  end

  @doc """
  Liste les albums publiés groupés par année de prise de vue.

  Retourne une map avec les années comme clés et les listes d'albums comme valeurs.
  Les albums sont triés par date décroissante au sein de chaque année.

  ## Exemples

      iex> list_published_by_year()
      %{
        2024 => [%Album{date_prise_vue: ~D[2024-12-25]}, %Album{date_prise_vue: ~D[2024-06-15]}],
        2023 => [%Album{date_prise_vue: ~D[2023-09-10]}]
      }

  """
  @spec list_published_by_year(keyword()) :: %{integer() => [Album.t()]}
  def list_published_by_year(opts \\ []) do
    Album
    |> where([a], a.published == true)
    |> order_by([a], desc: a.date_prise_vue)
    |> apply_preload(opts[:preload])
    |> Repo.all()
    |> Enum.group_by(fn album ->
      album.date_prise_vue.year
    end)
  end

  # Applique les filtres à la query
  @spec apply_filters(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  defp apply_filters(query, []), do: query

  defp apply_filters(query, [{:type, type} | rest]) do
    query
    |> where([a], a.type == ^type)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:published, published} | rest]) do
    query
    |> where([a], a.published == ^published)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [_other | rest]) do
    apply_filters(query, rest)
  end

  # Applique les preloads à la query
  @spec apply_preload(Ecto.Query.t(), nil | atom() | [atom()]) :: Ecto.Query.t()
  defp apply_preload(query, nil), do: query
  defp apply_preload(query, []), do: query

  defp apply_preload(query, preloads) when is_list(preloads) do
    # Si :photos est dans les preloads, on le remplace par une query ordonnée
    if :photos in preloads do
      preloads_without_photos = Enum.reject(preloads, &(&1 == :photos))
      photos_query = from p in Portfolio.Photography.Photo, order_by: [asc: p.display_order]

      query
      |> preload(^preloads_without_photos)
      |> preload(photos: ^photos_query)
    else
      preload(query, ^preloads)
    end
  end

  defp apply_preload(query, preload) when is_atom(preload) do
    apply_preload(query, [preload])
  end
end
