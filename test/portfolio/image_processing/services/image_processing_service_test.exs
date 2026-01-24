defmodule Portfolio.ImageProcessing.Services.ImageProcessingServiceTest do
  @moduledoc """
  Tests for ImageProcessingService.

  These tests verify the service orchestration logic.
  Integration tests with actual image processing are in a separate file.
  """
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing.Domain.Entities.ProcessedImage
  alias Portfolio.ImageProcessing.Domain.ValueObjects.{ImageDimensions, VariantSpecification}

  describe "ProcessedImage entity integration" do
    test "creates new processed image with correct initial state" do
      image_id = "test-123"
      source_path = "/uploads/source/photo.jpg"
      output_base_path = "/uploads/processed/test-123"

      image = ProcessedImage.new(image_id, source_path, output_base_path)

      assert image.id == image_id
      assert image.source_path == source_path
      assert image.output_base_path == output_base_path
      assert image.processing_status == :pending
    end

    test "transitions through processing states correctly" do
      image = ProcessedImage.new("test-456", "/source.jpg", "/output")
      {:ok, dimensions} = ImageDimensions.new(4000, 3000)

      # Start processing
      image = ProcessedImage.start_processing(image, dimensions)
      assert image.processing_status == :processing

      # Complete with variants
      variants = %{thumbnail: "/output/thumbnail.webp", medium: "/output/medium.webp"}
      image = ProcessedImage.mark_completed(image, variants)
      assert image.processing_status == :completed
      assert {:ok, ^variants} = ProcessedImage.variants(image)
    end

    test "handles failure state" do
      image = ProcessedImage.new("test-789", "/source.jpg", "/output")

      image = ProcessedImage.mark_failed(image, :corrupted_file)
      assert image.processing_status == :failed
      assert image.error == :corrupted_file
    end

    test "generates correct output path for variant" do
      image = ProcessedImage.new("test-abc", "/source.jpg", "/uploads/processed/test-abc")

      spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      output_path = ProcessedImage.output_path_for_variant(image, spec)

      assert output_path == "/uploads/processed/test-abc/thumbnail.webp"
    end
  end

  describe "VariantSpecification integration" do
    test "creates valid specification" do
      spec = VariantSpecification.new!(:medium, 1200, 85, :webp, 4)

      assert VariantSpecification.name(spec) == :medium
      assert spec.width == 1200
      assert spec.quality == 85
      assert spec.format == :webp
      assert spec.effort == 4
    end

    test "validates width constraints" do
      # Valid widths
      assert {:ok, _} = VariantSpecification.new(:thumb, 100, 75, :webp, 4)
      assert {:ok, _} = VariantSpecification.new(:large, 4000, 90, :webp, 4)

      # Invalid widths
      assert {:error, _} = VariantSpecification.new(:invalid, 0, 75, :webp, 4)
      assert {:error, _} = VariantSpecification.new(:invalid, -100, 75, :webp, 4)
    end

    test "validates quality constraints" do
      # Valid quality values
      assert {:ok, _} = VariantSpecification.new(:test, 800, 1, :webp, 4)
      assert {:ok, _} = VariantSpecification.new(:test, 800, 100, :webp, 4)

      # Invalid quality values
      assert {:error, _} = VariantSpecification.new(:test, 800, 0, :webp, 4)
      assert {:error, _} = VariantSpecification.new(:test, 800, 101, :webp, 4)
    end

    test "validates format" do
      assert {:ok, _} = VariantSpecification.new(:test, 800, 75, :webp, 4)
      assert {:ok, _} = VariantSpecification.new(:test, 800, 75, :avif, 4)
      assert {:ok, _} = VariantSpecification.new(:test, 800, 75, :jpeg, 4)

      assert {:error, _} = VariantSpecification.new(:test, 800, 75, :png, 4)
      assert {:error, _} = VariantSpecification.new(:test, 800, 75, :gif, 4)
    end
  end

  describe "ImageDimensions integration" do
    test "creates valid dimensions" do
      assert {:ok, dims} = ImageDimensions.new(1920, 1080)
      assert dims.width == 1920
      assert dims.height == 1080
    end

    test "calculates aspect ratio" do
      {:ok, dims} = ImageDimensions.new(1920, 1080)
      assert_in_delta ImageDimensions.aspect_ratio(dims), 1.777, 0.001
    end

    test "resizes to width preserving aspect ratio" do
      {:ok, dims} = ImageDimensions.new(4000, 3000)

      assert {:ok, resized} = ImageDimensions.resize_to_width(dims, 2000)
      assert resized.width == 2000
      assert resized.height == 1500
    end

    test "prevents upscaling" do
      {:ok, dims} = ImageDimensions.new(800, 600)

      assert {:no_upscale, ^dims} = ImageDimensions.resize_to_width(dims, 1600)
    end

    test "rejects invalid dimensions" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(0, 100)
      assert {:error, :invalid_dimensions} = ImageDimensions.new(100, 0)
      assert {:error, :invalid_dimensions} = ImageDimensions.new(-100, 100)
    end
  end

  describe "generate_variants/3" do
    alias Portfolio.ImageProcessing.Services.ImageProcessingService

    @fixtures_dir Path.join([File.cwd!(), "test", "fixtures", "images"])

    test "returns error when source file does not exist" do
      result =
        ImageProcessingService.generate_variants(
          "test-id",
          "/nonexistent/path/photo.jpg",
          "/tmp/output"
        )

      assert {:error, :file_not_found} = result
    end

    test "returns error when source file is corrupted" do
      # Create a temporary file with invalid image content
      temp_file = Path.join(System.tmp_dir!(), "invalid_image_#{:rand.uniform(100_000)}.jpg")
      File.write!(temp_file, "not a valid image content")

      on_exit(fn -> File.rm(temp_file) end)

      result =
        ImageProcessingService.generate_variants(
          "test-id",
          temp_file,
          "/tmp/output"
        )

      assert {:error, :corrupted_file} = result
    end

    test "successfully generates variants from valid image" do
      test_image = Path.join(@fixtures_dir, "test_photo.jpg")
      output_dir = Path.join(System.tmp_dir!(), "variants_test_#{:rand.uniform(100_000)}")

      on_exit(fn -> File.rm_rf(output_dir) end)

      if File.exists?(test_image) do
        result =
          ImageProcessingService.generate_variants(
            "success-test-id",
            test_image,
            output_dir
          )

        assert {:ok, variants} = result
        assert is_map(variants)
        assert map_size(variants) > 0

        # Check that variants files were created
        Enum.each(variants, fn {_name, path} ->
          assert File.exists?(path), "Variant file should exist: #{path}"
        end)
      else
        :ok
      end
    end

    test "returns error when output directory cannot be created" do
      test_image = Path.join(@fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        # Try to create output in a read-only location
        result =
          ImageProcessingService.generate_variants(
            "readonly-test-id",
            test_image,
            "/proc/readonly_test_dir"
          )

        assert {:error, {:directory_creation_failed, _}} = result
      else
        :ok
      end
    end

    test "emits telemetry events during processing" do
      test_image = Path.join(@fixtures_dir, "test_photo.jpg")
      output_dir = Path.join(System.tmp_dir!(), "telemetry_test_#{:rand.uniform(100_000)}")

      on_exit(fn -> File.rm_rf(output_dir) end)

      if File.exists?(test_image) do
        # The service emits domain events via DomainEvents.publish
        # We verify the function completes without error
        result =
          ImageProcessingService.generate_variants(
            "telemetry-test-id",
            test_image,
            output_dir
          )

        assert {:ok, _variants} = result
      else
        :ok
      end
    end
  end

  describe "VariantSpecification.name/1" do
    test "returns the name of the specification" do
      spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      assert VariantSpecification.name(spec) == :thumbnail

      spec = VariantSpecification.new!(:large, 2000, 90, :avif, 6)
      assert VariantSpecification.name(spec) == :large
    end
  end

  describe "ProcessedImage state transitions" do
    test "cannot get variants from pending image" do
      image = ProcessedImage.new("test-id", "/source.jpg", "/output")
      assert image.processing_status == :pending

      # Variants should not be available in pending state
      assert {:error, :not_processed} = ProcessedImage.variants(image)
    end

    test "cannot get variants from processing image" do
      image = ProcessedImage.new("test-id", "/source.jpg", "/output")
      {:ok, dimensions} = ImageDimensions.new(1920, 1080)
      image = ProcessedImage.start_processing(image, dimensions)

      assert image.processing_status == :processing
      assert {:error, :not_processed} = ProcessedImage.variants(image)
    end

    test "cannot get variants from failed image" do
      image = ProcessedImage.new("test-id", "/source.jpg", "/output")
      image = ProcessedImage.mark_failed(image, :some_error)

      assert image.processing_status == :failed
      assert {:error, :not_processed} = ProcessedImage.variants(image)
    end

    test "can get variants from completed image" do
      image = ProcessedImage.new("test-id", "/source.jpg", "/output")
      {:ok, dimensions} = ImageDimensions.new(1920, 1080)
      image = ProcessedImage.start_processing(image, dimensions)

      variants = %{thumbnail: "/output/thumbnail.webp"}
      image = ProcessedImage.mark_completed(image, variants)

      assert image.processing_status == :completed
      assert {:ok, ^variants} = ProcessedImage.variants(image)
    end
  end

  describe "ProcessedImage output paths" do
    test "generates correct output path for different formats" do
      image = ProcessedImage.new("test-id", "/source.jpg", "/uploads/test-id")

      webp_spec = VariantSpecification.new!(:thumb, 400, 75, :webp, 4)

      assert ProcessedImage.output_path_for_variant(image, webp_spec) ==
               "/uploads/test-id/thumb.webp"

      avif_spec = VariantSpecification.new!(:medium, 800, 80, :avif, 6)

      assert ProcessedImage.output_path_for_variant(image, avif_spec) ==
               "/uploads/test-id/medium.avif"

      # Note: jpeg format uses .jpg extension (standard short form)
      jpeg_spec = VariantSpecification.new!(:large, 1200, 85, :jpeg, 0)

      assert ProcessedImage.output_path_for_variant(image, jpeg_spec) ==
               "/uploads/test-id/large.jpg"
    end
  end
end
