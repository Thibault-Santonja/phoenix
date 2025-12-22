defmodule Portfolio.Services.Photography.PhotoService do
  @moduledoc """
  Service responsable des opérations CRUD sur les photos et du traitement.

  Ce service encapsule la logique métier liée aux photos :
  - Création, lecture, mise à jour
  - Gestion du statut de traitement
  - Retraitement des photos en échec
  - Opérations de stockage (URLs, usage)
  - Réorganisation de l'ordre des photos

  Ce service NE gère PAS :
  - La suppression (voir PhotoDeletionService)
  - L'upload workflow (voir PhotoUploadService)
  """

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.Events.PhotoUploaded
  alias Portfolio.Photography.Photo
  alias Portfolio.Photography.Repositories.PhotoRepository
  alias Portfolio.Workers.ImageVariantWorker

  # =============================================================================
  # Query Operations
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

  # =============================================================================
  # CRUD Operations
  # =============================================================================

  @doc """
  Crée une nouvelle photo dans un album.

  Émet un événement `PhotoUploaded` après la création réussie.

  ## Exemples

      iex> create_photo(%{album_id: album_id, original_filename: "test.jpg", file_path: "/test.jpg"})
      {:ok, %Photo{}}
  """
  @spec create_photo(map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def create_photo(attrs) do
    with_telemetry([:photo, :created], %{album_id: attrs[:album_id]}, fn ->
      with {:ok, photo} <- PhotoRepository.insert(attrs) do
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

  # =============================================================================
  # Processing Status Management
  # =============================================================================

  @doc """
  Liste les photos en attente de traitement.

  ## Options

  - `:limit` - Nombre maximum de résultats (défaut: 100)
  - `:preload` - Associations à précharger

  ## Exemples

      iex> list_pending_photos()
      [%Photo{processing_status: "pending"}, ...]
  """
  @spec list_pending_photos(keyword()) :: [Photo.t()]
  def list_pending_photos(opts \\ []), do: list_photos_by_status("pending", opts)

  @doc """
  Liste les photos dont le traitement a échoué.

  ## Options

  - `:limit` - Nombre maximum de résultats (défaut: 100)
  - `:preload` - Associations à précharger

  ## Exemples

      iex> list_failed_photos()
      [%Photo{processing_status: "failed"}, ...]
  """
  @spec list_failed_photos(keyword()) :: [Photo.t()]
  def list_failed_photos(opts \\ []), do: list_photos_by_status("failed", opts)

  @doc """
  Retourne les statistiques de traitement des photos.

  ## Exemples

      iex> get_processing_stats()
      %{pending: 12, processing: 3, completed: 1247, failed: 5, total: 1267}
  """
  @spec get_processing_stats() :: %{
          pending: non_neg_integer(),
          processing: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          total: non_neg_integer()
        }
  def get_processing_stats, do: PhotoRepository.count_by_processing_status()

  @doc """
  Retourne la photo en attente de traitement la plus ancienne.

  Utile pour détecter les jobs bloqués.

  ## Exemples

      iex> get_oldest_pending_photo()
      {:ok, %Photo{inserted_at: ~U[2025-01-26 10:00:00Z]}}

      iex> get_oldest_pending_photo()
      {:error, :not_found}
  """
  @spec get_oldest_pending_photo() :: {:ok, Photo.t()} | {:error, :not_found}
  def get_oldest_pending_photo do
    PhotoRepository.get_oldest_by_processing_status("pending")
  end

  # =============================================================================
  # Reprocessing Operations
  # =============================================================================

  @doc """
  Relance le traitement des variantes pour une photo.

  Utile en cas d'échec du traitement initial.

  ## Exemples

      iex> reprocess_photo(photo)
      {:ok, %Photo{}}
  """
  @spec reprocess_photo(Photo.t()) :: {:ok, Photo.t()} | {:error, term()}
  def reprocess_photo(%Photo{id: photo_id} = photo) do
    with {:ok, updated_photo} <- update_photo(photo, %{processing_status: "pending"}),
         {:ok, _job} <- ImageVariantWorker.enqueue(photo_id) do
      {:ok, updated_photo}
    end
  end

  @doc """
  Relance le traitement de toutes les photos en échec.

  Utilise le traitement concurrent pour optimiser les performances
  lors du retraitement de nombreuses photos.

  Retourne le nombre de photos relancées avec succès.

  ## Options

  - `:max_concurrency` - Nombre maximum de tâches concurrentes (défaut: 10)
  - `:timeout` - Timeout par photo en millisecondes (défaut: 5000)

  ## Exemples

      iex> reprocess_all_failed_photos()
      {:ok, 5}

      iex> reprocess_all_failed_photos(max_concurrency: 20)
      {:ok, 15}
  """
  @spec reprocess_all_failed_photos(keyword()) :: {:ok, non_neg_integer()}
  def reprocess_all_failed_photos(opts \\ []) do
    max_concurrency = Keyword.get(opts, :max_concurrency, 10)
    timeout = Keyword.get(opts, :timeout, 5_000)

    failed_photos = list_failed_photos(limit: 1000)

    count =
      failed_photos
      |> Task.async_stream(
        &reprocess_photo/1,
        max_concurrency: max_concurrency,
        timeout: timeout,
        on_timeout: :kill_task
      )
      |> Enum.count(fn
        {:ok, {:ok, _}} -> true
        _ -> false
      end)

    {:ok, count}
  end

  # =============================================================================
  # Storage Operations
  # =============================================================================

  @doc """
  Récupère l'URL d'une variante d'une photo.

  ## Paramètres

  - `photo_id` - L'identifiant de la photo
  - `variant` - Le nom de la variante (:thumbnail, :small, :medium, :large, :original)

  ## Exemples

      iex> get_photo_url("abc12345", :thumbnail)
      {:ok, "/uploads/photos/abc12345/thumbnail.webp"}
  """
  @spec get_photo_url(String.t(), atom()) :: {:ok, String.t()} | {:error, term()}
  def get_photo_url(photo_id, variant) do
    storage_adapter().get_photo_url(photo_id, variant)
  end

  @doc """
  Calcule l'espace de stockage utilisé par les photos.

  ## Options

  - `:unit` - Unité de retour (`:bytes`, `:kb`, `:mb`, `:gb`) (défaut: `:bytes`)

  ## Exemples

      iex> get_storage_usage()
      3435973120

      iex> get_storage_usage(unit: :gb)
      3.2
  """
  @spec get_storage_usage(keyword()) :: float() | non_neg_integer()
  def get_storage_usage(opts \\ []) do
    unit = Keyword.get(opts, :unit, :bytes)
    bytes = storage_adapter().get_storage_usage()

    case unit do
      :bytes -> bytes
      :kb -> bytes / 1024
      :mb -> bytes / (1024 * 1024)
      :gb -> bytes / (1024 * 1024 * 1024)
    end
  end

  # =============================================================================
  # Photo Ordering
  # =============================================================================

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
  # Statistics & Counting
  # =============================================================================

  @doc """
  Compte le nombre total de photos dans tous les albums.

  ## Exemples

      iex> count_all_photos()
      1247
  """
  @spec count_all_photos() :: non_neg_integer()
  def count_all_photos, do: PhotoRepository.count_all()

  @doc """
  Compte le nombre de photos dans un album.

  ## Exemples

      iex> count_photos_by_album(album_id)
      42
  """
  @spec count_photos_by_album(Ecto.UUID.t()) :: non_neg_integer()
  def count_photos_by_album(album_id), do: PhotoRepository.count_by_album(album_id)

  # =============================================================================
  # Private Helper Functions
  # =============================================================================

  defp list_photos_by_status(status, opts) do
    limit = Keyword.get(opts, :limit, 100)
    preload = Keyword.get(opts, :preload, [])

    PhotoRepository.list_by_processing_status(status, limit: limit, preload: preload)
  end

  defp storage_adapter do
    Application.get_env(
      :portfolio,
      :photo_storage_adapter,
      Portfolio.Photography.Storage.LocalStorage
    )
  end

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
