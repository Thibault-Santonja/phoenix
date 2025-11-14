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

  @spec extract_and_update_exif(Photography.Photo.t()) ::
          :ok | {:cancel, String.t()} | {:error, term()}
  defp extract_and_update_exif(photo) do
    file_path = build_absolute_path(photo.file_path)

    case File.exists?(file_path) do
      true ->
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

      false ->
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

  @spec extract_exif_data(String.t()) :: {:ok, map()} | {:error, term()}
  defp extract_exif_data(file_path) do
    # Use Exiftool.execute with -json flag for structured output
    case Exiftool.execute(["-json", file_path]) do
      {:ok, json_string} when is_binary(json_string) ->
        case Jason.decode(json_string) do
          {:ok, [exif_map | _]} when is_map(exif_map) ->
            parsed = parse_relevant_exif(exif_map)
            {:ok, parsed}

          {:ok, _} ->
            {:error, :invalid_exif_format}

          {:error, reason} ->
            {:error, reason}
        end

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

  @spec parse_relevant_exif(map()) :: map()
  defp parse_relevant_exif(raw_exif) do
    # Extract only relevant EXIF fields for photography
    %{}
    |> maybe_add(:camera_make, raw_exif["Make"])
    |> maybe_add(:camera_model, raw_exif["Model"])
    |> maybe_add(:camera, build_camera_name(raw_exif["Make"], raw_exif["Model"]))
    |> maybe_add(:lens, raw_exif["LensModel"] || raw_exif["Lens"])
    |> maybe_add(:focal_length, raw_exif["FocalLength"])
    |> maybe_add(:aperture, format_aperture(raw_exif["FNumber"] || raw_exif["ApertureValue"]))
    |> maybe_add(
      :shutter_speed,
      format_shutter_speed(raw_exif["ExposureTime"] || raw_exif["ShutterSpeedValue"])
    )
    |> maybe_add(:iso, parse_iso(raw_exif["ISO"]))
    |> maybe_add(
      :captured_at,
      parse_datetime(raw_exif["DateTimeOriginal"] || raw_exif["CreateDate"])
    )
    |> maybe_add(:width, raw_exif["ImageWidth"])
    |> maybe_add(:height, raw_exif["ImageHeight"])
    |> maybe_add(:orientation, raw_exif["Orientation"])
    |> maybe_add(:flash, raw_exif["Flash"])
    |> maybe_add(:white_balance, raw_exif["WhiteBalance"])
    |> maybe_add(:gps_latitude, parse_gps_coordinate(raw_exif["GPSLatitude"]))
    |> maybe_add(:gps_longitude, parse_gps_coordinate(raw_exif["GPSLongitude"]))
  end

  @spec maybe_add(map(), atom(), any()) :: map()
  defp maybe_add(map, _key, nil), do: map
  defp maybe_add(map, _key, ""), do: map
  defp maybe_add(map, key, value), do: Map.put(map, key, value)

  @spec build_camera_name(String.t() | nil, String.t() | nil) :: String.t() | nil
  defp build_camera_name(nil, nil), do: nil
  defp build_camera_name(make, nil), do: make
  defp build_camera_name(nil, model), do: model

  defp build_camera_name(make, model) do
    # Avoid duplication if model already contains make
    if String.contains?(model, make) do
      model
    else
      "#{make} #{model}"
    end
  end

  @spec format_aperture(any()) :: String.t() | nil
  defp format_aperture(nil), do: nil
  defp format_aperture(value) when is_number(value), do: "f/#{value}"
  defp format_aperture(value) when is_binary(value), do: value
  defp format_aperture(_), do: nil

  @spec format_shutter_speed(any()) :: String.t() | nil
  defp format_shutter_speed(nil), do: nil
  defp format_shutter_speed(value) when is_binary(value), do: value

  defp format_shutter_speed(value) when is_number(value) and value < 1,
    do: "1/#{trunc(1 / value)}"

  defp format_shutter_speed(value) when is_number(value), do: "#{value}s"
  defp format_shutter_speed(_), do: nil

  @spec parse_iso(any()) :: integer() | nil
  defp parse_iso(nil), do: nil
  defp parse_iso(value) when is_integer(value), do: value

  defp parse_iso(value) when is_binary(value) do
    case Integer.parse(value) do
      {iso, _} -> iso
      :error -> nil
    end
  end

  defp parse_iso(_), do: nil

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

  @spec parse_gps_coordinate(String.t() | nil) :: float() | nil
  defp parse_gps_coordinate(nil), do: nil

  defp parse_gps_coordinate(coord_string) when is_binary(coord_string) do
    # GPS format examples:
    # "48 deg 51' 29.52\" N" or "48.858200" (decimal degrees)
    case Float.parse(coord_string) do
      {float_val, _} ->
        float_val

      :error ->
        # Try parsing DMS format (degrees, minutes, seconds)
        parse_dms_coordinate(coord_string)
    end
  end

  defp parse_gps_coordinate(coord) when is_float(coord), do: coord
  defp parse_gps_coordinate(_), do: nil

  @spec parse_dms_coordinate(String.t()) :: float() | nil
  defp parse_dms_coordinate(dms_string) do
    # Parse "48 deg 51' 29.52\" N" format
    # Simple regex to extract degrees, minutes, seconds
    case Regex.run(~r/(\d+)\s*deg\s*(\d+)'\s*([\d.]+)"?\s*([NSEW])?/, dms_string) do
      [_, degrees, minutes, seconds | direction] ->
        deg = String.to_float(degrees)
        min = String.to_float(minutes)
        sec = String.to_float(seconds)

        decimal = deg + min / 60.0 + sec / 3600.0

        # Apply negative for South and West
        case direction do
          ["S"] -> -decimal
          ["W"] -> -decimal
          _ -> decimal
        end

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @spec update_photo_with_exif(Photography.Photo.t(), map()) :: :ok | {:error, term()}
  defp update_photo_with_exif(photo, exif_data) do
    # Merge new EXIF data with existing exif_data JSON field
    merged_exif = Map.merge(photo.exif_data || %{}, exif_data)

    # Build update attributes for dedicated columns
    attrs =
      %{exif_data: merged_exif}
      |> maybe_add(:captured_at, exif_data[:captured_at])
      |> maybe_add(:camera, exif_data[:camera])
      |> maybe_add(:lens, exif_data[:lens])
      |> maybe_add(:iso, exif_data[:iso])
      |> maybe_add(:aperture, exif_data[:aperture])
      |> maybe_add(:focal_length, exif_data[:focal_length])
      |> maybe_add(:shutter_speed, exif_data[:shutter_speed])
      |> maybe_add(:gps_latitude, exif_data[:gps_latitude])
      |> maybe_add(:gps_longitude, exif_data[:gps_longitude])

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
