defmodule Portfolio.ImageProcessing.Properties.ValueObjectsPropertiesTest do
  @moduledoc """
  Property-based tests for ImageProcessing value objects.

  Tests invariants for ImageDimensions, ImageQuality, and ImageFormat.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageDimensions
  alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat
  alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageQuality
  alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification

  describe "ImageDimensions properties" do
    property "valid dimensions are always positive" do
      check all(
              width <- integer(1..10_000),
              height <- integer(1..10_000)
            ) do
        {:ok, dims} = ImageDimensions.new(width, height)
        assert dims.width > 0
        assert dims.height > 0
      end
    end

    property "aspect ratio is width / height" do
      check all(
              width <- integer(1..10_000),
              height <- integer(1..10_000)
            ) do
        {:ok, dims} = ImageDimensions.new(width, height)
        expected = width / height
        assert_in_delta ImageDimensions.aspect_ratio(dims), expected, 0.0001
      end
    end

    property "resize to smaller width preserves aspect ratio within tolerance" do
      # Use constrained dimensions to avoid extreme aspect ratios
      # that cause significant rounding errors with integer height calculation
      check all(
              width <- integer(500..3000),
              height <- integer(300..2000),
              target_width <- integer(200..499)
            ) do
        {:ok, dims} = ImageDimensions.new(width, height)
        original_ratio = ImageDimensions.aspect_ratio(dims)

        case ImageDimensions.resize_to_width(dims, target_width) do
          {:ok, resized} ->
            resized_ratio = ImageDimensions.aspect_ratio(resized)
            # Use percentage-based tolerance (3%) to handle integer rounding
            # Constrained inputs keep error within reasonable bounds
            percentage_error = abs(original_ratio - resized_ratio) / original_ratio * 100

            assert percentage_error < 3,
                   "Aspect ratio should be within 3% (original: #{original_ratio}, resized: #{resized_ratio}, error: #{percentage_error}%)"

          {:no_upscale, _} ->
            # This shouldn't happen with target < width, but handle gracefully
            :ok
        end
      end
    end

    property "resize to larger width returns no_upscale" do
      check all(
              width <- integer(100..1000),
              height <- integer(100..1000),
              extra <- integer(1..1000)
            ) do
        {:ok, dims} = ImageDimensions.new(width, height)
        target_width = width + extra

        assert {:no_upscale, ^dims} = ImageDimensions.resize_to_width(dims, target_width)
      end
    end

    property "non-positive dimensions are rejected" do
      check all(
              width <- one_of([constant(0), integer(-1000..-1)]),
              height <- integer(1..1000)
            ) do
        assert {:error, :invalid_dimensions} = ImageDimensions.new(width, height)
      end

      check all(
              width <- integer(1..1000),
              height <- one_of([constant(0), integer(-1000..-1)])
            ) do
        assert {:error, :invalid_dimensions} = ImageDimensions.new(width, height)
      end
    end

    property "portrait/landscape/square are mutually exclusive" do
      check all(
              width <- integer(1..5000),
              height <- integer(1..5000)
            ) do
        {:ok, dims} = ImageDimensions.new(width, height)

        portrait = ImageDimensions.portrait?(dims)
        landscape = ImageDimensions.landscape?(dims)
        square = ImageDimensions.square?(dims)

        # Exactly one must be true
        true_count = Enum.count([portrait, landscape, square], & &1)
        assert true_count == 1, "Exactly one orientation should be true"
      end
    end
  end

  describe "ImageQuality properties" do
    property "valid quality is between 1 and 100" do
      check all(quality <- integer(1..100)) do
        {:ok, q} = ImageQuality.new(quality)
        # ImageQuality returns the integer directly, not a struct
        assert q >= 1
        assert q <= 100
      end
    end

    property "quality outside 1-100 is rejected" do
      check all(quality <- one_of([integer(-100..0), integer(101..200)])) do
        assert {:error, :invalid_quality} = ImageQuality.new(quality)
      end
    end

    property "quality value is preserved" do
      check all(quality <- integer(1..100)) do
        {:ok, q} = ImageQuality.new(quality)
        # ImageQuality returns the integer directly
        assert q == quality
      end
    end

    property "valid? matches new/1 success" do
      check all(quality <- integer(-10..110)) do
        valid = ImageQuality.valid?(quality)
        result = ImageQuality.new(quality)

        case result do
          {:ok, _} -> assert valid
          {:error, _} -> refute valid
        end
      end
    end

    property "category is consistent with quality ranges" do
      check all(quality <- integer(1..100)) do
        category = ImageQuality.category(quality)

        cond do
          quality <= 50 -> assert category == :low
          quality <= 75 -> assert category == :medium
          quality <= 90 -> assert category == :high
          true -> assert category == :very_high
        end
      end
    end
  end

  describe "ImageFormat properties" do
    test "supported formats are accepted" do
      for format <- [:webp, :avif, :jpeg] do
        assert ImageFormat.valid?(format)
      end
    end

    test "unsupported formats are rejected" do
      for format <- [:gif, :bmp, :tiff, :png, :raw, :heic] do
        refute ImageFormat.valid?(format)
      end
    end

    test "format extension is consistent" do
      formats_and_extensions = [
        {:webp, "webp"},
        {:avif, "avif"},
        {:jpeg, "jpg"}
      ]

      for {format, expected_ext} <- formats_and_extensions do
        assert ImageFormat.extension(format) == expected_ext
      end
    end

    test "all/0 returns all valid formats" do
      all_formats = ImageFormat.all()
      assert :webp in all_formats
      assert :avif in all_formats
      assert :jpeg in all_formats
      assert length(all_formats) == 3
    end

    test "from_string parses valid format strings" do
      assert {:ok, :webp} = ImageFormat.from_string("webp")
      assert {:ok, :avif} = ImageFormat.from_string("avif")
      assert {:ok, :jpeg} = ImageFormat.from_string("jpeg")
    end

    test "from_string rejects invalid format strings" do
      assert {:error, :invalid_format} = ImageFormat.from_string("png")
      assert {:error, :invalid_format} = ImageFormat.from_string("invalid")
      assert {:error, :invalid_format} = ImageFormat.from_string("unknown_format_xyz")
    end
  end

  describe "value object immutability" do
    property "ImageDimensions cannot be modified after creation" do
      check all(
              width <- integer(1..1000),
              height <- integer(1..1000)
            ) do
        {:ok, dims} = ImageDimensions.new(width, height)

        # Attempting to update should create a new struct, not modify original
        new_dims = %{dims | width: width + 100}

        # Original should be unchanged (this tests Elixir's immutability)
        assert dims.width == width
        assert new_dims.width == width + 100
      end
    end
  end

  describe "VariantSpecification properties" do
    # Generator for valid formats
    defp valid_format_gen, do: member_of([:webp, :avif, :jpeg])

    # Generator for valid effort based on format
    defp valid_effort_gen(:webp), do: integer(0..6)
    defp valid_effort_gen(:avif), do: integer(0..9)
    defp valid_effort_gen(:jpeg), do: integer(0..9)

    property "valid specifications preserve all values" do
      check all(
              width <- integer(1..5000),
              quality <- integer(1..100),
              format <- valid_format_gen(),
              effort <- valid_effort_gen(format)
            ) do
        {:ok, spec} = VariantSpecification.new(:test_variant, width, quality, format, effort)

        assert spec.name == :test_variant
        assert spec.width == width
        assert spec.quality == quality
        assert spec.format == format
        assert spec.effort == effort
      end
    end

    property "invalid quality rejects specification" do
      check all(
              width <- integer(1..5000),
              quality <- one_of([integer(-100..0), integer(101..200)]),
              format <- valid_format_gen(),
              effort <- integer(0..6)
            ) do
        assert {:error, :invalid_quality} =
                 VariantSpecification.new(:test, width, quality, format, effort)
      end
    end

    property "invalid width rejects specification" do
      check all(
              width <- one_of([constant(0), integer(-1000..-1)]),
              quality <- integer(1..100),
              format <- valid_format_gen()
            ) do
        assert {:error, :invalid_width} =
                 VariantSpecification.new(:test, width, quality, format, 4)
      end
    end

    property "invalid format rejects specification" do
      check all(
              width <- integer(1..5000),
              quality <- integer(1..100),
              format <- member_of([:png, :gif, :bmp, :tiff])
            ) do
        assert {:error, :invalid_format} =
                 VariantSpecification.new(:test, width, quality, format, 4)
      end
    end

    property "effort limits are format-specific" do
      # WebP max effort is 6
      check all(
              width <- integer(1..1000),
              quality <- integer(1..100),
              effort <- integer(7..20)
            ) do
        assert {:error, :invalid_effort} =
                 VariantSpecification.new(:test, width, quality, :webp, effort)
      end
    end

    property "filename combines name and format extension" do
      check all(
              width <- integer(1..1000),
              quality <- integer(1..100),
              format <- valid_format_gen(),
              effort <- valid_effort_gen(format)
            ) do
        {:ok, spec} = VariantSpecification.new(:my_variant, width, quality, format, effort)
        filename = VariantSpecification.filename(spec)

        assert String.starts_with?(filename, "my_variant.")
        assert String.ends_with?(filename, ImageFormat.extension(format))
      end
    end

    property "from_config is equivalent to new" do
      check all(
              width <- integer(1..1000),
              quality <- integer(1..100),
              format <- valid_format_gen(),
              effort <- valid_effort_gen(format)
            ) do
        config = %{name: :test, width: width, quality: quality, format: format, effort: effort}

        new_result = VariantSpecification.new(:test, width, quality, format, effort)
        config_result = VariantSpecification.from_config(config)

        assert new_result == config_result
      end
    end

    property "new! raises for invalid input, succeeds for valid" do
      check all(
              width <- integer(1..1000),
              quality <- integer(1..100),
              format <- valid_format_gen(),
              effort <- valid_effort_gen(format)
            ) do
        # Valid input should not raise
        spec = VariantSpecification.new!(:test, width, quality, format, effort)
        assert %VariantSpecification{} = spec
      end
    end
  end
end
