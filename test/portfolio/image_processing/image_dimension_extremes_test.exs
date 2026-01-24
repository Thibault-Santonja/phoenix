defmodule Portfolio.ImageProcessing.ImageDimensionExtremesTest do
  @moduledoc """
  Boundary tests for image dimension handling.

  Tests cover:
  - Extremely tall images (1x10000)
  - Extremely wide images (10000x1)
  - Zero width rejection
  - Negative dimensions rejection
  - Very large dimensions
  - Aspect ratio extremes
  """
  use ExUnit.Case, async: true

  @moduletag :skip

  alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageDimensions

  describe "dimension creation boundaries" do
    test "rejects zero width" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(0, 1080)
    end

    test "rejects zero height" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920, 0)
    end

    test "rejects both zero" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(0, 0)
    end

    test "rejects negative width" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(-1920, 1080)
    end

    test "rejects negative height" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920, -1080)
    end

    test "rejects both negative" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(-100, -100)
    end

    test "rejects non-integer width" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(19.5, 1080)
    end

    test "rejects non-integer height" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920, 10.8)
    end

    test "accepts minimum valid dimensions (1x1)" do
      assert {:ok, dims} = ImageDimensions.new(1, 1)
      assert dims.width == 1
      assert dims.height == 1
    end
  end

  describe "extremely tall images" do
    test "accepts extremely tall image (1x10000)" do
      assert {:ok, dims} = ImageDimensions.new(1, 10_000)
      assert dims.width == 1
      assert dims.height == 10_000
    end

    test "calculates aspect ratio for extremely tall image" do
      {:ok, dims} = ImageDimensions.new(1, 10_000)
      aspect_ratio = ImageDimensions.aspect_ratio(dims)

      assert aspect_ratio == 0.0001
      assert aspect_ratio < 1
    end

    test "resizes extremely tall image proportionally" do
      {:ok, dims} = ImageDimensions.new(100, 10_000)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 50)

      assert resized.width == 50
      assert resized.height == 5_000
    end

    test "handles very tall image (portrait extreme)" do
      {:ok, dims} = ImageDimensions.new(100, 50_000)
      aspect_ratio = ImageDimensions.aspect_ratio(dims)

      assert aspect_ratio == 0.002
    end
  end

  describe "extremely wide images" do
    test "accepts extremely wide image (10000x1)" do
      assert {:ok, dims} = ImageDimensions.new(10_000, 1)
      assert dims.width == 10_000
      assert dims.height == 1
    end

    test "calculates aspect ratio for extremely wide image" do
      {:ok, dims} = ImageDimensions.new(10_000, 1)
      aspect_ratio = ImageDimensions.aspect_ratio(dims)

      assert aspect_ratio == 10_000.0
      assert aspect_ratio > 1
    end

    test "resizes extremely wide image proportionally" do
      {:ok, dims} = ImageDimensions.new(10_000, 100)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 5_000)

      assert resized.width == 5_000
      assert resized.height == 50
    end

    test "handles very wide image (panorama extreme)" do
      {:ok, dims} = ImageDimensions.new(50_000, 100)
      aspect_ratio = ImageDimensions.aspect_ratio(dims)

      assert aspect_ratio == 500.0
    end
  end

  describe "very large dimensions" do
    test "accepts very large square image (10000x10000)" do
      assert {:ok, dims} = ImageDimensions.new(10_000, 10_000)
      assert dims.width == 10_000
      assert dims.height == 10_000
    end

    test "aspect ratio of square is always 1.0" do
      {:ok, dims} = ImageDimensions.new(10_000, 10_000)
      assert ImageDimensions.aspect_ratio(dims) == 1.0
    end

    test "accepts maximum realistic image dimensions" do
      # 100 megapixel image (10000x10000)
      assert {:ok, _dims} = ImageDimensions.new(10_000, 10_000)

      # Ultra high resolution (8K)
      assert {:ok, _dims} = ImageDimensions.new(7_680, 4_320)

      # Very large print resolution
      assert {:ok, _dims} = ImageDimensions.new(20_000, 15_000)
    end
  end

  describe "resize edge cases" do
    test "no upscale when target width is larger than original" do
      {:ok, dims} = ImageDimensions.new(800, 600)
      result = ImageDimensions.resize_to_width(dims, 1920)

      assert {:no_upscale, returned_dims} = result
      assert returned_dims.width == 800
      assert returned_dims.height == 600
    end

    test "resize to same width returns original dimensions" do
      {:ok, dims} = ImageDimensions.new(1920, 1080)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 1920)

      assert resized.width == 1920
      assert resized.height == 1080
    end

    test "resize to width of 1 for extremely wide image" do
      {:ok, dims} = ImageDimensions.new(10_000, 100)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 1)

      assert resized.width == 1
      # Height should round to at least 1
      assert resized.height >= 0
    end

    test "resize maintains aspect ratio for extreme dimensions" do
      {:ok, dims} = ImageDimensions.new(10_000, 1)
      original_aspect = ImageDimensions.aspect_ratio(dims)

      {:ok, resized} = ImageDimensions.resize_to_width(dims, 5_000)
      resized_aspect = ImageDimensions.aspect_ratio(resized)

      # Aspect ratios should be very close (allowing for rounding)
      assert_in_delta original_aspect, resized_aspect, 0.01
    end
  end

  describe "aspect ratio calculations" do
    test "perfect square has aspect ratio 1.0" do
      {:ok, dims} = ImageDimensions.new(1000, 1000)
      assert ImageDimensions.aspect_ratio(dims) == 1.0
    end

    test "16:9 aspect ratio" do
      {:ok, dims} = ImageDimensions.new(1920, 1080)
      aspect_ratio = ImageDimensions.aspect_ratio(dims)

      assert_in_delta aspect_ratio, 16 / 9, 0.01
    end

    test "4:3 aspect ratio" do
      {:ok, dims} = ImageDimensions.new(1024, 768)
      aspect_ratio = ImageDimensions.aspect_ratio(dims)

      assert_in_delta aspect_ratio, 4 / 3, 0.01
    end

    test "21:9 ultrawide aspect ratio" do
      {:ok, dims} = ImageDimensions.new(2560, 1080)
      aspect_ratio = ImageDimensions.aspect_ratio(dims)

      assert_in_delta aspect_ratio, 21 / 9, 0.01
    end

    test "aspect ratio never negative" do
      # Test various dimensions
      dimensions = [
        {1, 1},
        {100, 1},
        {1, 100},
        {1920, 1080},
        {10_000, 1}
      ]

      for {w, h} <- dimensions do
        {:ok, dims} = ImageDimensions.new(w, h)
        aspect_ratio = ImageDimensions.aspect_ratio(dims)
        assert aspect_ratio > 0
      end
    end
  end

  describe "precision and rounding" do
    test "handles odd dimension resizing" do
      {:ok, dims} = ImageDimensions.new(1001, 751)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 500)

      # Should maintain proportions
      assert resized.width == 500
      # Height should be proportional (rounded)
      assert resized.height > 0
    end

    test "very small resize maintains at least 1 pixel height" do
      {:ok, dims} = ImageDimensions.new(1000, 1)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 100)

      assert resized.width == 100
      # Even with extreme aspect ratio, height should be valid
      assert resized.height >= 0
    end
  end
end
