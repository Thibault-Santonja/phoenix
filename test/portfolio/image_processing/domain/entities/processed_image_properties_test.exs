defmodule Portfolio.ImageProcessing.Domain.Entities.ProcessedImagePropertiesTest do
  @moduledoc """
  Property-based tests for ProcessedImage entity.

  Tests invariants and state transitions that must hold for all valid inputs.
  """
  use ExUnit.Case, async: true

  @moduletag :skip
  use ExUnitProperties

  alias Portfolio.ImageProcessing.Domain.Entities.ProcessedImage
  alias Portfolio.ImageProcessing.Domain.ValueObjects.{ImageDimensions, VariantSpecification}

  # Generators

  defp id_generator do
    gen all(id <- string(:alphanumeric, min_length: 8, max_length: 64)) do
      id
    end
  end

  defp path_generator do
    gen all(parts <- list_of(string(:alphanumeric, min_length: 1, max_length: 20), min_length: 1)) do
      "/" <> Enum.join(parts, "/")
    end
  end

  defp dimensions_generator do
    gen all(
          width <- integer(1..10_000),
          height <- integer(1..10_000)
        ) do
      ImageDimensions.new!(width, height)
    end
  end

  defp variants_generator do
    gen all(
          variant_names <-
            list_of(
              member_of([:thumbnail, :small, :medium, :large, :original]),
              min_length: 1,
              max_length: 5
            ),
          paths <- list_of(path_generator(), min_length: 1, max_length: 5)
        ) do
      variant_names
      |> Enum.zip(paths)
      |> Map.new()
    end
  end

  defp error_generator do
    member_of([
      :file_not_found,
      :invalid_format,
      :corrupted_image,
      :processing_failed,
      {:vips_error, "Invalid image"},
      {:resize_failed, "Memory allocation failed"}
    ])
  end

  describe "state transition properties" do
    property "new images start in pending state" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator()
            ) do
        image = ProcessedImage.new(id, source, output)

        assert image.processing_status == :pending
        assert image.error == nil
        assert image.variants == nil
        assert image.original_dimensions == nil
      end
    end

    property "pending -> processing transition is valid" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              dimensions <- dimensions_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.start_processing(dimensions)

        assert image.processing_status == :processing
        assert image.original_dimensions == dimensions
        assert image.error == nil
      end
    end

    property "processing -> completed transition requires non-empty variants" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              dimensions <- dimensions_generator(),
              variants <- variants_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.start_processing(dimensions)
          |> ProcessedImage.mark_completed(variants)

        assert image.processing_status == :completed
        assert image.variants == variants
        assert map_size(image.variants) > 0
        assert image.error == nil
      end
    end

    property "any state -> failed transition sets error" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              error <- error_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.mark_failed(error)

        assert image.processing_status == :failed
        assert image.error == error
        assert image.variants == nil
      end
    end

    property "failed state implies error is not nil" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              error <- error_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.mark_failed(error)

        if ProcessedImage.failed?(image) do
          assert image.error != nil
        end
      end
    end

    property "completed state implies variants is not empty" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              dimensions <- dimensions_generator(),
              variants <- variants_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.start_processing(dimensions)
          |> ProcessedImage.mark_completed(variants)

        if ProcessedImage.completed?(image) do
          assert image.variants != nil
          assert map_size(image.variants) > 0
        end
      end
    end

    property "state predicates are mutually exclusive" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator()
            ) do
        image = ProcessedImage.new(id, source, output)

        # Only one predicate should be true at any time
        predicates = [
          ProcessedImage.completed?(image),
          ProcessedImage.failed?(image),
          ProcessedImage.processing?(image)
        ]

        true_count = Enum.count(predicates, & &1)

        assert true_count <= 1,
               "Multiple state predicates are true: #{inspect(predicates)}"
      end
    end
  end

  describe "variant path properties" do
    property "variant_path returns error for non-processed images" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              variant_name <- atom(:alphanumeric)
            ) do
        image = ProcessedImage.new(id, source, output)

        assert {:error, :not_processed} = ProcessedImage.variant_path(image, variant_name)
      end
    end

    property "variant_path returns ok for existing variants" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              dimensions <- dimensions_generator(),
              variants <- variants_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.start_processing(dimensions)
          |> ProcessedImage.mark_completed(variants)

        # Check each variant that exists
        Enum.each(variants, fn {variant_name, expected_path} ->
          assert {:ok, ^expected_path} = ProcessedImage.variant_path(image, variant_name)
        end)
      end
    end

    property "variant_path returns error for non-existent variants" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              dimensions <- dimensions_generator(),
              variants <- variants_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.start_processing(dimensions)
          |> ProcessedImage.mark_completed(variants)

        # Try to get a variant that doesn't exist
        non_existent = :definitely_does_not_exist_variant

        if not Map.has_key?(variants, non_existent) do
          assert {:error, :variant_not_found} =
                   ProcessedImage.variant_path(image, non_existent)
        end
      end
    end
  end

  describe "output path calculation properties" do
    property "output_path_for_variant is deterministic" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              width <- integer(100..2000),
              quality <- integer(50..100),
              format <- member_of([:webp, :avif, :jpeg]),
              effort <- integer(4..6)
            ) do
        image = ProcessedImage.new(id, source, output)
        spec = VariantSpecification.new!(:test_variant, width, quality, format, effort)

        path1 = ProcessedImage.output_path_for_variant(image, spec)
        path2 = ProcessedImage.output_path_for_variant(image, spec)

        assert path1 == path2
      end
    end

    property "output_path_for_variant starts with base path" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              width <- integer(100..2000),
              quality <- integer(50..100),
              format <- member_of([:webp, :avif, :jpeg]),
              effort <- integer(4..6)
            ) do
        image = ProcessedImage.new(id, source, output)
        spec = VariantSpecification.new!(:test_variant, width, quality, format, effort)

        path = ProcessedImage.output_path_for_variant(image, spec)

        assert String.starts_with?(path, output)
      end
    end

    property "output_path_for_variant includes variant name and format" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              variant_name <- atom(:alphanumeric),
              width <- integer(100..2000),
              quality <- integer(50..100),
              format <- member_of([:webp, :avif, :jpeg]),
              effort <- integer(4..6)
            ) do
        image = ProcessedImage.new(id, source, output)
        spec = VariantSpecification.new!(variant_name, width, quality, format, effort)

        path = ProcessedImage.output_path_for_variant(image, spec)

        # Path should contain variant name and format extension
        assert String.contains?(path, to_string(variant_name))
        assert String.ends_with?(path, ".#{format}")
      end
    end
  end

  describe "variants retrieval properties" do
    property "variants() returns error for non-processed images" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator()
            ) do
        image = ProcessedImage.new(id, source, output)

        assert {:error, :not_processed} = ProcessedImage.variants(image)
      end
    end

    property "variants() returns all completed variants" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              dimensions <- dimensions_generator(),
              expected_variants <- variants_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.start_processing(dimensions)
          |> ProcessedImage.mark_completed(expected_variants)

        assert {:ok, variants} = ProcessedImage.variants(image)
        assert variants == expected_variants
      end
    end
  end

  describe "idempotency properties" do
    property "marking failed multiple times preserves last error" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              error1 <- error_generator(),
              error2 <- error_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.mark_failed(error1)
          |> ProcessedImage.mark_failed(error2)

        assert image.processing_status == :failed
        assert image.error == error2
      end
    end

    property "start_processing can be called multiple times" do
      check all(
              id <- id_generator(),
              source <- path_generator(),
              output <- path_generator(),
              dims1 <- dimensions_generator(),
              dims2 <- dimensions_generator()
            ) do
        image =
          ProcessedImage.new(id, source, output)
          |> ProcessedImage.start_processing(dims1)
          |> ProcessedImage.start_processing(dims2)

        assert image.processing_status == :processing
        # Last dimensions should win
        assert image.original_dimensions == dims2
      end
    end
  end
end
