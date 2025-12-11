defmodule Portfolio.Exif.ParserTest do
  use ExUnit.Case, async: true

  alias Portfolio.Exif.Parser

  describe "parse_relevant_exif/1" do
    test "parses complete EXIF data" do
      raw_exif = %{
        "Make" => "Canon",
        "Model" => "EOS R5",
        "LensModel" => "RF 24-70mm F2.8 L IS USM",
        "FocalLength" => "50mm",
        "FNumber" => 2.8,
        "ExposureTime" => 0.004,
        "ISO" => 100,
        "DateTimeOriginal" => "2024:01:15 14:30:00",
        "ImageWidth" => 8192,
        "ImageHeight" => 5464,
        "Orientation" => "Horizontal",
        "Flash" => "Off",
        "WhiteBalance" => "Auto",
        "GPSLatitude" => "48.8582",
        "GPSLongitude" => "2.2945"
      }

      result = Parser.parse_relevant_exif(raw_exif)

      assert result[:camera_make] == "Canon"
      assert result[:camera_model] == "EOS R5"
      assert result[:camera] == "Canon EOS R5"
      assert result[:lens] == "RF 24-70mm F2.8 L IS USM"
      assert result[:focal_length] == "50mm"
      assert result[:aperture] == "f/2.8"
      assert result[:shutter_speed] == "1/250"
      assert result[:iso] == 100
      assert result[:width] == 8192
      assert result[:height] == 5464
      assert result[:orientation] == "Horizontal"
      assert result[:flash] == "Off"
      assert result[:white_balance] == "Auto"
      assert result[:gps_latitude] == 48.8582
      assert result[:gps_longitude] == 2.2945
    end

    test "handles empty EXIF data" do
      result = Parser.parse_relevant_exif(%{})
      assert result == %{}
    end

    test "handles partial EXIF data" do
      raw_exif = %{
        "Make" => "Sony",
        "ISO" => 400
      }

      result = Parser.parse_relevant_exif(raw_exif)

      assert result[:camera_make] == "Sony"
      assert result[:camera] == "Sony"
      assert result[:iso] == 400
      refute Map.has_key?(result, :lens)
      refute Map.has_key?(result, :aperture)
    end

    test "uses Lens field when LensModel is not available" do
      raw_exif = %{"Lens" => "24-70mm"}

      result = Parser.parse_relevant_exif(raw_exif)

      assert result[:lens] == "24-70mm"
    end

    test "uses ApertureValue when FNumber is not available" do
      raw_exif = %{"ApertureValue" => 4.0}

      result = Parser.parse_relevant_exif(raw_exif)

      assert result[:aperture] == "f/4.0"
    end

    test "uses ShutterSpeedValue when ExposureTime is not available" do
      raw_exif = %{"ShutterSpeedValue" => "1/500"}

      result = Parser.parse_relevant_exif(raw_exif)

      assert result[:shutter_speed] == "1/500"
    end

    test "uses CreateDate when DateTimeOriginal is not available" do
      raw_exif = %{"CreateDate" => "2024:06:20 10:00:00"}

      result = Parser.parse_relevant_exif(raw_exif)

      assert result[:captured_at] == ~U[2024-06-20 10:00:00Z]
    end
  end

  describe "maybe_add/3" do
    test "adds value when not nil" do
      result = Parser.maybe_add(%{}, :key, "value")
      assert result == %{key: "value"}
    end

    test "does not add nil values" do
      result = Parser.maybe_add(%{existing: true}, :key, nil)
      assert result == %{existing: true}
    end

    test "does not add empty string values" do
      result = Parser.maybe_add(%{}, :key, "")
      assert result == %{}
    end

    test "preserves existing map entries" do
      result = Parser.maybe_add(%{a: 1, b: 2}, :c, 3)
      assert result == %{a: 1, b: 2, c: 3}
    end
  end

  describe "build_camera_name/2" do
    test "combines make and model" do
      assert Parser.build_camera_name("Canon", "EOS R5") == "Canon EOS R5"
    end

    test "avoids duplication when model contains make" do
      assert Parser.build_camera_name("Canon", "Canon EOS R5") == "Canon EOS R5"
    end

    test "returns make when model is nil" do
      assert Parser.build_camera_name("Canon", nil) == "Canon"
    end

    test "returns model when make is nil" do
      assert Parser.build_camera_name(nil, "EOS R5") == "EOS R5"
    end

    test "returns nil when both are nil" do
      assert Parser.build_camera_name(nil, nil) == nil
    end
  end

  describe "format_aperture/1" do
    test "formats number as f-stop" do
      assert Parser.format_aperture(2.8) == "f/2.8"
      assert Parser.format_aperture(1.4) == "f/1.4"
      assert Parser.format_aperture(16) == "f/16"
    end

    test "passes through string values" do
      assert Parser.format_aperture("f/2.8") == "f/2.8"
      assert Parser.format_aperture("f/11") == "f/11"
    end

    test "returns nil for nil input" do
      assert Parser.format_aperture(nil) == nil
    end

    test "returns nil for invalid input" do
      assert Parser.format_aperture(:invalid) == nil
      assert Parser.format_aperture([]) == nil
    end
  end

  describe "format_shutter_speed/1" do
    test "formats fractions for speeds less than 1 second" do
      assert Parser.format_shutter_speed(0.001) == "1/1000"
      assert Parser.format_shutter_speed(0.004) == "1/250"
      assert Parser.format_shutter_speed(0.0166) == "1/60"
    end

    test "formats seconds for speeds >= 1 second" do
      assert Parser.format_shutter_speed(1) == "1s"
      assert Parser.format_shutter_speed(2) == "2s"
      assert Parser.format_shutter_speed(30) == "30s"
    end

    test "passes through string values" do
      assert Parser.format_shutter_speed("1/250") == "1/250"
      assert Parser.format_shutter_speed("2s") == "2s"
    end

    test "returns nil for nil input" do
      assert Parser.format_shutter_speed(nil) == nil
    end

    test "returns nil for invalid input" do
      assert Parser.format_shutter_speed(:invalid) == nil
    end
  end

  describe "parse_iso/1" do
    test "returns integer for integer input" do
      assert Parser.parse_iso(100) == 100
      assert Parser.parse_iso(6400) == 6400
    end

    test "parses string to integer" do
      assert Parser.parse_iso("100") == 100
      assert Parser.parse_iso("3200") == 3200
    end

    test "handles string with trailing content" do
      assert Parser.parse_iso("400 ") == 400
    end

    test "returns nil for nil input" do
      assert Parser.parse_iso(nil) == nil
    end

    test "returns nil for invalid string" do
      assert Parser.parse_iso("invalid") == nil
    end

    test "returns nil for other types" do
      assert Parser.parse_iso(:atom) == nil
      assert Parser.parse_iso([100]) == nil
    end
  end

  describe "parse_datetime/1" do
    test "parses EXIF datetime format" do
      result = Parser.parse_datetime("2024:01:15 14:30:00")
      assert result == ~U[2024-01-15 14:30:00Z]
    end

    test "parses datetime with different times" do
      assert Parser.parse_datetime("2023:12:25 00:00:00") == ~U[2023-12-25 00:00:00Z]
      assert Parser.parse_datetime("2024:06:15 23:59:59") == ~U[2024-06-15 23:59:59Z]
    end

    test "returns nil for nil input" do
      assert Parser.parse_datetime(nil) == nil
    end

    test "returns nil for invalid format" do
      # Note: ISO format with dashes also parses successfully
      assert Parser.parse_datetime("invalid") == nil
      assert Parser.parse_datetime("2024:01:15") == nil
    end
  end

  describe "parse_gps_coordinate/1" do
    test "parses decimal string" do
      assert Parser.parse_gps_coordinate("48.8582") == 48.8582
      assert Parser.parse_gps_coordinate("2.2945") == 2.2945
      assert Parser.parse_gps_coordinate("-33.8688") == -33.8688
    end

    test "passes through float values" do
      assert Parser.parse_gps_coordinate(48.8582) == 48.8582
    end

    test "converts integer to float" do
      assert Parser.parse_gps_coordinate(48) == 48.0
    end

    test "parses DMS format with North direction" do
      result = Parser.parse_gps_coordinate("48 deg 51' 29.52\" N")
      assert_in_delta result, 48.8582, 0.001
    end

    test "parses DMS format with South direction" do
      result = Parser.parse_gps_coordinate("33 deg 52' 7.68\" S")
      assert result < 0
      assert_in_delta result, -33.8688, 0.001
    end

    test "parses DMS format with East direction" do
      result = Parser.parse_gps_coordinate("2 deg 17' 40.20\" E")
      assert result > 0
      assert_in_delta result, 2.2945, 0.001
    end

    test "parses DMS format with West direction" do
      result = Parser.parse_gps_coordinate("122 deg 25' 9.12\" W")
      assert result < 0
      assert_in_delta result, -122.4192, 0.001
    end

    test "returns nil for nil input" do
      assert Parser.parse_gps_coordinate(nil) == nil
    end

    test "returns nil for invalid input" do
      assert Parser.parse_gps_coordinate(:invalid) == nil
    end
  end

  describe "parse_dms_coordinate/1" do
    test "parses standard DMS format" do
      result = Parser.parse_dms_coordinate("48 deg 51' 29.52\" N")
      assert_in_delta result, 48.8582, 0.0001
    end

    test "parses DMS without direction" do
      result = Parser.parse_dms_coordinate("48 deg 51' 29.52\"")
      assert_in_delta result, 48.8582, 0.0001
    end

    test "returns nil for invalid format" do
      assert Parser.parse_dms_coordinate("invalid") == nil
      assert Parser.parse_dms_coordinate("48.8582") == nil
    end
  end

  describe "convert_dms_to_decimal/4" do
    test "converts valid DMS to decimal" do
      result = Parser.convert_dms_to_decimal("48", "51", "29.52", [])
      assert_in_delta result, 48.8582, 0.0001
    end

    test "applies South direction" do
      result = Parser.convert_dms_to_decimal("33", "52", "7.68", ["S"])
      assert result < 0
    end

    test "applies West direction" do
      result = Parser.convert_dms_to_decimal("122", "25", "9.12", ["W"])
      assert result < 0
    end

    test "applies North direction (positive)" do
      result = Parser.convert_dms_to_decimal("48", "51", "29.52", ["N"])
      assert result > 0
    end

    test "applies East direction (positive)" do
      result = Parser.convert_dms_to_decimal("2", "17", "40.20", ["E"])
      assert result > 0
    end
  end

  describe "apply_direction_sign/2" do
    test "negates for South" do
      assert Parser.apply_direction_sign(48.0, ["S"]) == -48.0
    end

    test "negates for West" do
      assert Parser.apply_direction_sign(122.0, ["W"]) == -122.0
    end

    test "keeps positive for North" do
      assert Parser.apply_direction_sign(48.0, ["N"]) == 48.0
    end

    test "keeps positive for East" do
      assert Parser.apply_direction_sign(2.0, ["E"]) == 2.0
    end

    test "keeps positive for empty list" do
      assert Parser.apply_direction_sign(48.0, []) == 48.0
    end
  end

  describe "parse_number/1" do
    test "parses float string" do
      assert Parser.parse_number("48.5") == 48.5
    end

    test "parses integer string" do
      assert Parser.parse_number("48") == 48.0
    end

    test "returns nil for invalid input" do
      assert Parser.parse_number("invalid") == nil
    end
  end

  describe "valid_dms_bounds?/3" do
    test "returns true for valid bounds" do
      assert Parser.valid_dms_bounds?(48.0, 51.0, 29.52)
      assert Parser.valid_dms_bounds?(0.0, 0.0, 0.0)
      assert Parser.valid_dms_bounds?(180.0, 59.0, 59.99)
    end

    test "returns false for nil values" do
      refute Parser.valid_dms_bounds?(nil, 51.0, 29.52)
      refute Parser.valid_dms_bounds?(48.0, nil, 29.52)
      refute Parser.valid_dms_bounds?(48.0, 51.0, nil)
    end

    test "returns false for out of range degrees" do
      refute Parser.valid_dms_bounds?(181.0, 51.0, 29.52)
      refute Parser.valid_dms_bounds?(-1.0, 51.0, 29.52)
    end

    test "returns false for out of range minutes" do
      refute Parser.valid_dms_bounds?(48.0, 60.0, 29.52)
      refute Parser.valid_dms_bounds?(48.0, -1.0, 29.52)
    end

    test "returns false for out of range seconds" do
      refute Parser.valid_dms_bounds?(48.0, 51.0, 60.0)
      refute Parser.valid_dms_bounds?(48.0, 51.0, -1.0)
    end
  end
end
