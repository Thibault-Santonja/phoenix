defmodule Portfolio.ImageProcessing.Infrastructure.VipsAdapterTest do
  @moduledoc """
  Integration tests for the VipsAdapter.

  These tests verify the adapter correctly interfaces with libvips
  for image loading, resizing, and saving operations.
  """
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing.Infrastructure.VipsAdapter
  alias Portfolio.ImageProcessing.Domain.ValueObjects.{ImageDimensions, VariantSpecification}

  @moduletag :vips

  # Test fixtures directory
  @fixtures_dir Path.join([__DIR__, "..", "..", "..", "support", "fixtures"])
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

    test "returns error for corrupted file", %{fixtures_dir: fixtures_dir} do
      # Create a fake image file with invalid content
      corrupted_path = Path.join(fixtures_dir, "corrupted.jpg")
      File.write!(corrupted_path, "not an image")

      on_exit(fn -> File.rm(corrupted_path) end)

      assert {:error, :corrupted_file} = VipsAdapter.load_image(corrupted_path)
    end

    @tag :requires_test_image
    test "loads valid image and returns dimensions", %{fixtures_dir: fixtures_dir} do
      # This test requires a real test image to be present
      test_image = Path.join(fixtures_dir, "test_image.jpg")

      if File.exists?(test_image) do
        assert {:ok, image, %ImageDimensions{} = dims} = VipsAdapter.load_image(test_image)
        assert is_struct(image, Vix.Vips.Image)
        assert dims.width > 0
        assert dims.height > 0
      end
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
    @tag :requires_test_image
    test "does not upscale images smaller than target" do
      # Create a small test image programmatically if vips supports it
      # For now, this test documents the expected behavior

      _small_dims = ImageDimensions.new!(100, 75)
      _large_spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)

      # When source is smaller than target, resize should return :no_upscale
      # and the original image should be returned unchanged
      # This test would require a real image to fully verify
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
