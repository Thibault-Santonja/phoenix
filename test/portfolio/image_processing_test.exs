defmodule Portfolio.ImageProcessingTest do
  @moduledoc """
  Tests for ImageProcessing public API.

  Tests cover:
  - Delegation to ImageProcessingService
  - Configuration access via ImageConfig
  - File extension mapping
  """
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing

  describe "variants/0" do
    test "returns all configured variants" do
      variants = ImageProcessing.variants()

      assert is_map(variants)
      assert Map.has_key?(variants, :thumbnail)
      assert Map.has_key?(variants, :small)
      assert Map.has_key?(variants, :medium)
      assert Map.has_key?(variants, :large)
    end

    test "each variant has required configuration keys" do
      variants = ImageProcessing.variants()

      Enum.each(variants, fn {_name, config} ->
        assert Map.has_key?(config, :width)
        assert Map.has_key?(config, :quality)
        assert Map.has_key?(config, :format)
        assert Map.has_key?(config, :effort)
      end)
    end

    test "thumbnail variant has correct configuration" do
      variants = ImageProcessing.variants()
      thumbnail = variants[:thumbnail]

      assert thumbnail.width == 400
      assert thumbnail.quality == 75
      assert thumbnail.format == :webp
      assert thumbnail.effort == 2
    end

    test "small variant has correct configuration" do
      variants = ImageProcessing.variants()
      small = variants[:small]

      assert small.width == 768
      assert small.quality == 80
      assert small.format == :webp
      assert small.effort == 2
    end

    test "medium variant has correct configuration" do
      variants = ImageProcessing.variants()
      medium = variants[:medium]

      assert medium.width == 1280
      assert medium.quality == 85
      assert medium.format == :webp
      assert medium.effort == 4
    end

    test "large variant has correct configuration" do
      variants = ImageProcessing.variants()
      large = variants[:large]

      assert large.width == 1920
      assert large.quality == 90
      assert large.format == :avif
      assert large.effort == 6
    end
  end

  describe "variant/1" do
    test "returns specific variant configuration" do
      config = ImageProcessing.variant(:thumbnail)

      assert config.width == 400
      assert config.quality == 75
      assert config.format == :webp
    end

    test "returns nil for non-existent variant" do
      assert ImageProcessing.variant(:nonexistent) == nil
    end

    test "returns nil for invalid variant name" do
      assert ImageProcessing.variant(:invalid) == nil
    end

    test "returns configuration for all valid variants" do
      assert ImageProcessing.variant(:thumbnail) != nil
      assert ImageProcessing.variant(:small) != nil
      assert ImageProcessing.variant(:medium) != nil
      assert ImageProcessing.variant(:large) != nil
    end
  end

  describe "file_extension/1" do
    test "returns correct extension for webp" do
      assert ImageProcessing.file_extension(:webp) == "webp"
    end

    test "returns correct extension for avif" do
      assert ImageProcessing.file_extension(:avif) == "avif"
    end

    test "returns jpg for jpeg format" do
      assert ImageProcessing.file_extension(:jpeg) == "jpg"
    end
  end

  describe "file_extension/1 - edge cases" do
    test "handles all supported formats" do
      supported_formats = [:webp, :avif, :jpeg]

      Enum.each(supported_formats, fn format ->
        extension = ImageProcessing.file_extension(format)
        assert is_binary(extension)
        assert String.length(extension) > 0
      end)
    end
  end

  describe "generate_variants/3 - integration" do
    test "returns error for non-existent source file" do
      result =
        ImageProcessing.generate_variants(
          "test-123",
          "/non/existent/file.jpg",
          "/output/path"
        )

      assert {:error, _reason} = result
    end

    test "returns error for invalid output path" do
      # Create a temporary source file
      tmp_dir = System.tmp_dir!()
      source_path = Path.join(tmp_dir, "test_source.jpg")

      # Create minimal test image
      File.write!(source_path, <<0xFF, 0xD8, 0xFF>>)

      result =
        ImageProcessing.generate_variants(
          "test-456",
          source_path,
          "/invalid/output/path/that/does/not/exist"
        )

      # Clean up
      File.rm(source_path)

      assert {:error, _reason} = result
    end
  end

  describe "module types and specs" do
    test "variant type includes all standard variants" do
      # This test verifies the type documentation is correct
      # by ensuring all documented variants exist in configuration
      variants = ImageProcessing.variants()

      assert Map.has_key?(variants, :thumbnail)
      assert Map.has_key?(variants, :small)
      assert Map.has_key?(variants, :medium)
      assert Map.has_key?(variants, :large)
    end

    test "variant_config includes all required fields" do
      variant_config = ImageProcessing.variant(:thumbnail)

      # Verify all fields from variant_config type are present
      assert is_integer(variant_config.width)
      assert is_integer(variant_config.quality)
      assert is_atom(variant_config.format)
      assert is_integer(variant_config.effort)
    end
  end

  describe "configuration validation" do
    test "all variants have valid width values" do
      variants = ImageProcessing.variants()

      Enum.each(variants, fn {_name, config} ->
        assert config.width > 0
        assert config.width <= 4000
      end)
    end

    test "all variants have valid quality values" do
      variants = ImageProcessing.variants()

      Enum.each(variants, fn {_name, config} ->
        assert config.quality >= 1
        assert config.quality <= 100
      end)
    end

    test "all variants have valid effort values" do
      variants = ImageProcessing.variants()

      Enum.each(variants, fn {_name, config} ->
        assert config.effort >= 0
        assert config.effort <= 9
      end)
    end

    test "all variants have supported formats" do
      variants = ImageProcessing.variants()
      supported_formats = [:webp, :avif, :jpeg]

      Enum.each(variants, fn {_name, config} ->
        assert config.format in supported_formats
      end)
    end
  end

  describe "variant ordering and optimization" do
    test "variants are ordered by increasing size" do
      variants = ImageProcessing.variants()

      widths = [
        variants[:thumbnail].width,
        variants[:small].width,
        variants[:medium].width,
        variants[:large].width
      ]

      assert widths == Enum.sort(widths)
    end

    test "smaller variants use lower effort for faster processing" do
      variants = ImageProcessing.variants()

      # Thumbnail and small should have lower effort than large
      assert variants[:thumbnail].effort <= variants[:large].effort
      assert variants[:small].effort <= variants[:large].effort
    end

    test "quality increases with size for better detail" do
      variants = ImageProcessing.variants()

      # Larger variants should have equal or higher quality
      assert variants[:thumbnail].quality <= variants[:medium].quality
      assert variants[:small].quality <= variants[:medium].quality
      assert variants[:medium].quality <= variants[:large].quality
    end
  end
end
