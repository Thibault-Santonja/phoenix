defmodule Portfolio.VixTest do
  @moduledoc """
  Test suite to verify libvips and Vix installation.
  This ensures that the image processing infrastructure is properly configured.
  """
  use ExUnit.Case, async: true

  alias Vix.Vips.Image

  describe "libvips installation" do
    test "Vix can retrieve libvips version" do
      version = Vix.Vips.version()
      assert is_binary(version)
      assert String.match?(version, ~r/\d+\.\d+/)
    end
  end

  describe "basic image operations" do
    test "can create a test image and get dimensions" do
      # Create a minimal 1x1 PNG image in memory
      # PNG magic number + minimal IHDR chunk for 1x1 image
      image_data =
        <<137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82, 0, 0, 0, 1, 0, 0, 0, 1, 8,
          6, 0, 0, 0, 31, 21, 196, 137, 0, 0, 0, 13, 73, 68, 65, 84, 8, 153, 99, 0, 1, 0, 0, 5, 0,
          1, 13, 10, 43, 180, 0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130>>

      # Write to a temporary file
      temp_path = Path.join(System.tmp_dir!(), "test_image_#{System.unique_integer()}.png")
      File.write!(temp_path, image_data)

      # Clean up after test
      on_exit(fn -> File.rm(temp_path) end)

      # Test that Vix can load and read the image
      {:ok, image} = Image.new_from_file(temp_path)
      width = Image.width(image)
      height = Image.height(image)

      assert width == 1
      assert height == 1
    end
  end
end
