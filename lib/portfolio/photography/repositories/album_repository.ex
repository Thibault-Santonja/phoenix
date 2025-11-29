defmodule Portfolio.Photography.Repositories.AlbumRepository do
  @moduledoc """
  Repository pour la gestion de la persistence des Albums.

  Implémente le pattern Repository pour abstraire l'accès aux données des Albums.
  Toutes les opérations de base de données pour les Albums passent par ce module.

  La logique de construction des requêtes est déléguée aux Query Objects,
  ce repository se concentre uniquement sur l'accès aux données.

  ## Responsabilités

  - CRUD complet sur les Albums
  - Exécution des requêtes construites par AlbumQuery
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

  # warn: false suppresses unused import warnings - query macros are used dynamically
  import Ecto.Query, warn: false

  alias Portfolio.Photography.Album
  alias Portfolio.Photography.Queries.AlbumQuery
  alias Portfolio.Repo

  @doc """
  Liste tous les albums avec filtres optionnels.

  ## Filtres disponibles

  - `:type` - Filtre par type d'album (atom)
  - `:published` - Filtre par statut de publication (boolean)
  - `:preload` - Liste des associations à précharger (liste d'atoms)
  - `:with_photo_count` - Ajoute un champ virtuel `photo_count` au lieu de précharger toutes les photos (boolean)
  - `:limit` - Nombre maximum de résultats (integer)
  - `:offset` - Nombre de résultats à sauter (integer)

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
    AlbumQuery.base()
    |> apply_filters(filters)
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
    case fetch_one(:id, id, opts) do
      nil -> {:error, :not_found}
      album -> {:ok, album}
    end
  end

  @doc """
  Récupère un album par son slug.

  ## Exemples

      iex> get_by_slug("wedding-2024")
      {:ok, %Album{slug: "wedding-2024"}}

      iex> get_by_slug("nonexistent")
      {:error, :not_found}

  """
  @spec get_by_slug(String.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
  def get_by_slug(slug, opts \\ []) do
    case fetch_one(:slug, slug, opts) do
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
    build_get_query(:id, id)
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
  Liste les années ayant des albums publiés, triées par ordre décroissant.

  Utilise une requête SQL optimisée avec EXTRACT(YEAR) pour obtenir uniquement
  les années distinctes sans charger les albums complets.

  Cette fonction est optimale pour le lazy loading : elle permet d'afficher
  rapidement la liste des années disponibles, puis de charger les albums
  d'une année spécifique à la demande avec `list_published_for_year/2`.

  ## Exemples

      iex> list_published_years()
      [2024, 2023, 2022, 2021]

  """
  @spec list_published_years() :: [integer()]
  def list_published_years do
    from(a in Album,
      where: a.published == true,
      select: fragment("CAST(EXTRACT(YEAR FROM ?) AS INTEGER)", a.date_prise_vue),
      distinct: true,
      order_by: [desc: fragment("CAST(EXTRACT(YEAR FROM ?) AS INTEGER)", a.date_prise_vue)]
    )
    |> Repo.all()
  end

  @doc """
  Liste les albums publiés pour une année spécifique.

  Optimisé pour le lazy loading : charge uniquement les albums d'une année
  donnée au lieu de tous les albums. Combine avec `list_published_years/0`
  pour un chargement efficace par année.

  ## Paramètres

  - `year` - L'année pour laquelle récupérer les albums (integer, 1..9999)
  - `opts` - Options
    - `:preload` - Associations à précharger (ex: [:photos])

  ## Exemples

      iex> list_published_for_year(2024)
      [%Album{date_prise_vue: ~D[2024-12-25]}, %Album{date_prise_vue: ~D[2024-06-15]}]

      iex> list_published_for_year(2024, preload: [:photos])
      [%Album{photos: [%Photo{}, ...]}, ...]

  """
  @spec list_published_for_year(integer(), keyword()) :: [Album.t()]
  def list_published_for_year(year, opts \\ [])
      when is_integer(year) and year >= 1 and year <= 9999 do
    {:ok, start_date} = Date.new(year, 1, 1)
    {:ok, end_date} = Date.new(year, 12, 31)

    query =
      AlbumQuery.base()
      |> AlbumQuery.published()
      |> AlbumQuery.where_date_between(start_date, end_date)
      |> AlbumQuery.order_by_date_desc()

    query =
      if opts[:preload] do
        apply_preload(query, opts[:preload])
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Liste les albums publiés groupés par année de prise de vue.

  Retourne une map avec les années comme clés et les listes d'albums comme valeurs.
  Les albums sont triés par date décroissante au sein de chaque année.

  **Note:** Pour de meilleures performances avec de grands datasets, préférez
  utiliser `list_published_years/0` + `list_published_for_year/2` qui permettent
  un lazy loading plus efficace.

  ## Exemples

      iex> list_published_by_year()
      %{
        2024 => [%Album{date_prise_vue: ~D[2024-12-25]}, %Album{date_prise_vue: ~D[2024-06-15]}],
        2023 => [%Album{date_prise_vue: ~D[2023-09-10]}]
      }

  """
  @spec list_published_by_year(keyword()) :: %{integer() => [Album.t()]}
  def list_published_by_year(opts \\ []) do
    query =
      AlbumQuery.base()
      |> AlbumQuery.published()
      |> AlbumQuery.order_by_date_desc()

    query =
      if opts[:preload] do
        apply_preload(query, opts[:preload])
      else
        query
      end

    query
    |> Repo.all()
    |> Enum.group_by(fn album ->
      album.date_prise_vue.year
    end)
  end

  # Construction de requête pour get/get_by_slug
  @spec build_get_query(:id | :slug, term()) :: Ecto.Query.t()
  defp build_get_query(:id, id), do: from(a in Album, where: a.id == ^id)
  defp build_get_query(:slug, slug), do: from(a in Album, where: a.slug == ^slug)

  # Récupère un album avec preload optionnel (retourne nil si non trouvé)
  @spec fetch_one(:id | :slug, term(), keyword()) :: Album.t() | nil
  defp fetch_one(field, value, opts) do
    build_get_query(field, value)
    |> apply_preload(opts[:preload])
    |> Repo.one()
  end

  # Applique les filtres à la query en utilisant AlbumQuery
  @spec apply_filters(Ecto.Query.t(), keyword()) :: Ecto.Query.t()
  defp apply_filters(query, []), do: query

  defp apply_filters(query, [{:type, type} | rest]) do
    query
    |> AlbumQuery.by_type(type)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:published, true} | rest]) do
    query
    |> AlbumQuery.published()
    |> AlbumQuery.order_by_date_desc()
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:published, false} | rest]) do
    query
    |> AlbumQuery.unpublished()
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:preload, preloads} | rest]) do
    query
    |> apply_preload(preloads)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:with_photo_count, true} | rest]) do
    query
    |> AlbumQuery.with_photo_count()
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:limit, limit} | rest]) when is_integer(limit) do
    query
    |> limit(^limit)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:offset, offset} | rest]) when is_integer(offset) do
    query
    |> offset(^offset)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:order_by, order_spec} | rest]) when is_list(order_spec) do
    query
    |> order_by(^order_spec)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [_other | rest]) do
    apply_filters(query, rest)
  end

  @doc """
  Counts albums with optional filters.

  ## Options

  - `:published` - Filter by publication status (boolean)

  ## Examples

      iex> count()
      42

      iex> count(published: true)
      25

      iex> count(published: false)
      17
  """
  @spec count(keyword()) :: non_neg_integer()
  def count(opts \\ []) do
    query = Album

    query =
      case Keyword.get(opts, :published) do
        true -> where(query, [a], a.published == true)
        false -> where(query, [a], a.published == false)
        nil -> query
      end

    Repo.aggregate(query, :count)
  end

  @doc """
  Compte le nombre total d'albums.

  ## Exemples

      iex> count_all()
      42
  """
  @spec count_all() :: non_neg_integer()
  def count_all do
    Repo.aggregate(Album, :count)
  end

  @doc """
  Compte le nombre d'albums publiés.

  ## Exemples

      iex> count_published()
      25
  """
  @spec count_published() :: non_neg_integer()
  def count_published do
    from(a in Album, where: a.published == true)
    |> Repo.aggregate(:count)
  end

  @doc """
  Compte le nombre d'albums non publiés (brouillons).

  ## Exemples

      iex> count_draft()
      17
  """
  @spec count_draft() :: non_neg_integer()
  def count_draft do
    from(a in Album, where: a.published == false)
    |> Repo.aggregate(:count)
  end

  # Applique les preloads à la query en utilisant AlbumQuery
  @spec apply_preload(Ecto.Query.t(), nil | atom() | [atom()]) :: Ecto.Query.t()
  defp apply_preload(query, nil), do: query
  defp apply_preload(query, []), do: query

  defp apply_preload(query, preloads) do
    AlbumQuery.with_preload(query, preloads)
  end
end
