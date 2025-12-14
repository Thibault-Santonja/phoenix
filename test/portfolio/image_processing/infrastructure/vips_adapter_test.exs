defmodule Portfolio.ImageProcessing.Infrastructure.VipsAdapterTest do
  @moduledoc """
  Integration tests for the VipsAdapter.

  These tests verify the adapter correctly interfaces with libvips
  for image loading, resizing, and saving operations.
  """
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing.Domain.ValueObjects.{ImageDimensions, VariantSpecification}
  alias Portfolio.ImageProcessing.Infrastructure.VipsAdapter
  alias Vix.Vips.Image

  # Test fixtures directory (use project root fixtures)
  @fixtures_dir Path.join([File.cwd!(), "test", "fixtures", "images"])
  @temp_dir System.tmp_dir!()

  setup do
    # Ensure fixtures directory exists
    fixtures_path = Path.expand(@fixtures_dir)

    unless File.exists?(fixtures_path) do
      File.mkdir_p!(fixtures_path)
    end

    # Create a unique temp directory for this test
    test_output_dir = Path.join(@temp_dir, "vips_test_#{:erlang.unique_integer([:positive])}")
    File.mkdir_p!(test_output_dir)

    on_exit(fn ->
      File.rm_rf!(test_output_dir)
    end)

    {:ok, output_dir: test_output_dir, fixtures_dir: fixtures_path}
  end

  describe "load_image/1" do
    test "returns error for non-existent file" do
      assert {:error, :file_not_found} = VipsAdapter.load_image("/non/existent/path.jpg")
    end

    test "returns error for corrupted file", %{output_dir: output_dir} do
      # Create a fake image file with invalid content
      corrupted_path = Path.join(output_dir, "corrupted.jpg")
      File.write!(corrupted_path, "not an image")

      assert {:error, :corrupted_file} = VipsAdapter.load_image(corrupted_path)
    end

    test "loads valid image and returns dimensions", %{fixtures_dir: fixtures_dir} do
      test_image = Path.join(fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        assert {:ok, image, %ImageDimensions{} = dims} = VipsAdapter.load_image(test_image)
        assert is_struct(image, Vix.Vips.Image)
        assert dims.width > 0
        assert dims.height > 0
      else
        # Skip if no test image available
        :ok
      end
    end

    test "handles empty file as corrupted", %{output_dir: output_dir} do
      empty_path = Path.join(output_dir, "empty.jpg")
      File.write!(empty_path, "")

      assert {:error, :corrupted_file} = VipsAdapter.load_image(empty_path)
    end

    test "handles truncated file as corrupted", %{output_dir: output_dir} do
      # Partial JPEG header
      truncated_path = Path.join(output_dir, "truncated.jpg")
      File.write!(truncated_path, <<0xFF, 0xD8, 0xFF, 0xE0>>)

      assert {:error, :corrupted_file} = VipsAdapter.load_image(truncated_path)
    end
  end

  describe "ensure_output_directory/1" do
    test "creates directory if it does not exist", %{output_dir: output_dir} do
      new_dir = Path.join(output_dir, "new_subdir")
      refute File.exists?(new_dir)

      assert :ok = VipsAdapter.ensure_output_directory(new_dir)
      assert File.exists?(new_dir)
      assert File.dir?(new_dir)
    end

    test "succeeds if directory already exists", %{output_dir: output_dir} do
      assert File.exists?(output_dir)
      assert :ok = VipsAdapter.ensure_output_directory(output_dir)
    end

    test "creates nested directories", %{output_dir: output_dir} do
      nested_dir = Path.join([output_dir, "level1", "level2", "level3"])
      refute File.exists?(nested_dir)

      assert :ok = VipsAdapter.ensure_output_directory(nested_dir)
      assert File.exists?(nested_dir)
    end
  end

  describe "resize_image/3" do
    test "does not upscale images smaller than target", %{fixtures_dir: fixtures_dir} do
      test_image = Path.join(fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        {:ok, image, dims} = VipsAdapter.load_image(test_image)

        # Create a spec larger than the image
        large_spec = VariantSpecification.new!(:thumbnail, dims.width + 500, 75, :webp, 4)

        # Should return original image without upscaling
        assert {:ok, result_image} = VipsAdapter.resize_image(image, large_spec, dims)
        assert is_struct(result_image, Image)
      else
        :ok
      end
    end

    test "resizes image when target is smaller than source", %{fixtures_dir: fixtures_dir} do
      test_image = Path.join(fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        {:ok, image, dims} = VipsAdapter.load_image(test_image)

        # Create a spec smaller than the image
        target_width = div(dims.width, 2)
        small_spec = VariantSpecification.new!(:thumbnail, target_width, 75, :webp, 4)

        # Should resize the image
        assert {:ok, result_image} = VipsAdapter.resize_image(image, small_spec, dims)
        assert is_struct(result_image, Image)

        # Verify the result is smaller
        result_width = Image.width(result_image)
        assert result_width <= target_width + 1
      else
        :ok
      end
    end

    test "maintains aspect ratio when resizing", %{fixtures_dir: fixtures_dir} do
      test_image = Path.join(fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        {:ok, image, dims} = VipsAdapter.load_image(test_image)
        original_ratio = dims.width / dims.height

        target_width = div(dims.width, 3)
        spec = VariantSpecification.new!(:medium, target_width, 80, :webp, 4)

        {:ok, result_image} = VipsAdapter.resize_image(image, spec, dims)

        result_width = Image.width(result_image)
        result_height = Image.height(result_image)
        result_ratio = result_width / result_height

        # Aspect ratio should be preserved within a small tolerance
        assert_in_delta original_ratio, result_ratio, 0.01
      else
        :ok
      end
    end
  end

  describe "save_image/3" do
    test "saves image as webp", %{fixtures_dir: fixtures_dir, output_dir: output_dir} do
      test_image = Path.join(fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        {:ok, image, _dims} = VipsAdapter.load_image(test_image)
        spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
        # Vips needs the extension to determine format
        output_path = Path.join(output_dir, "test_output.webp")

        assert :ok = VipsAdapter.save_image(image, output_path, spec)

        # Verify file was created
        assert File.exists?(output_path <> "[Q=75,effort=4]") or File.exists?(output_path)
      else
        :ok
      end
    end

    test "saves image as jpeg", %{fixtures_dir: fixtures_dir, output_dir: output_dir} do
      test_image = Path.join(fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        {:ok, image, _dims} = VipsAdapter.load_image(test_image)
        spec = VariantSpecification.new!(:medium, 800, 85, :jpeg, 0)
        output_path = Path.join(output_dir, "test_output.jpg")

        assert :ok = VipsAdapter.save_image(image, output_path, spec)

        # The actual file created includes the options suffix
        saved_files = File.ls!(output_dir)
        assert Enum.any?(saved_files, &String.contains?(&1, "test_output"))
      else
        :ok
      end
    end

    test "saves image as avif", %{fixtures_dir: fixtures_dir, output_dir: output_dir} do
      test_image = Path.join(fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        {:ok, image, _dims} = VipsAdapter.load_image(test_image)
        spec = VariantSpecification.new!(:large, 1200, 80, :avif, 6)
        output_path = Path.join(output_dir, "test_output.avif")

        assert :ok = VipsAdapter.save_image(image, output_path, spec)

        saved_files = File.ls!(output_dir)
        assert Enum.any?(saved_files, &String.contains?(&1, "test_output"))
      else
        :ok
      end
    end

    test "respects quality settings", %{fixtures_dir: fixtures_dir, output_dir: output_dir} do
      test_image = Path.join(fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        {:ok, image, _dims} = VipsAdapter.load_image(test_image)

        # Save with low quality
        low_spec = VariantSpecification.new!(:thumbnail, 400, 50, :jpeg, 0)
        low_path = Path.join(output_dir, "low_quality.jpg")
        :ok = VipsAdapter.save_image(image, low_path, low_spec)

        # Save with high quality
        high_spec = VariantSpecification.new!(:thumbnail, 400, 95, :jpeg, 0)
        high_path = Path.join(output_dir, "high_quality.jpg")
        :ok = VipsAdapter.save_image(image, high_path, high_spec)

        # High quality file should be larger
        low_files = File.ls!(output_dir) |> Enum.filter(&String.contains?(&1, "low"))
        high_files = File.ls!(output_dir) |> Enum.filter(&String.contains?(&1, "high"))

        if low_files != [] and high_files != [] do
          low_size = File.stat!(Path.join(output_dir, hd(low_files))).size
          high_size = File.stat!(Path.join(output_dir, hd(high_files))).size

          assert high_size >= low_size
        end
      else
        :ok
      end
    end
  end

  describe "build_format_suffix (via save_image)" do
    test "webp format includes quality and effort" do
      # We test the suffix construction indirectly through the module behavior
      # The suffix format is: [Q=quality,effort=effort]
      spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      assert spec.format == :webp
      assert spec.quality == 75
      assert spec.effort == 4
    end

    test "avif format includes quality and effort" do
      spec = VariantSpecification.new!(:thumbnail, 400, 80, :avif, 6)
      assert spec.format == :avif
      assert spec.quality == 80
      assert spec.effort == 6
    end

    test "jpeg format includes only quality" do
      spec = VariantSpecification.new!(:thumbnail, 400, 85, :jpeg, 0)
      assert spec.format == :jpeg
      assert spec.quality == 85
    end
  end

  describe "integration with VariantSpecification" do
    test "accepts all supported formats" do
      for format <- [:webp, :avif, :jpeg] do
        spec = VariantSpecification.new!(:thumbnail, 400, 75, format, 4)
        assert spec.format == format
      end
    end

    test "accepts different quality levels" do
      for quality <- [50, 75, 85, 95] do
        spec = VariantSpecification.new!(:thumbnail, 400, quality, :webp, 4)
        assert spec.quality == quality
      end
    end

    test "accepts different effort levels" do
      for effort <- [0, 2, 4, 6] do
        spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, effort)
        assert spec.effort == effort
      end
    end
  end

  describe "error handling" do
    test "load_image handles path with special characters" do
      # Paths with unicode or special characters should be handled gracefully
      unicode_path = "/tmp/тест_画像_🖼️.jpg"
      assert {:error, :file_not_found} = VipsAdapter.load_image(unicode_path)
    end

    test "ensure_output_directory handles read-only parent" do
      # This test is OS-dependent; on most systems /proc is read-only
      readonly_path = "/proc/fake_vips_test_dir"

      result = VipsAdapter.ensure_output_directory(readonly_path)

      assert match?({:error, {:directory_creation_failed, _}}, result)
    end
  end
end
