defmodule Portfolio.Photography do
  @moduledoc """
  Photography Bounded Context - Gestion des albums photo et médias du portfolio.

  Ce contexte encapsule toute la logique métier liée à la photographie :
  - Gestion des albums photo (création, édition, publication)
  - Gestion des photos (upload, organisation, métadonnées)
  - Organisation par types (couples, wedding, music, reenactment, etc.)

  ## Ubiquitous Language

  - **Album** : Collection cohérente de photos autour d'un événement photographique
  - **Photo** : Image individuelle membre d'un album
  - **Published** : État d'un album visible publiquement (vs brouillon)
  - **Cover Photo** : Photo représentative d'un album (utilisée dans la timeline)
  - **Display Order** : Ordre d'affichage des photos au sein d'un album
  - **Type** : Catégorie métier de l'album (couples, wedding, music, etc.)
  - **Slug** : Identifiant URL-friendly unique généré depuis le titre

  ## Architecture

  Ce context suit les principes DDD et Clean Architecture :

  - **Domain Layer** : Entités (Album, Photo), Services métier
  - **Application Layer** : Ce module (API publique, orchestration)
  - **Infrastructure Layer** : Repositories, Storage (LocalStorage)

  ## Services

  Ce module délègue aux services spécialisés :

  - **AlbumService** : Opérations CRUD sur les albums, statistiques, requêtes
  - **PhotoService** : Opérations CRUD sur les photos, processing, stockage
  - **AlbumCacheService** : Gestion du cache des albums publiés
  - **AlbumPublicationService** : Publication d'albums avec orchestration
  - **AlbumDeletionService** : Suppression atomique d'albums
  - **PhotoDeletionService** : Suppression atomique de photos
  - **PhotoUploadService** : Upload parallèle de photos

  ## Exemples

      # Lister tous les albums publiés groupés par année
      albums_by_year = Photography.list_published_albums_by_year()

      # Créer un nouvel album
      {:ok, album} = Photography.create_album(%{
        title: "Mariage de Claire & Damien",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        location: "Château de Coucy"
      })

      # Uploader des photos dans un album
      {:ok, photos} = Photography.upload_photos(album, uploads)

      # Publier un album
      {:ok, published_album} = Photography.publish_album(album)
  """

  alias Portfolio.Photography.{Album, Photo}

  # Service Layer
  alias Portfolio.Services.Photography.{
    AlbumCacheService,
    AlbumDeletionService,
    AlbumPublicationService,
    AlbumService,
    PhotoDeletionService,
    PhotoService,
    PhotoUploadService
  }

  # =============================================================================
  # Album API - Delegates to AlbumService
  # =============================================================================

  @doc """
  Liste tous les albums avec filtres optionnels.

  Délègue à `AlbumService.list_albums/1`.
  """
  @spec list_albums(keyword()) :: [Album.t()]
  defdelegate list_albums(opts \\ []), to: AlbumService

  @doc """
  Compte le nombre total d'albums.

  Délègue à `AlbumService.count_all_albums/0`.
  """
  @spec count_all_albums() :: non_neg_integer()
  defdelegate count_all_albums(), to: AlbumService

  @doc """
  Compte le nombre d'albums publiés.

  Délègue à `AlbumService.count_published_albums/0`.
  """
  @spec count_published_albums() :: non_neg_integer()
  defdelegate count_published_albums(), to: AlbumService

  @doc """
  Compte le nombre d'albums non publiés (brouillons).

  Délègue à `AlbumService.count_draft_albums/0`.
  """
  @spec count_draft_albums() :: non_neg_integer()
  defdelegate count_draft_albums(), to: AlbumService

  @doc """
  Retourne toutes les statistiques des albums en une seule requête SQL.

  Délègue à `AlbumService.get_album_stats/0`.
  """
  @spec get_album_stats() :: %{
          total: non_neg_integer(),
          published: non_neg_integer(),
          draft: non_neg_integer()
        }
  defdelegate get_album_stats(), to: AlbumService

  @doc """
  Récupère un album par son ID.

  Délègue à `AlbumService.get_album/2`.
  """
  @spec get_album(Ecto.UUID.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
  defdelegate get_album(id, opts \\ []), to: AlbumService

  @doc """
  Récupère un album par son slug.

  Délègue à `AlbumService.get_album_by_slug/2`.
  """
  @spec get_album_by_slug(String.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
  defdelegate get_album_by_slug(slug, opts \\ []), to: AlbumService

  @doc """
  Récupère un album par son ID, lève une exception si non trouvé.

  Délègue à `AlbumService.get_album!/2`.
  """
  @spec get_album!(Ecto.UUID.t(), keyword()) :: Album.t()
  defdelegate get_album!(id, opts \\ []), to: AlbumService

  @doc """
  Crée un nouvel album.

  Délègue à `AlbumService.create_album/1`.
  """
  @spec create_album(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_album(attrs), to: AlbumService

  @doc """
  Met à jour un album existant et invalide le cache si nécessaire.

  Orchestre la mise à jour via AlbumService et l'invalidation du cache
  via AlbumCacheService.
  """
  @spec update_album(Album.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def update_album(album, attrs) do
    case AlbumService.update_album(album, attrs) do
      {:ok, updated_album} = result ->
        if updated_album.published or album.published do
          AlbumCacheService.invalidate_cache()
        end

        result

      error ->
        error
    end
  end

  @doc """
  Supprime un album et toutes ses photos (CASCADE) de manière atomique.

  Délègue à `AlbumDeletionService.execute/1` et invalide le cache si nécessaire.
  """
  @spec delete_album(Album.t()) :: {:ok, map()} | {:error, Ecto.Multi.name(), term(), map()}
  def delete_album(%Album{} = album) do
    case AlbumDeletionService.execute(album) do
      {:ok, _result} = success ->
        if album.published do
          AlbumCacheService.invalidate_cache()
        end

        success

      error ->
        error
    end
  end

  @doc """
  Liste les années ayant des albums publiés, triées par ordre décroissant.

  Délègue à `AlbumService.list_published_years/0`.
  """
  @spec list_published_years() :: [integer()]
  defdelegate list_published_years(), to: AlbumService

  @doc """
  Liste les albums publiés pour une année spécifique.

  Délègue à `AlbumService.list_published_for_year/2`.
  """
  @spec list_published_for_year(integer(), keyword()) :: [Album.t()]
  defdelegate list_published_for_year(year, opts \\ []), to: AlbumService

  @doc """
  Liste les albums publiés groupés par année avec cache.

  Délègue à `AlbumCacheService.list_published_albums_by_year/1`.
  """
  @spec list_published_albums_by_year(keyword()) :: %{integer() => [Album.t()]}
  defdelegate list_published_albums_by_year(opts \\ []), to: AlbumCacheService

  @doc """
  Liste tous les albums publiés (liste plate pour sitemap, etc.).

  Délègue à `AlbumCacheService.list_published_albums/1`.
  """
  @spec list_published_albums(keyword()) :: [Album.t()]
  defdelegate list_published_albums(opts \\ []), to: AlbumCacheService

  @doc """
  Publie un album en le rendant visible publiquement.

  Délègue à `AlbumPublicationService.execute/2`.
  """
  @spec publish_album(Album.t(), Ecto.UUID.t() | nil) ::
          {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def publish_album(%Album{} = album, user_id \\ nil) do
    AlbumPublicationService.execute(album, user_id: user_id)
  end

  # =============================================================================
  # Photo API - Delegates to PhotoService
  # =============================================================================

  @doc """
  Liste toutes les photos avec options de filtrage.

  Délègue à `PhotoService.list_photos/1`.
  """
  @spec list_photos(keyword()) :: [Photo.t()]
  defdelegate list_photos(opts \\ []), to: PhotoService

  @doc """
  Liste toutes les photos d'un album.

  Délègue à `PhotoService.list_photos_by_album/2`.
  """
  @spec list_photos_by_album(Ecto.UUID.t(), keyword()) :: [Photo.t()]
  defdelegate list_photos_by_album(album_id, opts \\ []), to: PhotoService

  @doc """
  Récupère une photo par son ID.

  Délègue à `PhotoService.get_photo/2`.
  """
  @spec get_photo(Ecto.UUID.t(), keyword()) :: {:ok, Photo.t()} | {:error, :not_found}
  defdelegate get_photo(id, opts \\ []), to: PhotoService

  @doc """
  Récupère une photo par son ID, lève une exception si non trouvée.

  Délègue à `PhotoService.get_photo!/2`.
  """
  @spec get_photo!(Ecto.UUID.t(), keyword()) :: Photo.t()
  defdelegate get_photo!(id, opts \\ []), to: PhotoService

  @doc """
  Crée une nouvelle photo dans un album.

  Délègue à `PhotoService.create_photo/1`.
  """
  @spec create_photo(map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  defdelegate create_photo(attrs), to: PhotoService

  @doc """
  Met à jour une photo existante.

  Délègue à `PhotoService.update_photo/2`.
  """
  @spec update_photo(Photo.t(), map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  defdelegate update_photo(photo, attrs), to: PhotoService

  @doc """
  Supprime une photo ainsi que son fichier sur le disque de manière atomique.

  Délègue à `PhotoDeletionService.execute/1`.
  """
  @spec delete_photo(Photo.t()) :: {:ok, map()} | {:error, Ecto.Multi.name(), term(), map()}
  def delete_photo(%Photo{} = photo) do
    PhotoDeletionService.execute(photo)
  end

  @doc """
  Upload des photos dans un album en parallèle.

  Délègue à `PhotoUploadService.execute/3`.
  """
  @spec upload_photos(String.t(), [PhotoUploadService.upload()], keyword()) ::
          {:ok, [PhotoUploadService.photo_metadata()]}
          | {:error, PhotoUploadService.error_reason()}
  def upload_photos(album_slug, uploads, opts \\ []) when is_list(uploads) do
    PhotoUploadService.execute(album_slug, uploads, opts)
  end

  @doc """
  Récupère l'URL d'une variante d'une photo.

  Délègue à `PhotoService.get_photo_url/2`.
  """
  @spec get_photo_url(String.t(), atom()) :: {:ok, String.t()} | {:error, term()}
  defdelegate get_photo_url(photo_id, variant), to: PhotoService

  @doc """
  Relance le traitement des variantes pour une photo.

  Délègue à `PhotoService.reprocess_photo/1`.
  """
  @spec reprocess_photo(Photo.t()) :: {:ok, Photo.t()} | {:error, term()}
  defdelegate reprocess_photo(photo), to: PhotoService

  @doc """
  Liste les photos en attente de traitement.

  Délègue à `PhotoService.list_pending_photos/1`.
  """
  @spec list_pending_photos(keyword()) :: [Photo.t()]
  defdelegate list_pending_photos(opts \\ []), to: PhotoService

  @doc """
  Liste les photos dont le traitement a échoué.

  Délègue à `PhotoService.list_failed_photos/1`.
  """
  @spec list_failed_photos(keyword()) :: [Photo.t()]
  defdelegate list_failed_photos(opts \\ []), to: PhotoService

  @doc """
  Retourne les statistiques de traitement des photos.

  Délègue à `PhotoService.get_processing_stats/0`.
  """
  @spec get_processing_stats() :: %{
          pending: non_neg_integer(),
          processing: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          total: non_neg_integer()
        }
  defdelegate get_processing_stats(), to: PhotoService

  @doc """
  Calcule l'espace de stockage utilisé par les photos.

  Délègue à `PhotoService.get_storage_usage/1`.
  """
  @spec get_storage_usage(keyword()) :: float() | non_neg_integer()
  defdelegate get_storage_usage(opts \\ []), to: PhotoService

  @doc """
  Retourne la photo en attente de traitement la plus ancienne.

  Délègue à `PhotoService.get_oldest_pending_photo/0`.
  """
  @spec get_oldest_pending_photo() :: {:ok, Photo.t()} | {:error, :not_found}
  defdelegate get_oldest_pending_photo(), to: PhotoService

  @doc """
  Relance le traitement de toutes les photos en échec.

  Délègue à `PhotoService.reprocess_all_failed_photos/0`.
  """
  @spec reprocess_all_failed_photos() :: {:ok, non_neg_integer()}
  defdelegate reprocess_all_failed_photos(), to: PhotoService

  @doc """
  Réorganise l'ordre d'affichage des photos d'un album.

  Délègue à `PhotoService.reorder_photos/2`.
  """
  @spec reorder_photos(Ecto.UUID.t(), [Ecto.UUID.t()]) ::
          {:ok, integer()} | {:error, :invalid_photos}
  defdelegate reorder_photos(album_id, photo_ids), to: PhotoService

  # =============================================================================
  # Helper Functions - Delegates to AlbumService and PhotoService
  # =============================================================================

  @doc """
  Retourne la liste des types d'albums disponibles.

  Délègue à `AlbumService.list_album_types/0`.
  """
  @spec list_album_types() :: [AlbumService.album_type(), ...]
  defdelegate list_album_types(), to: AlbumService

  @doc """
  Compte le nombre de photos dans un album.

  Délègue à `AlbumService.count_photos_in_album/1`.
  """
  @spec count_photos_in_album(Ecto.UUID.t()) :: non_neg_integer()
  defdelegate count_photos_in_album(album_id), to: AlbumService

  @doc """
  Alias pour count_photos_in_album/1.

  Délègue à `PhotoService.count_photos_by_album/1`.
  """
  @spec count_photos_by_album(Ecto.UUID.t()) :: non_neg_integer()
  defdelegate count_photos_by_album(album_id), to: PhotoService

  @doc """
  Compte le nombre total de photos dans tous les albums.

  Délègue à `PhotoService.count_all_photos/0`.
  """
  @spec count_all_photos() :: non_neg_integer()
  defdelegate count_all_photos(), to: PhotoService
end
