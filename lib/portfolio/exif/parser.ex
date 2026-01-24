defmodule Portfolio.Exif.Parser do
  @moduledoc """
  Pure functions for parsing and formatting EXIF metadata.

  This module contains all the parsing logic extracted from ExifExtractionWorker
  to enable thorough unit testing without I/O dependencies.

  ## Supported EXIF Fields

  - Camera make/model
  - Lens information
  - Exposure settings (aperture, shutter speed, ISO)
  - Date/time captured
  - GPS coordinates (DMS and decimal formats)
  - Image dimensions and orientation
  """

  @doc """
  Parses raw EXIF data map and extracts relevant photography metadata.

  ## Examples

      iex> Parser.parse_relevant_exif(%{"Make" => "Canon", "Model" => "EOS R5"})
      %{camera_make: "Canon", camera_model: "EOS R5", camera: "Canon EOS R5"}
  """
  @spec parse_relevant_exif(map()) :: map()
  def parse_relevant_exif(raw_exif) when is_map(raw_exif) do
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

  @doc """
  Adds a key-value pair to a map if the value is not nil or empty string.
  """
  @spec maybe_add(map(), atom(), any()) :: map()
  def maybe_add(map, _key, nil), do: map
  def maybe_add(map, _key, ""), do: map
  def maybe_add(map, key, value), do: Map.put(map, key, value)

  @doc """
  Builds a camera name from make and model, avoiding duplication.

  ## Examples

      iex> Parser.build_camera_name("Canon", "EOS R5")
      "Canon EOS R5"

      iex> Parser.build_camera_name("Canon", "Canon EOS R5")
      "Canon EOS R5"

      iex> Parser.build_camera_name(nil, "EOS R5")
      "EOS R5"
  """
  @spec build_camera_name(String.t() | nil, String.t() | nil) :: String.t() | nil
  def build_camera_name(nil, nil), do: nil
  def build_camera_name(make, nil), do: make
  def build_camera_name(nil, model), do: model

  def build_camera_name(make, model) do
    if String.contains?(model, make) do
      model
    else
      "#{make} #{model}"
    end
  end

  @doc """
  Formats an aperture value to f-stop notation.

  ## Examples

      iex> Parser.format_aperture(2.8)
      "f/2.8"

      iex> Parser.format_aperture("f/1.4")
      "f/1.4"

      iex> Parser.format_aperture(nil)
      nil
  """
  @spec format_aperture(any()) :: String.t() | nil
  def format_aperture(nil), do: nil
  def format_aperture(value) when is_number(value), do: "f/#{value}"
  def format_aperture(value) when is_binary(value), do: value
  def format_aperture(_), do: nil

  @doc """
  Formats a shutter speed value.

  ## Examples

      iex> Parser.format_shutter_speed(0.001)
      "1/1000"

      iex> Parser.format_shutter_speed(2)
      "2s"

      iex> Parser.format_shutter_speed("1/250")
      "1/250"
  """
  @spec format_shutter_speed(any()) :: String.t() | nil
  def format_shutter_speed(nil), do: nil
  def format_shutter_speed(value) when is_binary(value), do: value

  def format_shutter_speed(value) when is_number(value) and value < 1,
    do: "1/#{trunc(1 / value)}"

  def format_shutter_speed(value) when is_number(value), do: "#{value}s"
  def format_shutter_speed(_), do: nil

  @doc """
  Parses an ISO value to integer.

  ## Examples

      iex> Parser.parse_iso(100)
      100

      iex> Parser.parse_iso("400")
      400

      iex> Parser.parse_iso(nil)
      nil
  """
  @spec parse_iso(any()) :: integer() | nil
  def parse_iso(nil), do: nil
  def parse_iso(value) when is_integer(value), do: value

  def parse_iso(value) when is_binary(value) do
    case Integer.parse(value) do
      {iso, _} -> iso
      :error -> nil
    end
  end

  def parse_iso(_), do: nil

  @doc """
  Parses an EXIF datetime string to DateTime.

  EXIF format: "YYYY:MM:DD HH:MM:SS"

  ## Examples

      iex> Parser.parse_datetime("2024:01:15 14:30:00")
      ~U[2024-01-15 14:30:00Z]

      iex> Parser.parse_datetime(nil)
      nil
  """
  @spec parse_datetime(String.t() | nil) :: DateTime.t() | nil
  def parse_datetime(nil), do: nil

  def parse_datetime(datetime_string) when is_binary(datetime_string) do
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

  @doc """
  Parses GPS coordinates from various formats.

  Supports:
  - Decimal degrees: "48.858200"
  - DMS format: "48 deg 51' 29.52\" N"

  ## Examples

      iex> Parser.parse_gps_coordinate("48.8582")
      48.8582

      iex> Parser.parse_gps_coordinate("48 deg 51' 29.52\" N")
      48.8582

      iex> Parser.parse_gps_coordinate(48.8582)
      48.8582
  """
  @spec parse_gps_coordinate(String.t() | float() | nil) :: float() | nil
  def parse_gps_coordinate(nil), do: nil

  def parse_gps_coordinate(coord_string) when is_binary(coord_string) do
    case Float.parse(coord_string) do
      {float_val, ""} ->
        # Pure decimal format
        float_val

      {float_val, rest} when byte_size(rest) <= 1 ->
        # Decimal with optional trailing space or similar
        float_val

      {_float_val, _rest} ->
        # Has trailing content - try DMS format
        parse_dms_coordinate(coord_string)

      :error ->
        parse_dms_coordinate(coord_string)
    end
  end

  def parse_gps_coordinate(coord) when is_float(coord), do: coord
  def parse_gps_coordinate(coord) when is_integer(coord), do: coord * 1.0
  def parse_gps_coordinate(_), do: nil

  @doc """
  Parses DMS (degrees, minutes, seconds) coordinate format.

  Format: "48 deg 51' 29.52\" N"

  ## Examples

      iex> Parser.parse_dms_coordinate("48 deg 51' 29.52\" N")
      48.8582
  """
  @spec parse_dms_coordinate(String.t()) :: float() | nil
  def parse_dms_coordinate(dms_string) do
    case Regex.run(~r/(\d+)\s*deg\s*(\d+)'\s*([\d.]+)"?\s*([NSEW])?/, dms_string) do
      [_, degrees, minutes, seconds | direction] ->
        convert_dms_to_decimal(degrees, minutes, seconds, direction)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  @doc """
  Converts DMS components to decimal degrees.
  """
  @spec convert_dms_to_decimal(String.t(), String.t(), String.t(), [String.t()]) :: float() | nil
  def convert_dms_to_decimal(degrees, minutes, seconds, direction) do
    deg = parse_number(degrees)
    min = parse_number(minutes)
    sec = parse_number(seconds)

    if valid_dms_bounds?(deg, min, sec) do
      decimal = deg + min / 60.0 + sec / 3600.0
      apply_direction_sign(decimal, direction)
    else
      nil
    end
  end

  @doc """
  Applies sign based on cardinal direction.
  """
  @spec apply_direction_sign(float(), [String.t()]) :: float()
  def apply_direction_sign(decimal, ["S"]), do: -decimal
  def apply_direction_sign(decimal, ["W"]), do: -decimal
  def apply_direction_sign(decimal, _), do: decimal

  @doc """
  Parses a string number to float.
  """
  @spec parse_number(String.t()) :: float() | nil
  def parse_number(str) do
    case Float.parse(str) do
      {num, _} -> num
      :error -> String.to_integer(str) * 1.0
    end
  rescue
    _ -> nil
  end

  @doc """
  Validates that DMS values are within valid bounds.
  """
  @spec valid_dms_bounds?(float() | nil, float() | nil, float() | nil) :: boolean()
  def valid_dms_bounds?(deg, min, sec) do
    is_number(deg) and is_number(min) and is_number(sec) and
      deg >= 0 and deg <= 180 and
      min >= 0 and min < 60 and
      sec >= 0 and sec < 60
  end
end
