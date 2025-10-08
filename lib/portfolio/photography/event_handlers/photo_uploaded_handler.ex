defmodule Portfolio.Photography.EventHandlers.PhotoUploadedHandler do
  @moduledoc """
  Event handler for PhotoUploaded domain events.

  This handler reacts to photo upload events and can trigger
  various side effects such as:
  - Logging upload events
  - Generating thumbnails
  - Extracting EXIF metadata
  - Running image processing pipelines
  - Updating album statistics
  - Tracking storage metrics

  The handler runs as a GenServer and subscribes to the `:photo_uploaded`
  event type via the DomainEvents system.

  ## Architecture

  This handler is part of the Application Layer and coordinates
  infrastructure concerns (image processing, logging, etc.) in response
  to domain events.

  ## Supervision

  This GenServer is supervised by the main application supervisor
  and will restart automatically if it crashes.
  """

  use GenServer
  require Logger

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.Events.PhotoUploaded

  # =============================================================================
  # Public API
  # =============================================================================

  @doc """
  Starts the event handler GenServer.

  Called by the supervision tree during application startup.
  """
  @spec start_link(term()) :: GenServer.on_start()
  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  # =============================================================================
  # GenServer Callbacks
  # =============================================================================

  @impl true
  def init(_opts) do
    # Subscribe to photo_uploaded events
    DomainEvents.subscribe(:photo_uploaded)
    Logger.info("PhotoUploadedHandler started and subscribed to :photo_uploaded events")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:photo_uploaded, %PhotoUploaded{} = event}, state) do
    Logger.info("Photo uploaded",
      photo_id: event.photo_id,
      album_id: event.album_id,
      file_path: event.file_path,
      hash: event.hash,
      uploaded_at: event.uploaded_at
    )

    # Extract EXIF metadata asynchronously
    Task.start(fn -> extract_and_store_exif(event) end)

    {:noreply, state}
  end

  # Handle unexpected messages gracefully
  @impl true
  def handle_info(msg, state) do
    Logger.warning("PhotoUploadedHandler received unexpected message: #{inspect(msg)}")
    {:noreply, state}
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  @spec extract_and_store_exif(PhotoUploaded.t()) :: :ok | {:error, term()}
  defp extract_and_store_exif(event) do
    file_path = build_absolute_path(event.file_path)

    case extract_exif_data(file_path) do
      {:ok, exif_data} ->
        update_photo_exif(event.photo_id, exif_data)

      {:error, reason} ->
        Logger.warning("Failed to extract EXIF data",
          photo_id: event.photo_id,
          file_path: file_path,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  @spec build_absolute_path(String.t()) :: String.t()
  defp build_absolute_path(file_path) do
    # Convert relative path to absolute path
    # file_path is like "/uploads/albums/slug/original/photo.jpg"
    priv_dir = Application.app_dir(:portfolio, "priv")
    Path.join([priv_dir, "static", file_path])
  end

  @spec extract_exif_data(String.t()) :: {:ok, map()} | {:error, term()}
  defp extract_exif_data(file_path) do
    case File.exists?(file_path) do
      true ->
        # Use Exiftool.execute with -json flag for structured output
        case Exiftool.execute(["-json", file_path]) do
          {:ok, raw_exif} ->
            exif_data = parse_relevant_exif(raw_exif)
            {:ok, exif_data}

          {:error, reason} ->
            {:error, reason}
        end

      false ->
        {:error, :file_not_found}
    end
  end

  @spec parse_relevant_exif(map()) :: map()
  defp parse_relevant_exif(raw_exif) do
    # Extract only relevant EXIF fields for photography
    %{}
    |> maybe_add(:camera_make, raw_exif["Make"])
    |> maybe_add(:camera_model, raw_exif["Model"])
    |> maybe_add(:lens_model, raw_exif["LensModel"])
    |> maybe_add(:focal_length, raw_exif["FocalLength"])
    |> maybe_add(:aperture, raw_exif["FNumber"] || raw_exif["ApertureValue"])
    |> maybe_add(:shutter_speed, raw_exif["ExposureTime"] || raw_exif["ShutterSpeedValue"])
    |> maybe_add(:iso, raw_exif["ISO"])
    |> maybe_add(:taken_at, parse_datetime(raw_exif["DateTimeOriginal"]))
    |> maybe_add(:width, raw_exif["ImageWidth"])
    |> maybe_add(:height, raw_exif["ImageHeight"])
    |> maybe_add(:orientation, raw_exif["Orientation"])
    |> maybe_add(:flash, raw_exif["Flash"])
    |> maybe_add(:white_balance, raw_exif["WhiteBalance"])
  end

  @spec maybe_add(map(), atom(), any()) :: map()
  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, _key, ""), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  @spec parse_datetime(String.t() | nil) :: DateTime.t() | nil
  defp parse_datetime(nil), do: nil

  defp parse_datetime(datetime_string) when is_binary(datetime_string) do
    # EXIF datetime format: "YYYY:MM:DD HH:MM:SS"
    case String.split(datetime_string, " ") do
      [date_part, time_part] ->
        date = String.replace(date_part, ":", "-")
        datetime_str = "#{date} #{time_part}"

        case NaiveDateTime.from_iso8601(datetime_str) do
          {:ok, naive_dt} -> DateTime.from_naive!(naive_dt, "Etc/UTC")
          _ -> nil
        end

      _ ->
        nil
    end
  end

  @spec update_photo_exif(String.t(), map()) :: :ok | {:error, term()}
  defp update_photo_exif(photo_id, exif_data) do
    case Portfolio.Photography.get_photo(photo_id) do
      {:ok, photo} ->
        # Merge new EXIF data with existing data
        merged_exif = Map.merge(photo.exif_data || %{}, exif_data)

        # Update photo with EXIF data and taken_at if available
        attrs =
          %{exif_data: merged_exif}
          |> maybe_add(:taken_at, exif_data[:taken_at])

        case Portfolio.Photography.update_photo(photo, attrs) do
          {:ok, _updated_photo} ->
            Logger.info("EXIF data extracted and stored",
              photo_id: photo_id,
              fields: Map.keys(exif_data)
            )

            :ok

          {:error, changeset} ->
            Logger.error("Failed to update photo with EXIF data",
              photo_id: photo_id,
              errors: inspect(changeset.errors)
            )

            {:error, changeset}
        end

      {:error, :not_found} ->
        Logger.warning("Photo not found for EXIF update", photo_id: photo_id)
        {:error, :photo_not_found}
    end
  end
end
