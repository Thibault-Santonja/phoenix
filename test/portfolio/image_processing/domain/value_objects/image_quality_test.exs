defmodule Portfolio.ImageProcessing.Domain.ValueObjects.ImageQualityTest do
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageQuality

  doctest ImageQuality

  describe "new/1" do
    test "creates valid quality with value 1 (minimum)" do
      assert {:ok, 1} = ImageQuality.new(1)
    end

    test "creates valid quality with value 100 (maximum)" do
      assert {:ok, 100} = ImageQuality.new(100)
    end

    test "creates valid quality with value 50 (midpoint)" do
      assert {:ok, 50} = ImageQuality.new(50)
    end

    test "creates valid quality with value 75" do
      assert {:ok, 75} = ImageQuality.new(75)
    end

    test "creates valid quality with value 85" do
      assert {:ok, 85} = ImageQuality.new(85)
    end

    test "returns error for quality 0" do
      assert {:error, :invalid_quality} = ImageQuality.new(0)
    end

    test "returns error for quality 101" do
      assert {:error, :invalid_quality} = ImageQuality.new(101)
    end

    test "returns error for negative quality" do
      assert {:error, :invalid_quality} = ImageQuality.new(-1)
    end

    test "returns error for large negative quality" do
      assert {:error, :invalid_quality} = ImageQuality.new(-100)
    end

    test "returns error for quality greater than 100" do
      assert {:error, :invalid_quality} = ImageQuality.new(200)
    end

    test "returns error for nil" do
      assert {:error, :invalid_quality} = ImageQuality.new(nil)
    end

    test "returns error for float" do
      assert {:error, :invalid_quality} = ImageQuality.new(85.5)
    end

    test "returns error for string" do
      assert {:error, :invalid_quality} = ImageQuality.new("85")
    end

    test "returns error for atom" do
      assert {:error, :invalid_quality} = ImageQuality.new(:high)
    end

    test "returns error for boolean" do
      assert {:error, :invalid_quality} = ImageQuality.new(true)
    end
  end

  describe "new!/1" do
    test "creates valid quality with value 85" do
      assert 85 = ImageQuality.new!(85)
    end

    test "creates valid quality with value 1" do
      assert 1 = ImageQuality.new!(1)
    end

    test "creates valid quality with value 100" do
      assert 100 = ImageQuality.new!(100)
    end

    test "raises ArgumentError for invalid quality 0" do
      assert_raise ArgumentError, "Invalid quality: must be between 1 and 100", fn ->
        ImageQuality.new!(0)
      end
    end

    test "raises ArgumentError for invalid quality 101" do
      assert_raise ArgumentError, "Invalid quality: must be between 1 and 100", fn ->
        ImageQuality.new!(101)
      end
    end

    test "raises ArgumentError for negative quality" do
      assert_raise ArgumentError, fn ->
        ImageQuality.new!(-50)
      end
    end

    test "raises ArgumentError for nil" do
      assert_raise ArgumentError, fn ->
        ImageQuality.new!(nil)
      end
    end
  end

  describe "valid?/1" do
    test "returns true for quality 1" do
      assert ImageQuality.valid?(1)
    end

    test "returns true for quality 100" do
      assert ImageQuality.valid?(100)
    end

    test "returns true for quality 50" do
      assert ImageQuality.valid?(50)
    end

    test "returns true for quality 85" do
      assert ImageQuality.valid?(85)
    end

    test "returns false for quality 0" do
      refute ImageQuality.valid?(0)
    end

    test "returns false for quality 101" do
      refute ImageQuality.valid?(101)
    end

    test "returns false for negative quality" do
      refute ImageQuality.valid?(-10)
    end

    test "returns false for nil" do
      refute ImageQuality.valid?(nil)
    end

    test "returns false for float" do
      refute ImageQuality.valid?(85.5)
    end

    test "returns false for string" do
      refute ImageQuality.valid?("85")
    end
  end

  describe "min/0" do
    test "returns minimum quality value" do
      assert ImageQuality.min() == 1
    end

    test "minimum value is valid" do
      min = ImageQuality.min()
      assert ImageQuality.valid?(min)
    end
  end

  describe "max/0" do
    test "returns maximum quality value" do
      assert ImageQuality.max() == 100
    end

    test "maximum value is valid" do
      max = ImageQuality.max()
      assert ImageQuality.valid?(max)
    end
  end

  describe "category/1" do
    test "categorizes quality 1 as low" do
      assert ImageQuality.category(1) == :low
    end

    test "categorizes quality 25 as low" do
      assert ImageQuality.category(25) == :low
    end

    test "categorizes quality 50 as low" do
      assert ImageQuality.category(50) == :low
    end

    test "categorizes quality 51 as medium" do
      assert ImageQuality.category(51) == :medium
    end

    test "categorizes quality 60 as medium" do
      assert ImageQuality.category(60) == :medium
    end

    test "categorizes quality 75 as medium" do
      assert ImageQuality.category(75) == :medium
    end

    test "categorizes quality 76 as high" do
      assert ImageQuality.category(76) == :high
    end

    test "categorizes quality 85 as high" do
      assert ImageQuality.category(85) == :high
    end

    test "categorizes quality 90 as high" do
      assert ImageQuality.category(90) == :high
    end

    test "categorizes quality 91 as very_high" do
      assert ImageQuality.category(91) == :very_high
    end

    test "categorizes quality 95 as very_high" do
      assert ImageQuality.category(95) == :very_high
    end

    test "categorizes quality 100 as very_high" do
      assert ImageQuality.category(100) == :very_high
    end
  end

  describe "category boundaries" do
    test "low category includes 1-50" do
      for quality <- 1..50 do
        assert ImageQuality.category(quality) == :low
      end
    end

    test "medium category includes 51-75" do
      for quality <- 51..75 do
        assert ImageQuality.category(quality) == :medium
      end
    end

    test "high category includes 76-90" do
      for quality <- 76..90 do
        assert ImageQuality.category(quality) == :high
      end
    end

    test "very_high category includes 91-100" do
      for quality <- 91..100 do
        assert ImageQuality.category(quality) == :very_high
      end
    end
  end

  describe "integration scenarios" do
    test "all valid qualities can be created and categorized" do
      for quality <- 1..100 do
        assert {:ok, ^quality} = ImageQuality.new(quality)
        assert ImageQuality.valid?(quality)
        category = ImageQuality.category(quality)
        assert category in [:low, :medium, :high, :very_high]
      end
    end

    test "min and max form valid range" do
      min = ImageQuality.min()
      max = ImageQuality.max()
      assert min < max
      assert {:ok, ^min} = ImageQuality.new(min)
      assert {:ok, ^max} = ImageQuality.new(max)
    end
  end
end
