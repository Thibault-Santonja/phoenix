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
  - **Infrastructure Layer** : Repositories, FileStorage

  ## Stratégie de Cache

  Le contexte utilise Cachex pour optimiser les requêtes fréquentes :

  ### Albums Publiés par Année

  - **Clé de cache** : `{:published_albums_by_year, preloads}`
  - **TTL** : 1 heure
  - **Invalidation** : Lors de la publication/dépublication d'un album
  - **Fonction** : `list_published_albums_by_year/1`

  ### Invalidation du Cache

  Le cache est automatiquement invalidé dans les cas suivants :

  1. **Mise à jour d'un album** (`update_album/2`) :
     - Invalide si l'album est/était publié
     - Gère à la fois publish et unpublish

  2. **Publication d'un album** (`publish_album/2`) :
     - Délégué au `AlbumPublicationService`
     - Invalide le cache après publication réussie

  ### Mode Test

  En environnement test, le cache est automatiquement désactivé via
  l'option `:skip_cache` pour éviter la pollution entre tests.

  ## Exemples

      # Lister tous les albums publiés groupés par année
      {:ok, albums_by_year} = Photography.list_published_albums_by_year()

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

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.{Album, Photo, Storage}
  alias Portfolio.Photography.Events.{PhotoDeleted, PhotoUploaded}
  alias Portfolio.Photography.Repositories.{AlbumRepository, PhotoRepository}
  alias Portfolio.Repo

  # Service Layer
  alias Portfolio.Services.Photography.{
    AlbumDeletionService,
    AlbumPublicationService,
    PhotoUploadService
  }

  # =============================================================================
  # Album API
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
  Met à jour un album existant et invalide le cache.

  ## Exemples

      iex> update_album(album, %{title: "Nouveau titre"})
      {:ok, %Album{}}
  """
  @spec update_album(Album.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def update_album(album, attrs) do
    with_telemetry([:album, :updated], %{album_id: album.id}, fn ->
      case AlbumRepository.update(album, attrs) do
        {:ok, updated_album} = result ->
          # Invalider le cache si l'album est/était publié
          # (pour gérer à la fois publish et unpublish)
          if updated_album.published or album.published do
            invalidate_albums_cache()
          end

          result

        error ->
          error
      end
    end)
  end

  @doc """
  Supprime un album et toutes ses photos (CASCADE) de manière atomique.

  Délègue au AlbumDeletionService pour orchestrer l'opération complète.

  ## Exemples

      iex> delete_album(album)
      {:ok, %{album: %Album{}, photos: [%Photo{}], files: :ok}}
  """
  @spec delete_album(Album.t()) :: {:ok, map()} | {:error, Ecto.Multi.name(), term(), map()}
  def delete_album(%Album{} = album) do
    AlbumDeletionService.execute(album)
  end

  @doc """
  Liste les années ayant des albums publiés, triées par ordre décroissant.

  Utilise une requête SQL optimisée pour récupérer uniquement les années distinctes
  sans charger les albums complets. Idéal pour le lazy loading.

  ## Exemples

      iex> list_published_years()
      [2024, 2023, 2022, 2021]

  """
  @spec list_published_years() :: [integer()]
  def list_published_years do
    AlbumRepository.list_published_years()
  end

  @doc """
  Liste les albums publiés pour une année spécifique.

  Optimisé pour le lazy loading : charge uniquement les albums d'une année donnée.
  Utilisez `list_published_years/0` en combinaison avec cette fonction pour un
  chargement progressif par année.

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
  Liste les albums publiés groupés par année avec cache.

  Utilise Cachex pour mettre en cache les résultats et éviter les requêtes répétées.
  Le cache expire après 1 heure ou est invalidé lors de la publication d'un album.

  Retourne une map avec les années comme clés et les albums comme valeurs.

  **Note de performance:** Pour de meilleurs résultats avec de grands datasets,
  préférez utiliser `list_published_years/0` + `list_published_for_year/2` qui
  permettent un lazy loading plus efficace.

  ## Options

  - `:preload` - Associations à précharger
  - `:skip_cache` - Ignorer le cache et forcer une requête DB (défaut: false)

  ## Exemples

      iex> list_published_albums_by_year()
      %{2024 => [%Album{}], 2023 => [%Album{}]}

      iex> list_published_albums_by_year(skip_cache: true)
      %{2024 => [%Album{}], 2023 => [%Album{}]}
  """
  @spec list_published_albums_by_year(keyword()) :: %{integer() => [Album.t()]}
  def list_published_albums_by_year(opts \\ []) do
    skip_cache = Keyword.get(opts, :skip_cache, false)
    cache_key = {:published_albums_by_year, opts[:preload] || []}

    # En test, toujours skip le cache pour éviter la pollution entre tests
    skip_cache = skip_cache or Mix.env() == :test

    if skip_cache do
      AlbumRepository.list_published_by_year(opts)
    else
      case Cachex.fetch(:portfolio_cache, cache_key, fn ->
             result = AlbumRepository.list_published_by_year(opts)
             # Cache pendant 1 heure
             {:commit, result, ttl: :timer.hours(1)}
           end) do
        {:ok, albums} -> albums
        {:commit, albums, _opts} -> albums
        {:commit, albums} -> albums
        {:error, _reason} -> AlbumRepository.list_published_by_year(opts)
      end
    end
  end

  @doc """
  Publie un album en le rendant visible publiquement.

  Délègue au AlbumPublicationService pour orchestrer l'opération complète
  incluant la mise à jour DB, l'invalidation du cache, et l'émission d'événements.

  ## Paramètres

  - `album` - L'album à publier
  - `user_id` - L'ID de l'utilisateur qui publie l'album (optionnel)

  ## Exemples

      iex> publish_album(album)
      {:ok, %Album{published: true}}

      iex> publish_album(album, user_id)
      {:ok, %Album{published: true}}
  """
  @spec publish_album(Album.t(), Ecto.UUID.t() | nil) ::
          {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def publish_album(%Album{} = album, user_id \\ nil) do
    AlbumPublicationService.execute(album, user_id: user_id)
  end

  # =============================================================================
  # Photo API
  # =============================================================================

  @doc """
  Liste toutes les photos avec options de filtrage.

  ## Options

  - `:album_id` - Filtre par ID d'album
  - `:limit` - Limite le nombre de résultats
  - `:offset` - Décalage pour la pagination
  - `:preload` - Associations à précharger
  - `:order_by` - Ordre de tri

  ## Exemples

      iex> list_photos()
      [%Photo{}, %Photo{}]
  """
  @spec list_photos(keyword()) :: [Photo.t()]
  def list_photos(opts \\ []), do: PhotoRepository.list(opts)

  @doc """
  Liste toutes les photos d'un album.

  ## Exemples

      iex> list_photos_by_album(album_id)
      [%Photo{}, %Photo{}]
  """
  @spec list_photos_by_album(Ecto.UUID.t(), keyword()) :: [Photo.t()]
  def list_photos_by_album(album_id, opts \\ []),
    do: PhotoRepository.list_by_album(album_id, opts)

  @doc """
  Récupère une photo par son ID.
  """
  @spec get_photo(Ecto.UUID.t(), keyword()) :: {:ok, Photo.t()} | {:error, :not_found}
  def get_photo(id, opts \\ []), do: PhotoRepository.get(id, opts)

  @doc """
  Récupère une photo par son ID, lève une exception si non trouvée.
  """
  @spec get_photo!(Ecto.UUID.t(), keyword()) :: Photo.t()
  def get_photo!(id, opts \\ []), do: PhotoRepository.get!(id, opts)

  @doc """
  Crée une nouvelle photo dans un album.

  Émet un événement `PhotoUploaded` après la création réussie de la photo.

  ## Exemples

      iex> create_photo(%{album_id: album_id, original_filename: "test.jpg", file_path: "/test.jpg"})
      {:ok, %Photo{}}
  """
  @spec create_photo(map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def create_photo(attrs) do
    with_telemetry([:photo, :created], %{album_id: attrs[:album_id]}, fn ->
      with {:ok, photo} <- PhotoRepository.insert(attrs) do
        # Émettre l'événement de domaine
        DomainEvents.publish(:photo_uploaded, %PhotoUploaded{
          photo_id: photo.id,
          album_id: photo.album_id,
          file_path: photo.file_path,
          hash: photo.hash,
          uploaded_at: photo.inserted_at
        })

        {:ok, photo}
      end
    end)
  end

  @doc """
  Met à jour une photo existante.
  """
  @spec update_photo(Photo.t(), map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def update_photo(photo, attrs) do
    with_telemetry([:photo, :updated], %{photo_id: photo.id, album_id: photo.album_id}, fn ->
      PhotoRepository.update(photo, attrs)
    end)
  end

  @doc """
  Supprime une photo ainsi que son fichier sur le disque de manière atomique.

  Cette opération utilise Ecto.Multi pour garantir l'atomicité :
  - L'enregistrement en base de données est supprimé en premier
  - Le fichier physique est supprimé ensuite
  - Si la suppression du fichier échoue, la transaction DB est rollback

  ## Exemples

      iex> delete_photo(photo)
      {:ok, %{photo: %Photo{}, file: :ok}}

      iex> delete_photo(photo_with_invalid_file)
      {:ok, %{photo: %Photo{}, file: :ok}}  # Les données orphelines sont acceptées
  """
  @spec delete_photo(Photo.t()) :: {:ok, map()} | {:error, Ecto.Multi.name(), term(), map()}
  def delete_photo(%Photo{} = photo) do
    with_telemetry([:photo, :deleted], %{photo_id: photo.id, album_id: photo.album_id}, fn ->
      result =
        Ecto.Multi.new()
        |> Ecto.Multi.delete(:photo, photo)
        |> Ecto.Multi.run(:file, fn _repo, %{photo: deleted_photo} ->
          # Supprimer le fichier via FileStorage
          case Storage.backend().delete_photo(deleted_photo.file_path) do
            :ok ->
              {:ok, :ok}

            {:error, :not_found} ->
              # Si le fichier n'existe pas, c'est acceptable (données orphelines)
              {:ok, :ok}

            {:error, reason} ->
              # Autre erreur de suppression fichier - rollback de la transaction
              {:error, reason}
          end
        end)
        |> Repo.transaction()

      case result do
        {:ok, %{photo: deleted_photo}} ->
          # Émettre l'événement de domaine
          DomainEvents.publish(:photo_deleted, %PhotoDeleted{
            photo_id: deleted_photo.id,
            album_id: deleted_photo.album_id,
            file_path: deleted_photo.file_path,
            deleted_at: DateTime.utc_now()
          })

          result

        _error ->
          result
      end
    end)
  end

  @doc """
  Upload des photos dans un album en parallèle.

  Utilise Task.async_stream pour paralléliser les uploads et optimiser les performances.
  Stocke les fichiers via FileStorage et crée les enregistrements en base.

  Émet un événement telemetry `[:portfolio, :photography, :photos, :uploaded]` avec
  la durée, le nombre de photos, et le résultat de l'opération.

  ## Paramètres

  - `album_slug` - Le slug de l'album (pour l'organisation des fichiers)
  - `uploads` - Liste d'uploads avec :path, :client_name, :client_type

  ## Options

  - `:max_concurrency` - Nombre maximum d'uploads parallèles (défaut: 4)
  - `:timeout` - Timeout par upload en ms (défaut: 30000)
  - `:ordered` - Préserver l'ordre des résultats (défaut: false pour performance)

  ## Retour

  - `{:ok, [metadata]}` - Liste des métadonnées des photos créées
  - `{:error, reason}` - Erreur lors du stockage ou création

  ## Exemples

      iex> upload_photos("mariage-2024", uploads)
      {:ok, [%{file_path: "...", hash: "..."}, ...]}

      iex> upload_photos("mariage-2024", uploads, max_concurrency: 8)
      {:ok, [%{file_path: "...", hash: "..."}, ...]}
  """
  @spec upload_photos(String.t(), [map()], keyword()) :: {:ok, [map()]} | {:error, term()}
  def upload_photos(album_slug, uploads, opts \\ []) when is_list(uploads) do
    PhotoUploadService.execute(album_slug, uploads, opts)
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  # Exécute une fonction avec instrumentation telemetry
  #
  # ## Paramètres
  # - `event_name` - Liste de segments du nom de l'événement (ex: [:album, :created])
  # - `metadata` - Map de métadonnées à ajouter à l'événement
  # - `fun` - Fonction à exécuter et instrumenter
  #
  # ## Retour
  # Retourne le résultat de la fonction
  #
  # ## Exemples
  #
  #     with_telemetry([:album, :created], %{}, fn ->
  #       AlbumRepository.insert(attrs)
  #     end)
  #
  defp with_telemetry(event_name, metadata, fun) when is_list(event_name) and is_map(metadata) do
    start_time = System.monotonic_time()
    result = fun.()
    duration = System.monotonic_time() - start_time

    metrics = %{duration: duration}
    full_metadata = Map.merge(metadata, result_metadata(result))

    :telemetry.execute([:portfolio, :photography | event_name], metrics, full_metadata)
    result
  end

  # Extrait les métadonnées du résultat pour telemetry
  defp result_metadata({:ok, _}), do: %{result: :ok}
  defp result_metadata({:error, _}), do: %{result: :error}
  defp result_metadata(_), do: %{}

  # Invalide tous les caches liés aux albums publiés
  #
  # Cette fonction doit être appelée après toute opération qui affecte
  # la liste des albums publiés :
  # - Publication d'un album (publish_album/2)
  # - Dépublication d'un album (update_album/2 avec published: false)
  # - Mise à jour d'un album publié (update_album/2)
  #
  # Note: La suppression d'album (delete_album/1) est gérée par AlbumDeletionService
  defp invalidate_albums_cache do
    Cachex.del(:portfolio_cache, {:published_albums_by_year, []})
    Cachex.del(:portfolio_cache, {:published_albums_by_year, [:photos]})
    :ok
  end

  @doc """
  Réorganise l'ordre d'affichage des photos d'un album.

  ## Exemples

      iex> reorder_photos(album_id, [photo1_id, photo2_id, photo3_id])
      {:ok, 3}
  """
  @spec reorder_photos(Ecto.UUID.t(), [Ecto.UUID.t()]) ::
          {:ok, integer()} | {:error, :invalid_photos}
  def reorder_photos(album_id, photo_ids), do: PhotoRepository.reorder(album_id, photo_ids)

  # =============================================================================
  # Helper Functions
  # =============================================================================

  @doc """
  Retourne la liste des types d'albums disponibles.

  ## Exemples

      iex> list_album_types()
      [:couples, :wedding, :motherhood, :events, :landscape, :street, :music, :reenactment, :amvcc, :china, :japan, :taiwan]
  """
  @spec list_album_types() :: [atom()]
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
  def count_photos_in_album(album_id) do
    PhotoRepository.count_by_album(album_id)
  end

  @doc """
  Alias pour count_photos_in_album/1.
  """
  @spec count_photos_by_album(Ecto.UUID.t()) :: non_neg_integer()
  def count_photos_by_album(album_id), do: count_photos_in_album(album_id)

  @doc """
  Compte le nombre total de photos dans tous les albums.

  Utilise une seule requête SQL optimisée.

  ## Exemples

      iex> count_all_photos()
      150
  """
  @spec count_all_photos() :: non_neg_integer()
  def count_all_photos do
    PhotoRepository.count_all()
  end
end
