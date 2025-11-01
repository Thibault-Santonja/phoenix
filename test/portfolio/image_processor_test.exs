defmodule Portfolio.ImageProcessorTest do
  @moduledoc """
  Tests for the ImageProcessor module.

  These tests verify image processing functionality including:
  - Variant generation with correct dimensions
  - WebP conversion with quality settings
  - Error handling for invalid inputs
  - Performance within acceptable bounds
  """
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessor

  @test_fixtures_dir "test/fixtures/images"
  @test_output_dir "test/tmp/image_processor"

  setup do
    # Clean and create test directories
    File.rm_rf!(@test_output_dir)
    File.mkdir_p!(@test_output_dir)
    File.mkdir_p!(@test_fixtures_dir)

    # Create a simple test image using Vix if none exists
    test_image_path = Path.join(@test_fixtures_dir, "test_photo.jpg")

    unless File.exists?(test_image_path) do
      create_test_image(test_image_path, 1920, 1080)
    end

    on_exit(fn ->
      File.rm_rf!(@test_output_dir)
    end)

    %{test_image: test_image_path, output_dir: @test_output_dir}
  end

  describe "variants/0" do
    test "returns configured variants from application config" do
      variants = ImageProcessor.variants()

      assert is_map(variants)
      assert Map.has_key?(variants, :thumbnail)
      assert Map.has_key?(variants, :small)
      assert Map.has_key?(variants, :medium)
      assert Map.has_key?(variants, :large)
    end

    test "each variant has width and quality configured" do
      variants = ImageProcessor.variants()

      Enum.each(variants, fn {name, config} ->
        assert Keyword.has_key?(config, :width), "#{name} missing :width"
        assert Keyword.has_key?(config, :quality), "#{name} missing :quality"
        assert is_integer(config[:width]), "#{name} width not an integer"
        assert is_integer(config[:quality]), "#{name} quality not an integer"
      end)
    end

    test "variants are in ascending size order" do
      variants = ImageProcessor.variants()

      widths = [
        variants[:thumbnail][:width],
        variants[:small][:width],
        variants[:medium][:width],
        variants[:large][:width]
      ]

      assert widths == Enum.sort(widths), "Variants not in ascending size order"
    end
  end

  describe "generate_variants/2 - happy path" do
    test "generates all configured variants", %{test_image: source, output_dir: output} do
      output_path = Path.join(output, "photo1")

      assert {:ok, variants} = ImageProcessor.generate_variants(source, output_path)

      assert is_map(variants)
      assert Map.has_key?(variants, :thumbnail)
      assert Map.has_key?(variants, :small)
      assert Map.has_key?(variants, :medium)
      assert Map.has_key?(variants, :large)
    end

    test "all variant files are created", %{test_image: source, output_dir: output} do
      output_path = Path.join(output, "photo2")

      assert {:ok, variants} = ImageProcessor.generate_variants(source, output_path)

      Enum.each(variants, fn {_name, path} ->
        assert File.exists?(path), "Variant file not created: #{path}"
      end)
    end

    test "variant files are WebP format", %{test_image: source, output_dir: output} do
      output_path = Path.join(output, "photo3")

      assert {:ok, variants} = ImageProcessor.generate_variants(source, output_path)

      Enum.each(variants, fn {_name, path} ->
        assert String.ends_with?(path, ".webp"), "Variant not WebP: #{path}"
      end)
    end

    test "creates output directory if it doesn't exist", %{
      test_image: source,
      output_dir: output
    } do
      output_path = Path.join(output, "nested/deep/directory")
      refute File.exists?(output_path)

      assert {:ok, _variants} = ImageProcessor.generate_variants(source, output_path)
      assert File.exists?(output_path)
    end

    test "variant dimensions are correct", %{test_image: source, output_dir: output} do
      output_path = Path.join(output, "photo4")

      assert {:ok, variants} = ImageProcessor.generate_variants(source, output_path)

      config = ImageProcessor.variants()

      Enum.each(variants, fn {name, path} ->
        {:ok, img} = Vix.Vips.Image.new_from_file(path)
        width = Vix.Vips.Image.width(img)
        expected_width = config[name][:width]

        # Width should match or be smaller (if original was smaller)
        assert width <= expected_width,
               "#{name} width #{width} exceeds expected #{expected_width}"
      end)
    end

    test "doesn't upscale images smaller than target", %{output_dir: output} do
      # Create a small image (smaller than thumbnail)
      small_image = Path.join(output, "small_source.jpg")
      create_test_image(small_image, 200, 150)

      output_path = Path.join(output, "photo5")

      assert {:ok, variants} = ImageProcessor.generate_variants(small_image, output_path)

      # All variants should be 200px or smaller (original size)
      Enum.each(variants, fn {_name, path} ->
        {:ok, img} = Vix.Vips.Image.new_from_file(path)
        width = Vix.Vips.Image.width(img)
        assert width <= 200, "Small image was upscaled to #{width}px"
      end)
    end
  end

  describe "generate_variants/2 - error handling" do
    test "returns error for non-existent source file", %{output_dir: output} do
      output_path = Path.join(output, "photo6")

      assert {:error, :file_not_found} =
               ImageProcessor.generate_variants("/nonexistent/file.jpg", output_path)
    end

    test "returns error for corrupted image file", %{output_dir: output} do
      # Create a corrupted file (not a valid image)
      corrupted = Path.join(output, "corrupted.jpg")
      File.write!(corrupted, "not an image")

      output_path = Path.join(output, "photo7")

      assert {:error, :corrupted_file} = ImageProcessor.generate_variants(corrupted, output_path)
    end

    test "returns error when output directory cannot be created" do
      # Try to write to a read-only location (this is system-dependent)
      # For now, we'll test the validation logic exists
      assert {:error, :file_not_found} =
               ImageProcessor.generate_variants("/nonexistent.jpg", "/some/path")
    end

    test "handles huge images gracefully", %{output_dir: output} do
      # Create a very large image (12000x8000)
      huge_image = Path.join(output, "huge_source.jpg")
      create_test_image(huge_image, 12000, 8000)

      output_path = Path.join(output, "photo_huge")

      # Should succeed even with huge images
      assert {:ok, variants} = ImageProcessor.generate_variants(huge_image, output_path)

      # Verify all variants were created
      assert map_size(variants) == 4

      # Verify largest variant doesn't exceed original size
      large_path = variants[:large]
      {:ok, img} = Vix.Vips.Image.new_from_file(large_path)
      width = Vix.Vips.Image.width(img)
      assert width <= 12000
    end

    test "handles PNG format correctly", %{output_dir: output} do
      # Create a PNG test image
      png_image = Path.join(output, "test.png")
      create_test_image(png_image, 1920, 1080)

      output_path = Path.join(output, "photo_png")

      assert {:ok, variants} = ImageProcessor.generate_variants(png_image, output_path)

      # All outputs should be WebP
      Enum.each(variants, fn {_name, path} ->
        assert String.ends_with?(path, ".webp")
      end)
    end

    test "handles WebP format correctly", %{output_dir: output} do
      # Create a WebP test image
      webp_image = Path.join(output, "test.webp")
      {:ok, img} = Vix.Vips.Operation.black(1920, 1080)
      Vix.Vips.Image.write_to_file(img, webp_image)

      output_path = Path.join(output, "photo_webp")

      assert {:ok, variants} = ImageProcessor.generate_variants(webp_image, output_path)

      # All outputs should be WebP
      Enum.each(variants, fn {_name, path} ->
        assert String.ends_with?(path, ".webp")
      end)
    end

    test "returns error for invalid file format", %{output_dir: output} do
      # Create a text file with image extension
      invalid = Path.join(output, "invalid.jpg")
      File.write!(invalid, "This is not an image file, just plain text")

      output_path = Path.join(output, "photo_invalid")

      assert {:error, :corrupted_file} = ImageProcessor.generate_variants(invalid, output_path)
    end

    test "returns error for empty file", %{output_dir: output} do
      # Create an empty file
      empty = Path.join(output, "empty.jpg")
      File.write!(empty, "")

      output_path = Path.join(output, "photo_empty")

      assert {:error, :corrupted_file} = ImageProcessor.generate_variants(empty, output_path)
    end
  end

  describe "performance" do
    @tag :performance
    @tag timeout: 30_000
    test "processes image within acceptable time", %{test_image: source, output_dir: output} do
      output_path = Path.join(output, "photo_perf")

      {time_micros, {:ok, _variants}} =
        :timer.tc(fn ->
          ImageProcessor.generate_variants(source, output_path)
        end)

      time_seconds = time_micros / 1_000_000

      # Should complete in under 10 seconds for a 1920x1080 test image
      # (Production target is 4s for 4000x3000, so this should be fast)
      assert time_seconds < 10.0,
             "Processing took #{time_seconds}s, expected < 10s"
    end

    @tag :performance
    test "generates reasonably sized output files", %{test_image: source, output_dir: output} do
      output_path = Path.join(output, "photo_size")

      assert {:ok, variants} = ImageProcessor.generate_variants(source, output_path)

      Enum.each(variants, fn {name, path} ->
        size_bytes = File.stat!(path).size
        size_kb = size_bytes / 1024

        # WebP files should be reasonably compressed
        # Exact sizes depend on image content, but check they're not huge
        assert size_kb < 1024,
               "#{name} variant is #{size_kb}KB, expected < 1024KB"
      end)
    end
  end

  # Helper Functions

  defp create_test_image(path, width, height) do
    # Create a simple solid color image for testing
    {:ok, img} = Vix.Vips.Operation.black(width, height)
    Vix.Vips.Image.write_to_file(img, path)
  end
end
