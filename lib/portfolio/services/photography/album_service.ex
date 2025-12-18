defmodule Portfolio.Services.Photography.AlbumService do
  @moduledoc """
  Service responsable des opérations CRUD sur les albums.

  Ce service encapsule la logique métier liée aux albums :
  - Création, lecture, mise à jour
  - Comptages et statistiques
  - Requêtes par année pour les albums publiés
  - Liste des types d'albums disponibles

  Ce service NE gère PAS :
  - Le cache (voir AlbumCacheService)
  - La publication (voir AlbumPublicationService)
  - La suppression (voir AlbumDeletionService)
  """

  alias Portfolio.Photography.Album
  alias Portfolio.Photography.Repositories.{AlbumRepository, PhotoRepository}

  @typedoc "Types d'albums disponibles dans l'application"
  @type album_type ::
          :couples
          | :wedding
          | :motherhood
          | :events
          | :landscape
          | :street
          | :music
          | :reenactment
          | :amvcc
          | :china
          | :japan
          | :taiwan

  # =============================================================================
  # Query Operations
  # =============================================================================

  @doc """
  Liste tous les albums avec filtres optionnels.

  ## Options

  - `:type` - Filtre par type d'album
  - `:published` - Filtre par statut de publication
  - `:preload` - Associations à précharger

  ## Exemples

      iex> list_albums()
      [%Album{}, %Album{}]

      iex> list_albums(published: true)
      [%Album{published: true}]
  """
  @spec list_albums(keyword()) :: [Album.t()]
  def list_albums(opts \\ []), do: AlbumRepository.list(opts)

  @doc """
  Récupère un album par son ID.

  ## Exemples

      iex> get_album(id)
      {:ok, %Album{}}

      iex> get_album("invalid")
      {:error, :not_found}
  """
  @spec get_album(Ecto.UUID.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
  def get_album(id, opts \\ []), do: AlbumRepository.get(id, opts)

  @doc """
  Récupère un album par son slug.
  """
  @spec get_album_by_slug(String.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
  def get_album_by_slug(slug, opts \\ []), do: AlbumRepository.get_by_slug(slug, opts)

  @doc """
  Récupère un album par son ID, lève une exception si non trouvé.
  """
  @spec get_album!(Ecto.UUID.t(), keyword()) :: Album.t()
  def get_album!(id, opts \\ []), do: AlbumRepository.get!(id, opts)

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  @doc """
  Crée un nouvel album.

  Émet un événement telemetry `[:portfolio, :photography, :album, :created]` avec
  la durée et le résultat de l'opération.

  ## Exemples

      iex> create_album(%{title: "Mon Album", type: :wedding, date_prise_vue: ~D[2024-01-01]})
      {:ok, %Album{}}
  """
  @spec create_album(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def create_album(attrs) do
    with_telemetry([:album, :created], %{}, fn ->
      AlbumRepository.insert(attrs)
    end)
  end

  @doc """
  Met à jour un album existant.

  Note: N'invalide PAS le cache. C'est la responsabilité de l'appelant
  (contexte Photography) de gérer le cache.

  ## Exemples

      iex> update_album(album, %{title: "Nouveau titre"})
      {:ok, %Album{}}
  """
  @spec update_album(Album.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def update_album(album, attrs) do
    with_telemetry([:album, :updated], %{album_id: album.id}, fn ->
      AlbumRepository.update(album, attrs)
    end)
  end

  # =============================================================================
  # Statistics & Counting
  # =============================================================================

  @doc """
  Compte le nombre total d'albums.

  ## Exemples

      iex> count_all_albums()
      42
  """
  @spec count_all_albums() :: non_neg_integer()
  def count_all_albums, do: AlbumRepository.count_all()

  @doc """
  Compte le nombre d'albums publiés.

  ## Exemples

      iex> count_published_albums()
      25
  """
  @spec count_published_albums() :: non_neg_integer()
  def count_published_albums, do: AlbumRepository.count_published()

  @doc """
  Compte le nombre d'albums non publiés (brouillons).

  ## Exemples

      iex> count_draft_albums()
      17
  """
  @spec count_draft_albums() :: non_neg_integer()
  def count_draft_albums, do: AlbumRepository.count_draft()

  @doc """
  Retourne toutes les statistiques des albums en une seule requête SQL.

  Optimisé pour le dashboard admin - évite les requêtes multiples en consolidant
  tous les counts dans une seule requête avec des agrégations conditionnelles.

  ## Exemples

      iex> get_album_stats()
      %{total: 42, published: 25, draft: 17}
  """
  @spec get_album_stats() :: %{
          total: non_neg_integer(),
          published: non_neg_integer(),
          draft: non_neg_integer()
        }
  def get_album_stats, do: AlbumRepository.get_all_stats()

  # =============================================================================
  # Published Albums Queries
  # =============================================================================

  @doc """
  Liste les années ayant des albums publiés, triées par ordre décroissant.

  Utilise une requête SQL optimisée pour récupérer uniquement les années distinctes
  sans charger les albums complets. Idéal pour le lazy loading.

  ## Exemples

      iex> list_published_years()
      [2024, 2023, 2022, 2021]
  """
  @spec list_published_years() :: [integer()]
  def list_published_years, do: AlbumRepository.list_published_years()

  @doc """
  Liste les albums publiés pour une année spécifique.

  Optimisé pour le lazy loading : charge uniquement les albums d'une année donnée.

  ## Paramètres

  - `year` - L'année pour laquelle récupérer les albums (integer)
  - `opts` - Options
    - `:preload` - Associations à précharger (ex: [:photos])

  ## Exemples

      iex> list_published_for_year(2024)
      [%Album{}, %Album{}]

      iex> list_published_for_year(2024, preload: [:photos])
      [%Album{photos: [...]}, ...]
  """
  @spec list_published_for_year(integer(), keyword()) :: [Album.t()]
  def list_published_for_year(year, opts \\ []) when is_integer(year) do
    AlbumRepository.list_published_for_year(year, opts)
  end

  @doc """
  Récupère les albums publiés groupés par année depuis la DB.

  Utilisé par AlbumCacheService. N'utilise PAS de cache.

  ## Options

  - `:preload` - Associations à précharger

  ## Exemples

      iex> fetch_published_albums_by_year()
      %{2024 => [%Album{}], 2023 => [%Album{}]}
  """
  @spec fetch_published_albums_by_year(keyword()) :: %{integer() => [Album.t()]}
  def fetch_published_albums_by_year(opts \\ []) do
    AlbumRepository.list_published_by_year(opts)
  end

  # =============================================================================
  # Helper Functions
  # =============================================================================

  @doc """
  Retourne la liste des types d'albums disponibles.

  ## Exemples

      iex> list_album_types()
      [:couples, :wedding, :motherhood, ...]
  """
  @spec list_album_types() :: [album_type(), ...]
  def list_album_types do
    [
      :couples,
      :wedding,
      :motherhood,
      :events,
      :landscape,
      :street,
      :music,
      :reenactment,
      :amvcc,
      :china,
      :japan,
      :taiwan
    ]
  end

  @doc """
  Compte le nombre de photos dans un album.

  ## Exemples

      iex> count_photos_in_album(album_id)
      42
  """
  @spec count_photos_in_album(Ecto.UUID.t()) :: non_neg_integer()
  def count_photos_in_album(album_id), do: PhotoRepository.count_by_album(album_id)

  # =============================================================================
  # Private Telemetry Helper
  # =============================================================================

  defp with_telemetry(event_name, metadata, fun) when is_list(event_name) and is_map(metadata) do
    start_time = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start_time

    metrics = %{duration: duration}
    full_metadata = Map.merge(metadata, result_metadata(result))

    :telemetry.execute([:portfolio, :photography | event_name], metrics, full_metadata)
    result
  end

  defp result_metadata({:ok, _}), do: %{result: :ok}
  defp result_metadata({:error, _}), do: %{result: :error}
end
