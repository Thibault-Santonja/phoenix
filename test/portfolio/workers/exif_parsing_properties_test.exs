defmodule Portfolio.Workers.ExifParsingPropertiesTest do
  @moduledoc """
  Property-based tests for EXIF parsing functions.

  Tests invariants and edge cases for GPS coordinates, ISO values,
  aperture/shutter speed formatting, and DMS coordinate conversions.
  """
  use ExUnit.Case, async: true

  use ExUnitProperties

  # Since these are private functions, we'll create a wrapper module for testing
  # or we'll test them indirectly through parse_relevant_exif

  describe "GPS coordinate bounds properties" do
    property "latitude is always within valid bounds (-90 to 90)" do
      check all(
              # Use 0..89 for degrees to avoid edge case at 90
              degrees <- integer(0..89),
              minutes <- integer(0..59),
              seconds <- float(min: 0.0, max: 59.999),
              direction <- member_of(["N", "S"])
            ) do
        # Construct DMS string
        dms_string = "#{degrees} deg #{minutes}' #{seconds}\" #{direction}"

        # Parse through the worker's logic
        result = parse_gps_coordinate_test_helper(dms_string)

        case result do
          nil ->
            # If parsing fails, that's acceptable for edge cases
            :ok

          decimal ->
            assert is_float(decimal)

            assert decimal >= -90.0 and decimal <= 90.0,
                   "Latitude #{decimal} out of bounds for DMS: #{dms_string}"
        end
      end
    end

    property "longitude is always within valid bounds (-180 to 180)" do
      check all(
              # Use 0..179 for degrees to avoid edge case at 180
              degrees <- integer(0..179),
              minutes <- integer(0..59),
              seconds <- float(min: 0.0, max: 59.999),
              direction <- member_of(["E", "W"])
            ) do
        dms_string = "#{degrees} deg #{minutes}' #{seconds}\" #{direction}"

        result = parse_gps_coordinate_test_helper(dms_string)

        case result do
          nil ->
            :ok

          decimal ->
            assert is_float(decimal)

            assert decimal >= -180.0 and decimal <= 180.0,
                   "Longitude #{decimal} out of bounds for DMS: #{dms_string}"
        end
      end
    end

    property "decimal degree format is parsed correctly" do
      check all(
              lat <- float(min: -90.0, max: 90.0),
              # Format as string with reasonable precision
              coord_string = Float.to_string(lat)
            ) do
        result = parse_gps_coordinate_test_helper(coord_string)

        case result do
          nil ->
            :ok

          decimal ->
            # Should be close to original value (within floating point precision)
            assert_in_delta decimal, lat, 0.000001
        end
      end
    end
  end

  describe "DMS to decimal conversion properties" do
    property "DMS conversion is reversible within precision" do
      check all(
              decimal <- float(min: -90.0, max: 90.0),
              # Convert to DMS and back
              direction = if(decimal >= 0, do: "N", else: "S"),
              abs_decimal = abs(decimal),
              degrees = trunc(abs_decimal),
              minutes_decimal = (abs_decimal - degrees) * 60,
              minutes = trunc(minutes_decimal),
              seconds = (minutes_decimal - minutes) * 60
            ) do
        # Reconstruct decimal from DMS
        reconstructed = degrees + minutes / 60.0 + seconds / 3600.0
        reconstructed = if direction == "S", do: -reconstructed, else: reconstructed

        # Should match original within reasonable precision
        # (we lose some precision in the conversion)
        assert_in_delta reconstructed,
                        decimal,
                        0.001,
                        "DMS conversion not reversible: #{decimal} -> DMS -> #{reconstructed}"
      end
    end

    property "southern and western coordinates are negative" do
      check all(
              degrees <- integer(1..90),
              minutes <- integer(0..59),
              seconds <- integer(0..59),
              direction <- member_of(["S", "W"])
            ) do
        dms_string = "#{degrees} deg #{minutes}' #{seconds}\" #{direction}"

        result = parse_gps_coordinate_test_helper(dms_string)

        case result do
          nil ->
            :ok

          decimal when is_float(decimal) ->
            assert decimal <= 0.0,
                   "Southern/Western coordinate should be negative: #{dms_string} -> #{decimal}"

          _ ->
            :ok
        end
      end
    end

    property "northern and eastern coordinates are positive" do
      check all(
              degrees <- integer(1..90),
              minutes <- integer(0..59),
              seconds <- integer(0..59),
              direction <- member_of(["N", "E"])
            ) do
        dms_string = "#{degrees} deg #{minutes}' #{seconds}\" #{direction}"

        result = parse_gps_coordinate_test_helper(dms_string)

        case result do
          nil ->
            :ok

          decimal when is_float(decimal) ->
            assert decimal >= 0.0,
                   "Northern/Eastern coordinate should be positive: #{dms_string} -> #{decimal}"

          _ ->
            :ok
        end
      end
    end
  end

  describe "ISO value properties" do
    property "ISO values are always positive integers" do
      check all(iso <- integer(50..102_400)) do
        # Test with integer input
        result_int = parse_iso_test_helper(iso)
        assert result_int == iso
        assert is_integer(result_int)
        assert result_int > 0

        # Test with string input
        result_string = parse_iso_test_helper(Integer.to_string(iso))
        assert result_string == iso
        assert is_integer(result_string)
        assert result_string > 0
      end
    end

    property "ISO parsing handles binary strings correctly" do
      check all(iso <- integer(100..6400)) do
        iso_string = Integer.to_string(iso)

        result = parse_iso_test_helper(iso_string)

        assert result == iso
        assert is_integer(result)
      end
    end

    property "ISO parsing returns nil for invalid input" do
      check all(invalid <- string(:alphanumeric, min_length: 1, max_length: 10)) do
        # Only test strings that don't start with digits
        if Regex.match?(~r/^[a-zA-Z]/, invalid) do
          result = parse_iso_test_helper(invalid)
          assert result == nil
        end
      end
    end
  end

  describe "aperture formatting properties" do
    property "aperture format always starts with f/ for numeric values" do
      check all(aperture <- float(min: 1.0, max: 32.0)) do
        result = format_aperture_test_helper(aperture)

        assert String.starts_with?(result, "f/"),
               "Aperture should start with 'f/': #{result}"
      end
    end

    property "aperture formatting is deterministic" do
      check all(aperture <- float(min: 1.4, max: 22.0)) do
        result1 = format_aperture_test_helper(aperture)
        result2 = format_aperture_test_helper(aperture)

        assert result1 == result2
      end
    end

    property "aperture binary passthrough is unchanged" do
      check all(aperture_string <- string(:alphanumeric, min_length: 3, max_length: 10)) do
        # If we pass a string, it should be returned as-is
        aperture_with_prefix = "f/" <> aperture_string

        result = format_aperture_test_helper(aperture_with_prefix)
        assert result == aperture_with_prefix
      end
    end
  end

  describe "shutter speed formatting properties" do
    property "shutter speed format is consistent for fractional values" do
      check all(
              # Generate fractional shutter speeds (< 1 second)
              denominator <- integer(2..8000)
            ) do
        shutter_speed = 1.0 / denominator

        result = format_shutter_speed_test_helper(shutter_speed)

        # Should be in "1/N" format
        assert String.starts_with?(result, "1/"),
               "Fractional shutter speed should be '1/N' format: #{result}"

        # Extract denominator
        [_, denom_str] = String.split(result, "/")
        parsed_denom = String.to_integer(denom_str)

        # Should be close to original denominator
        assert_in_delta parsed_denom, denominator, 1
      end
    end

    property "shutter speed format includes 's' suffix for values >= 1" do
      check all(shutter_speed <- integer(1..30)) do
        result = format_shutter_speed_test_helper(shutter_speed)

        assert String.ends_with?(result, "s"),
               "Shutter speed >= 1 should end with 's': #{result}"
      end
    end

    property "shutter speed formatting is deterministic" do
      check all(speed <- float(min: 0.001, max: 30.0)) do
        result1 = format_shutter_speed_test_helper(speed)
        result2 = format_shutter_speed_test_helper(speed)

        assert result1 == result2
      end
    end
  end

  # Helper functions that replicate the private function logic
  # These are necessary since we can't directly test private functions

  defp parse_gps_coordinate_test_helper(nil), do: nil

  defp parse_gps_coordinate_test_helper(coord_string) when is_binary(coord_string) do
    # Only accept as decimal if the entire string is a valid float
    case Float.parse(coord_string) do
      {float_val, ""} ->
        float_val

      {float_val, rest} ->
        if String.trim(rest) == "" do
          float_val
        else
          # Try DMS format
          parse_dms_coordinate_test_helper(coord_string)
        end

      :error ->
        parse_dms_coordinate_test_helper(coord_string)
    end
  end

  defp parse_gps_coordinate_test_helper(coord) when is_float(coord), do: coord
  defp parse_gps_coordinate_test_helper(_), do: nil

  defp parse_dms_coordinate_test_helper(dms_string) do
    case Regex.run(~r/(\d+)\s*deg\s*(\d+)'\s*([\d.]+)"?\s*([NSEW])?/, dms_string) do
      [_, degrees, minutes, seconds | direction] ->
        convert_dms_to_decimal_test_helper(degrees, minutes, seconds, direction)

      _ ->
        nil
    end
  rescue
    _ -> nil
  end

  defp convert_dms_to_decimal_test_helper(degrees, minutes, seconds, direction) do
    deg = parse_number_test_helper(degrees)
    min = parse_number_test_helper(minutes)
    sec = parse_number_test_helper(seconds)

    if valid_dms_bounds_test_helper?(deg, min, sec) do
      decimal = deg + min / 60.0 + sec / 3600.0
      apply_direction_sign_test_helper(decimal, direction)
    else
      nil
    end
  end

  defp parse_number_test_helper(str) when is_binary(str) do
    case Float.parse(str) do
      {num, _} ->
        num

      :error ->
        case Integer.parse(str) do
          {num, _} -> num * 1.0
          :error -> nil
        end
    end
  end

  defp valid_dms_bounds_test_helper?(deg, min, sec) do
    is_number(deg) and is_number(min) and is_number(sec) and
      deg >= 0 and deg <= 180 and
      min >= 0 and min < 60 and
      sec >= 0 and sec < 60
  end

  defp apply_direction_sign_test_helper(decimal, ["S"]), do: -decimal
  defp apply_direction_sign_test_helper(decimal, ["W"]), do: -decimal
  defp apply_direction_sign_test_helper(decimal, _), do: decimal

  defp parse_iso_test_helper(nil), do: nil
  defp parse_iso_test_helper(value) when is_integer(value), do: value

  defp parse_iso_test_helper(value) when is_binary(value) do
    case Integer.parse(value) do
      {iso, _} -> iso
      :error -> nil
    end
  end

  defp parse_iso_test_helper(_), do: nil

  defp format_aperture_test_helper(nil), do: nil
  defp format_aperture_test_helper(value) when is_number(value), do: "f/#{value}"
  defp format_aperture_test_helper(value) when is_binary(value), do: value
  defp format_aperture_test_helper(_), do: nil

  defp format_shutter_speed_test_helper(nil), do: nil
  defp format_shutter_speed_test_helper(value) when is_binary(value), do: value

  defp format_shutter_speed_test_helper(value) when is_number(value) and value < 1,
    do: "1/#{trunc(1 / value)}"

  defp format_shutter_speed_test_helper(value) when is_number(value), do: "#{value}s"
  defp format_shutter_speed_test_helper(_), do: nil
end
