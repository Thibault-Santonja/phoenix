defmodule Portfolio.ImageProcessing.Domain.ValueObjects.ImageDimensionsTest do
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageDimensions

  doctest ImageDimensions

  describe "new/2" do
    test "creates valid dimensions with positive integers" do
      assert {:ok, %ImageDimensions{width: 1920, height: 1080}} =
               ImageDimensions.new(1920, 1080)
    end

    test "creates dimensions with minimum valid values (1x1)" do
      assert {:ok, %ImageDimensions{width: 1, height: 1}} = ImageDimensions.new(1, 1)
    end

    test "creates large dimensions" do
      assert {:ok, %ImageDimensions{width: 10_000, height: 8_000}} =
               ImageDimensions.new(10_000, 8_000)
    end

    test "returns error for zero width" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(0, 1080)
    end

    test "returns error for zero height" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920, 0)
    end

    test "returns error for negative width" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(-1920, 1080)
    end

    test "returns error for negative height" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920, -1080)
    end

    test "returns error for both zero" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(0, 0)
    end

    test "returns error for both negative" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(-100, -200)
    end

    test "returns error for nil width" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(nil, 1080)
    end

    test "returns error for nil height" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920, nil)
    end

    test "returns error for float width" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920.5, 1080)
    end

    test "returns error for float height" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920, 1080.5)
    end

    test "returns error for string width" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new("1920", 1080)
    end

    test "returns error for string height" do
      assert {:error, :invalid_dimensions} = ImageDimensions.new(1920, "1080")
    end
  end

  describe "new!/2" do
    test "creates valid dimensions with positive integers" do
      assert %ImageDimensions{width: 1920, height: 1080} = ImageDimensions.new!(1920, 1080)
    end

    test "raises ArgumentError for invalid dimensions" do
      assert_raise ArgumentError,
                   "Invalid dimensions: width and height must be positive",
                   fn ->
                     ImageDimensions.new!(0, 1080)
                   end
    end

    test "raises ArgumentError for negative width" do
      assert_raise ArgumentError, fn ->
        ImageDimensions.new!(-1920, 1080)
      end
    end

    test "raises ArgumentError for nil values" do
      assert_raise ArgumentError, fn ->
        ImageDimensions.new!(nil, nil)
      end
    end
  end

  describe "aspect_ratio/1" do
    test "calculates aspect ratio for landscape image (16:9)" do
      dims = ImageDimensions.new!(1920, 1080)
      assert_in_delta ImageDimensions.aspect_ratio(dims), 1.7777777777777777, 0.0001
    end

    test "calculates aspect ratio for portrait image (9:16)" do
      dims = ImageDimensions.new!(1080, 1920)
      assert_in_delta ImageDimensions.aspect_ratio(dims), 0.5625, 0.0001
    end

    test "calculates aspect ratio for square image (1:1)" do
      dims = ImageDimensions.new!(1080, 1080)
      assert ImageDimensions.aspect_ratio(dims) == 1.0
    end

    test "calculates aspect ratio for 4:3 image" do
      dims = ImageDimensions.new!(1600, 1200)
      assert_in_delta ImageDimensions.aspect_ratio(dims), 1.3333333333333333, 0.0001
    end

    test "calculates aspect ratio for ultra-wide image (21:9)" do
      dims = ImageDimensions.new!(2560, 1080)
      assert_in_delta ImageDimensions.aspect_ratio(dims), 2.370370, 0.0001
    end
  end

  describe "resize_to_width/2" do
    test "resizes landscape image proportionally" do
      dims = ImageDimensions.new!(1920, 1080)

      assert {:ok, %ImageDimensions{width: 960, height: 540}} =
               ImageDimensions.resize_to_width(dims, 960)
    end

    test "resizes portrait image proportionally" do
      dims = ImageDimensions.new!(1080, 1920)

      assert {:ok, %ImageDimensions{width: 540, height: 960}} =
               ImageDimensions.resize_to_width(dims, 540)
    end

    test "resizes square image proportionally" do
      dims = ImageDimensions.new!(1000, 1000)

      assert {:ok, %ImageDimensions{width: 500, height: 500}} =
               ImageDimensions.resize_to_width(dims, 500)
    end

    test "prevents upscaling when target width is larger" do
      dims = ImageDimensions.new!(800, 600)
      assert {:no_upscale, ^dims} = ImageDimensions.resize_to_width(dims, 1920)
    end

    test "prevents upscaling when target width equals original width" do
      dims = ImageDimensions.new!(1920, 1080)
      assert {:no_upscale, ^dims} = ImageDimensions.resize_to_width(dims, 1920)
    end

    test "rounds height to integer when needed" do
      dims = ImageDimensions.new!(1920, 1081)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 960)
      assert is_integer(resized.height)
      assert resized.height == 541
    end

    test "handles small dimensions" do
      dims = ImageDimensions.new!(100, 75)

      assert {:ok, %ImageDimensions{width: 50, height: 38}} =
               ImageDimensions.resize_to_width(dims, 50)
    end

    test "handles very wide images" do
      dims = ImageDimensions.new!(5000, 1000)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 2500)
      assert resized.width == 2500
      assert resized.height == 500
    end

    test "handles very tall images" do
      dims = ImageDimensions.new!(1000, 5000)
      {:ok, resized} = ImageDimensions.resize_to_width(dims, 500)
      assert resized.width == 500
      assert resized.height == 2500
    end
  end

  describe "portrait?/1" do
    test "returns true for portrait image" do
      dims = ImageDimensions.new!(1080, 1920)
      assert ImageDimensions.portrait?(dims)
    end

    test "returns false for landscape image" do
      dims = ImageDimensions.new!(1920, 1080)
      refute ImageDimensions.portrait?(dims)
    end

    test "returns false for square image" do
      dims = ImageDimensions.new!(1080, 1080)
      refute ImageDimensions.portrait?(dims)
    end

    test "returns true for tall narrow image" do
      dims = ImageDimensions.new!(100, 1000)
      assert ImageDimensions.portrait?(dims)
    end
  end

  describe "landscape?/1" do
    test "returns true for landscape image" do
      dims = ImageDimensions.new!(1920, 1080)
      assert ImageDimensions.landscape?(dims)
    end

    test "returns false for portrait image" do
      dims = ImageDimensions.new!(1080, 1920)
      refute ImageDimensions.landscape?(dims)
    end

    test "returns false for square image" do
      dims = ImageDimensions.new!(1080, 1080)
      refute ImageDimensions.landscape?(dims)
    end

    test "returns true for wide short image" do
      dims = ImageDimensions.new!(1000, 100)
      assert ImageDimensions.landscape?(dims)
    end
  end

  describe "square?/1" do
    test "returns true for square image" do
      dims = ImageDimensions.new!(1080, 1080)
      assert ImageDimensions.square?(dims)
    end

    test "returns false for landscape image" do
      dims = ImageDimensions.new!(1920, 1080)
      refute ImageDimensions.square?(dims)
    end

    test "returns false for portrait image" do
      dims = ImageDimensions.new!(1080, 1920)
      refute ImageDimensions.square?(dims)
    end

    test "returns true for small square image" do
      dims = ImageDimensions.new!(1, 1)
      assert ImageDimensions.square?(dims)
    end

    test "returns true for large square image" do
      dims = ImageDimensions.new!(5000, 5000)
      assert ImageDimensions.square?(dims)
    end
  end

  describe "orientation classification" do
    test "image can only be one orientation type" do
      landscape = ImageDimensions.new!(1920, 1080)
      portrait = ImageDimensions.new!(1080, 1920)
      square = ImageDimensions.new!(1080, 1080)

      # Landscape
      assert ImageDimensions.landscape?(landscape)
      refute ImageDimensions.portrait?(landscape)
      refute ImageDimensions.square?(landscape)

      # Portrait
      assert ImageDimensions.portrait?(portrait)
      refute ImageDimensions.landscape?(portrait)
      refute ImageDimensions.square?(portrait)

      # Square
      assert ImageDimensions.square?(square)
      refute ImageDimensions.portrait?(square)
      refute ImageDimensions.landscape?(square)
    end
  end
end
