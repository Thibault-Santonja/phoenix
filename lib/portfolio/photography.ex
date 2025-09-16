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
  alias Portfolio.Photography.{Album, Photo}
  alias Portfolio.Photography.Events.{AlbumPublished, PhotoUploaded}
  alias Portfolio.Photography.Repositories.{AlbumRepository, PhotoRepository}
  alias Portfolio.Repo

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
    start_time = System.monotonic_time()

    result = AlbumRepository.insert(attrs)

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :photography, :album, :created],
      %{duration: duration},
      %{result: elem(result, 0)}
    )

    result
  end

  @doc """
  Met à jour un album existant et invalide le cache.

  ## Exemples

      iex> update_album(album, %{title: "Nouveau titre"})
      {:ok, %Album{}}
  """
  @spec update_album(Album.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def update_album(album, attrs) do
    case AlbumRepository.update(album, attrs) do
      {:ok, updated_album} = result ->
        # Invalider le cache si l'album est publié
        if updated_album.published do
          invalidate_albums_cache()
        end

        result

      error ->
        error
    end
  end

  @doc """
  Supprime un album et toutes ses photos (CASCADE) de manière atomique.

  Utilise Ecto.Multi pour garantir l'atomicité :
  - Récupère toutes les photos de l'album
  - Supprime les fichiers physiques de toutes les photos
  - Supprime l'album (les photos seront supprimées en CASCADE)
  - Si l'une des opérations échoue, toute la transaction est annulée

  ## Exemples

      iex> delete_album(album)
      {:ok, %{album: %Album{}, files: :ok}}
  """
  @spec delete_album(Album.t()) :: {:ok, map()} | {:error, Ecto.Multi.name(), term(), map()}
  def delete_album(%Album{} = album) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:photos, fn _repo, _changes ->
      # Récupérer toutes les photos de l'album
      photos = list_photos_by_album(album.id)
      {:ok, photos}
    end)
    |> Ecto.Multi.run(:files, fn _repo, %{photos: photos} ->
      # Supprimer tous les fichiers physiques
      results =
        Enum.map(photos, fn photo ->
          storage().delete_photo(photo.file_path)
        end)

      # Vérifier si toutes les suppressions ont réussi (on accepte :not_found)
      if Enum.all?(results, &(&1 == :ok || &1 == {:error, :not_found})) do
        {:ok, :ok}
      else
        # Trouver la première vraie erreur
        error = Enum.find(results, &match?({:error, reason} when reason != :not_found, &1))
        error
      end
    end)
    |> Ecto.Multi.delete(:album, album)
    |> Repo.transaction()
  end

  @doc """
  Liste les albums publiés groupés par année avec cache.

  Utilise Cachex pour mettre en cache les résultats et éviter les requêtes répétées.
  Le cache expire après 1 heure ou est invalidé lors de la publication d'un album.

  Retourne une map avec les années comme clés et les albums comme valeurs.

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
        {:commit, albums} -> albums
        {:error, _reason} -> AlbumRepository.list_published_by_year(opts)
      end
    end
  end

  @doc """
  Publie un album en le rendant visible publiquement et invalide le cache.

  Émet un événement `AlbumPublished` pour permettre à d'autres contextes
  de réagir à la publication (notifications, indexation, etc.).

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
    with {:ok, album} <- AlbumRepository.update(album, %{published: true}) do
      # Invalider le cache des albums publiés
      invalidate_albums_cache()

      # Émettre l'événement de domaine
      DomainEvents.publish(:album_published, %AlbumPublished{
        album_id: album.id,
        title: album.title,
        slug: album.slug,
        published_at: DateTime.utc_now(),
        user_id: user_id
      })

      {:ok, album}
    end
  end

  # =============================================================================
  # Photo API
  # =============================================================================

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
  end

  @doc """
  Met à jour une photo existante.
  """
  @spec update_photo(Photo.t(), map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def update_photo(photo, attrs), do: PhotoRepository.update(photo, attrs)

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
    Ecto.Multi.new()
    |> Ecto.Multi.delete(:photo, photo)
    |> Ecto.Multi.run(:file, fn _repo, %{photo: deleted_photo} ->
      # Supprimer le fichier via FileStorage
      case storage().delete_photo(deleted_photo.file_path) do
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
    start_time = System.monotonic_time()
    count = length(uploads)

    max_concurrency = Keyword.get(opts, :max_concurrency, 4)
    timeout = Keyword.get(opts, :timeout, 30_000)
    ordered = Keyword.get(opts, :ordered, false)

    # Upload en parallèle avec Task.async_stream
    results =
      uploads
      |> Task.async_stream(
        fn upload -> storage().store_photo(album_slug, upload) end,
        max_concurrency: max_concurrency,
        timeout: timeout,
        ordered: ordered,
        on_timeout: :kill_task
      )
      |> Enum.to_list()

    # Vérifier si toutes les opérations ont réussi
    result =
      if Enum.all?(results, &match?({:ok, {:ok, _}}, &1)) do
        photos_metadata = Enum.map(results, fn {:ok, {:ok, meta}} -> meta end)
        {:ok, photos_metadata}
      else
        # Récupérer la première erreur
        case Enum.find(results, &match?({:ok, {:error, _}}, &1)) do
          {:ok, {:error, reason}} -> {:error, reason}
          {:exit, reason} -> {:error, {:task_exit, reason}}
          nil -> {:error, :unknown_error}
        end
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :photography, :photos, :uploaded],
      %{duration: duration, count: count},
      %{album_slug: album_slug, result: elem(result, 0)}
    )

    result
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp storage do
    Application.get_env(:portfolio, :file_storage)[:backend] ||
      Portfolio.Photography.Storage.LocalStorage
  end

  # Invalide tous les caches liés aux albums publiés
  defp invalidate_albums_cache do
    # Supprimer toutes les clés du cache qui correspondent aux albums publiés
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
end
