defmodule Portfolio.Workers.ExifExtractionWorker do
  @moduledoc """
  Oban worker for extracting EXIF metadata from uploaded photos.

  This worker replaces the previous Task.start approach with a persistent,
  retryable job system. According to ADR-011 Phase 3 and ADR-013, EXIF
  extraction should be:

  - **Persistent**: Survives server restarts (Oban PostgreSQL storage)
  - **Retryable**: Handles transient I/O errors with exponential backoff
  - **Monitored**: Visible in Oban dashboard for debugging
  - **Low priority**: Less critical than image variant generation

  ## Extracted EXIF Data

  Key metadata extracted and stored in dedicated columns:
  - `captured_at`: DateTime from EXIF DateTimeOriginal (for Timeline)
  - `camera`, `lens`: Equipment info (for credibility, portfolio display)
  - `iso`, `aperture`, `focal_length`, `shutter_speed`: Camera settings
  - `gps_latitude`, `gps_longitude`: GPS coordinates (stored, not publicly exposed)

  Additional metadata stored in `exif_data` JSONB field.

  ## Error Handling

  - **Permanent errors** (`{:cancel, reason}`): Photo not found, file not found
  - **Transient errors** (`{:error, reason}`): I/O errors, temporary unavailability
    - Oban will retry with exponential backoff: 15s, 2m, 5m

  ## Queue Configuration

  - Queue: `:exif_extraction`
  - Concurrency: 5 (light CPU/memory usage)
  - Max attempts: 3 (reasonable for I/O operations)
  - Priority: 2 (lower than image_processing priority 1)

  ## Usage

      # Enqueue EXIF extraction job for a photo
      %{photo_id: photo_id}
      |> ExifExtractionWorker.new()
      |> Oban.insert()

  """
  use Oban.Worker,
    queue: :exif_extraction,
    max_attempts: 3,
    priority: 2

  require Logger

  alias Portfolio.Exif.Parser
  alias Portfolio.Photography

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}, attempt: attempt}) do
    Logger.info("Extracting EXIF data",
      photo_id: photo_id,
      attempt: attempt
    )

    case Photography.get_photo(photo_id) do
      {:ok, photo} ->
        extract_and_update_exif(photo)

      {:error, :not_found} ->
        Logger.warning("Photo not found for EXIF extraction",
          photo_id: photo_id,
          attempt: attempt
        )

        {:cancel, "Photo not found"}
    end
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  @spec extract_and_update_exif(Portfolio.Photography.Photo.t()) ::
          :ok | {:cancel, String.t()} | {:error, term()}
  defp extract_and_update_exif(photo) do
    file_path = build_absolute_path(photo.file_path)

    if File.exists?(file_path) do
      case extract_exif_data(file_path) do
        {:ok, exif_data} ->
          update_photo_with_exif(photo, exif_data)

        {:error, reason} ->
          Logger.warning("Failed to extract EXIF data",
            photo_id: photo.id,
            file_path: file_path,
            reason: inspect(reason)
          )

          # Transient error - allow retry
          {:error, reason}
      end
    else
      Logger.warning("Photo file not found",
        photo_id: photo.id,
        file_path: file_path
      )

      # Permanent error - cancel job
      {:cancel, "File not found"}
    end
  end

  @spec build_absolute_path(String.t()) :: String.t()
  defp build_absolute_path(file_path) do
    # Convert relative path to absolute path
    # file_path is like "/uploads/albums/slug/photos/photo.jpg"
    priv_dir = Application.app_dir(:portfolio, "priv")
    Path.join([priv_dir, "static", file_path])
  end

  defp extract_exif_data(file_path) do
    # Use Exiftool.execute to get structured EXIF data
    case Exiftool.execute([file_path]) do
      {:ok, exif_map} when is_map(exif_map) ->
        parsed = Parser.parse_relevant_exif(exif_map)
        {:ok, parsed}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e ->
      Logger.error("Exception extracting EXIF",
        file_path: file_path,
        error: Exception.message(e)
      )

      {:error, :exiftool_exception}
  end

  @spec update_photo_with_exif(Portfolio.Photography.Photo.t(), map()) :: :ok | {:error, term()}
  defp update_photo_with_exif(photo, exif_data) do
    # Merge new EXIF data with existing exif_data JSON field
    merged_exif = Map.merge(photo.exif_data, exif_data)

    # Build update attributes for dedicated columns
    attrs =
      %{exif_data: merged_exif}
      |> Parser.maybe_add(:captured_at, exif_data[:captured_at])
      |> Parser.maybe_add(:camera, exif_data[:camera])
      |> Parser.maybe_add(:lens, exif_data[:lens])
      |> Parser.maybe_add(:iso, exif_data[:iso])
      |> Parser.maybe_add(:aperture, exif_data[:aperture])
      |> Parser.maybe_add(:focal_length, exif_data[:focal_length])
      |> Parser.maybe_add(:shutter_speed, exif_data[:shutter_speed])
      |> Parser.maybe_add(:gps_latitude, exif_data[:gps_latitude])
      |> Parser.maybe_add(:gps_longitude, exif_data[:gps_longitude])

    case Photography.update_photo(photo, attrs) do
      {:ok, _updated_photo} ->
        Logger.info("EXIF data extracted and stored",
          photo_id: photo.id,
          fields: Map.keys(exif_data),
          captured_at: exif_data[:captured_at],
          camera: exif_data[:camera]
        )

        :ok

      {:error, changeset} ->
        Logger.error("Failed to update photo with EXIF data",
          photo_id: photo.id,
          errors: inspect(changeset.errors)
        )

        # Transient error - allow retry
        {:error, changeset}
    end
  end
end
