defmodule Portfolio.ImageProcessing.Domain.Entities.ProcessedImageTest do
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing.Domain.Entities.ProcessedImage
  alias Portfolio.ImageProcessing.Domain.ValueObjects.{ImageDimensions, VariantSpecification}

  describe "new/3" do
    test "creates a new image with pending status" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")

      assert image.id == "abc123"
      assert image.source_path == "/tmp/photo.jpg"
      assert image.output_base_path == "/uploads/abc123"
      assert image.processing_status == :pending
      assert image.original_dimensions == nil
      assert image.variants == nil
      assert image.error == nil
    end

    test "creates image with different paths" do
      image = ProcessedImage.new("xyz", "/data/images/test.png", "/output/xyz")

      assert image.id == "xyz"
      assert image.source_path == "/data/images/test.png"
      assert image.output_base_path == "/output/xyz"
    end

    test "handles empty string id" do
      image = ProcessedImage.new("", "/tmp/photo.jpg", "/uploads/")
      assert image.id == ""
    end

    test "handles paths with special characters" do
      image = ProcessedImage.new("id-123", "/tmp/photo with spaces.jpg", "/uploads/dir-name")
      assert image.source_path == "/tmp/photo with spaces.jpg"
    end
  end

  describe "start_processing/2" do
    test "transitions image to processing status" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      dims = ImageDimensions.new!(1920, 1080)

      processing_image = ProcessedImage.start_processing(image, dims)

      assert processing_image.processing_status == :processing
      assert processing_image.original_dimensions == dims
    end

    test "preserves other fields when starting processing" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      dims = ImageDimensions.new!(4000, 3000)

      processing_image = ProcessedImage.start_processing(image, dims)

      assert processing_image.id == "abc123"
      assert processing_image.source_path == "/tmp/photo.jpg"
      assert processing_image.output_base_path == "/uploads/abc123"
    end

    test "accepts various dimension sizes" do
      image = ProcessedImage.new("id", "/path", "/output")

      for {w, h} <- [{100, 100}, {1920, 1080}, {8000, 6000}] do
        dims = ImageDimensions.new!(w, h)
        result = ProcessedImage.start_processing(image, dims)
        assert result.original_dimensions.width == w
        assert result.original_dimensions.height == h
      end
    end
  end

  describe "mark_completed/2" do
    test "transitions image to completed status with variants" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")

      variants = %{
        thumbnail: "/uploads/abc123/thumbnail.webp",
        large: "/uploads/abc123/large.webp"
      }

      completed = ProcessedImage.mark_completed(image, variants)

      assert completed.processing_status == :completed
      assert completed.variants == variants
      assert completed.error == nil
    end

    test "clears error when marking completed" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      failed = ProcessedImage.mark_failed(image, :some_error)

      completed = ProcessedImage.mark_completed(failed, %{})

      assert completed.processing_status == :completed
      assert completed.error == nil
    end

    test "accepts empty variants map" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")

      completed = ProcessedImage.mark_completed(image, %{})

      assert completed.processing_status == :completed
      assert completed.variants == %{}
    end

    test "accepts multiple variant formats" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")

      variants = %{
        thumbnail_webp: "/path/thumbnail.webp",
        thumbnail_avif: "/path/thumbnail.avif",
        large_webp: "/path/large.webp"
      }

      completed = ProcessedImage.mark_completed(image, variants)
      assert completed.variants == variants
    end
  end

  describe "mark_failed/2" do
    test "transitions image to failed status with error" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")

      failed = ProcessedImage.mark_failed(image, :file_not_found)

      assert failed.processing_status == :failed
      assert failed.error == :file_not_found
      assert failed.variants == nil
    end

    test "clears variants when marking failed" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      completed = ProcessedImage.mark_completed(image, %{thumbnail: "/path"})

      failed = ProcessedImage.mark_failed(completed, :processing_error)

      assert failed.variants == nil
    end

    test "accepts different error types" do
      image = ProcessedImage.new("id", "/path", "/output")

      errors = [
        :file_not_found,
        :invalid_format,
        {:timeout, 5000},
        "string error",
        %{reason: :unknown}
      ]

      for error <- errors do
        failed = ProcessedImage.mark_failed(image, error)
        assert failed.error == error
      end
    end
  end

  describe "completed?/1" do
    test "returns true for completed image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_completed(%{})

      assert ProcessedImage.completed?(image)
    end

    test "returns false for pending image" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      refute ProcessedImage.completed?(image)
    end

    test "returns false for processing image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.start_processing(ImageDimensions.new!(1920, 1080))

      refute ProcessedImage.completed?(image)
    end

    test "returns false for failed image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_failed(:error)

      refute ProcessedImage.completed?(image)
    end
  end

  describe "failed?/1" do
    test "returns true for failed image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_failed(:error)

      assert ProcessedImage.failed?(image)
    end

    test "returns false for pending image" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      refute ProcessedImage.failed?(image)
    end

    test "returns false for completed image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_completed(%{})

      refute ProcessedImage.failed?(image)
    end
  end

  describe "processing?/1" do
    test "returns true for processing image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.start_processing(ImageDimensions.new!(1920, 1080))

      assert ProcessedImage.processing?(image)
    end

    test "returns false for pending image" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      refute ProcessedImage.processing?(image)
    end

    test "returns false for completed image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_completed(%{})

      refute ProcessedImage.processing?(image)
    end

    test "returns false for failed image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_failed(:error)

      refute ProcessedImage.processing?(image)
    end
  end

  describe "variant_path/2" do
    test "returns path for existing variant" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_completed(%{thumbnail: "/path/thumb.webp"})

      assert {:ok, "/path/thumb.webp"} = ProcessedImage.variant_path(image, :thumbnail)
    end

    test "returns error for non-existent variant" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_completed(%{thumbnail: "/path/thumb.webp"})

      assert {:error, :variant_not_found} = ProcessedImage.variant_path(image, :large)
    end

    test "returns error when image not processed" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")

      assert {:error, :not_processed} = ProcessedImage.variant_path(image, :thumbnail)
    end

    test "returns error for failed image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_failed(:error)

      assert {:error, :not_processed} = ProcessedImage.variant_path(image, :thumbnail)
    end

    test "handles multiple variants" do
      variants = %{
        thumbnail: "/path/thumb.webp",
        small: "/path/small.webp",
        large: "/path/large.webp"
      }

      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_completed(variants)

      assert {:ok, "/path/thumb.webp"} = ProcessedImage.variant_path(image, :thumbnail)
      assert {:ok, "/path/small.webp"} = ProcessedImage.variant_path(image, :small)
      assert {:ok, "/path/large.webp"} = ProcessedImage.variant_path(image, :large)
    end
  end

  describe "variants/1" do
    test "returns variants for completed image" do
      variants = %{thumbnail: "/path/thumb.webp"}

      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_completed(variants)

      assert {:ok, ^variants} = ProcessedImage.variants(image)
    end

    test "returns empty map for completed image with no variants" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_completed(%{})

      assert {:ok, %{}} = ProcessedImage.variants(image)
    end

    test "returns error for pending image" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")

      assert {:error, :not_processed} = ProcessedImage.variants(image)
    end

    test "returns error for failed image" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_failed(:error)

      assert {:error, :not_processed} = ProcessedImage.variants(image)
    end
  end

  describe "output_path_for_variant/2" do
    test "generates correct path for webp variant" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)

      assert ProcessedImage.output_path_for_variant(image, spec) ==
               "/uploads/abc123/thumbnail.webp"
    end

    test "generates correct path for avif variant" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      spec = VariantSpecification.new!(:large, 1920, 85, :avif, 6)

      assert ProcessedImage.output_path_for_variant(image, spec) == "/uploads/abc123/large.avif"
    end

    test "generates correct path for jpeg variant" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      spec = VariantSpecification.new!(:medium, 960, 80, :jpeg, 5)

      assert ProcessedImage.output_path_for_variant(image, spec) == "/uploads/abc123/medium.jpg"
    end

    test "handles nested output paths" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/data/uploads/2024/01/abc123")
      spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)

      assert ProcessedImage.output_path_for_variant(image, spec) ==
               "/data/uploads/2024/01/abc123/thumbnail.webp"
    end
  end

  describe "state transitions" do
    test "full lifecycle: pending -> processing -> completed" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      assert image.processing_status == :pending

      dims = ImageDimensions.new!(1920, 1080)
      image = ProcessedImage.start_processing(image, dims)
      assert image.processing_status == :processing

      image = ProcessedImage.mark_completed(image, %{thumbnail: "/path"})
      assert image.processing_status == :completed
    end

    test "full lifecycle: pending -> processing -> failed" do
      image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      assert image.processing_status == :pending

      dims = ImageDimensions.new!(1920, 1080)
      image = ProcessedImage.start_processing(image, dims)
      assert image.processing_status == :processing

      image = ProcessedImage.mark_failed(image, :timeout)
      assert image.processing_status == :failed
    end

    test "can recover from failed to completed" do
      image =
        ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
        |> ProcessedImage.mark_failed(:error)

      assert image.processing_status == :failed

      image = ProcessedImage.mark_completed(image, %{thumbnail: "/path"})
      assert image.processing_status == :completed
      assert image.error == nil
    end

    test "only one status predicate is true at a time" do
      pending = ProcessedImage.new("id", "/path", "/output")

      processing =
        ProcessedImage.start_processing(pending, ImageDimensions.new!(100, 100))

      completed = ProcessedImage.mark_completed(pending, %{})
      failed = ProcessedImage.mark_failed(pending, :error)

      for image <- [pending, processing, completed, failed] do
        statuses = [
          ProcessedImage.processing?(image),
          ProcessedImage.completed?(image),
          ProcessedImage.failed?(image)
        ]

        # At most one status predicate should be true
        assert Enum.count(statuses, & &1) <= 1
      end
    end
  end
end
