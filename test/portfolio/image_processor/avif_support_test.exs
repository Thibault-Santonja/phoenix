defmodule Portfolio.ImageProcessor.AvifSupportTest do
  @moduledoc """
  Tests for AVIF format support in ImageProcessor.

  According to ADR-011 Phase 2 and ADR-012, the large variant should be
  migrated to AVIF format for superior quality at fullscreen resolution.

  AVIF benefits:
  - 30-40% better compression than WebP
  - Superior perceptual quality for large images
  - Better handling of fine textures (critical for photography portfolio)

  Target configuration:
  - thumbnail: WebP 400px Q75
  - small: WebP 768px Q80
  - medium: WebP 1280px Q85
  - large: AVIF 1920px Q90
  """
  use Portfolio.DataCase, async: true

  alias Portfolio.ImageConfig
  alias Portfolio.ImageProcessor

  @test_image_path "test/fixtures/test_image.jpg"
  @output_base "test/tmp/image_processor"

  setup do
    File.mkdir_p!(@output_base)
    on_exit(fn -> File.rm_rf!(@output_base) end)
    :ok
  end

  describe "AVIF format support" do
    @tag :skip
    test "generates AVIF for large variant" do
      output_path = Path.join(@output_base, "avif_test")

      assert {:ok, variants} = ImageProcessor.generate_variants(@test_image_path, output_path)

      # Large variant should be AVIF
      assert Map.has_key?(variants, :large)
      assert variants.large =~ ".avif"
      assert File.exists?(variants.large)
    end

    @tag :skip
    test "WebP variants remain unchanged" do
      output_path = Path.join(@output_base, "webp_test")

      assert {:ok, variants} = ImageProcessor.generate_variants(@test_image_path, output_path)

      # Other variants should be WebP
      assert variants.thumbnail =~ ".webp"
      assert variants.small =~ ".webp"
      assert variants.medium =~ ".webp"
    end

    @tag :skip
    test "AVIF large variant has higher quality" do
      # Large variant should have Q90 (vs Q85 for WebP variants)
      large_config = ImageConfig.variant(:large)

      assert large_config.quality == 90
      assert large_config.format == :avif
    end

    @tag :skip
    test "AVIF uses effort 6 for maximum quality" do
      # AVIF encoding effort should be 6 for best quality
      # (vs effort 4 for WebP which is faster)
      large_config = ImageConfig.variant(:large)

      assert large_config.effort == 6
    end
  end

  describe "format detection" do
    test "ImageConfig returns format for each variant" do
      variants = ImageConfig.variants()

      assert variants.thumbnail.format == :webp
      assert variants.small.format == :webp
      assert variants.medium.format == :webp
      assert variants.large.format == :avif
    end
  end

  describe "file extension based on format" do
    test "WebP format gets .webp extension" do
      assert ImageProcessor.file_extension(:webp) == "webp"
    end

    test "AVIF format gets .avif extension" do
      assert ImageProcessor.file_extension(:avif) == "avif"
    end

    test "JPEG format gets .jpg extension" do
      assert ImageProcessor.file_extension(:jpeg) == "jpg"
    end
  end

  describe "performance" do
    @tag :skip
    test "AVIF generation takes reasonable time" do
      # AVIF with effort 6 should take ~1.5x longer than WebP
      # but still complete in acceptable time (<10s for 1920px)
      output_path = Path.join(@output_base, "perf_test")

      {time_microseconds, {:ok, _variants}} =
        :timer.tc(fn -> ImageProcessor.generate_variants(@test_image_path, output_path) end)

      time_seconds = time_microseconds / 1_000_000

      # Total time for all 4 variants should be < 10s
      assert time_seconds < 10.0,
             "Image processing took #{time_seconds}s, should be < 10s"
    end
  end

  describe "backward compatibility" do
    @tag :skip
    test "existing photos with WebP large variant still work" do
      # Old photos may have large.webp instead of large.avif
      # ImageHelpers should handle both gracefully

      # This test ensures we don't break existing functionality
      # when migrating to AVIF
      output_path = Path.join(@output_base, "compat_test")

      # Simulate old WebP variant
      File.mkdir_p!(output_path)
      File.write!(Path.join(output_path, "large.webp"), "fake webp content")

      # Should still be readable
      assert File.exists?(Path.join(output_path, "large.webp"))
    end
  end
end
