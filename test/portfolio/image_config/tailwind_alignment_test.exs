defmodule Portfolio.ImageConfig.TailwindAlignmentTest do
  @moduledoc """
  Tests for image variant sizes aligned with Tailwind CSS breakpoints.

  According to ADR-011 Phase 4, variant sizes should align with Tailwind
  breakpoints for optimal responsive image display and reduced bandwidth.

  ## Target Configuration (ADR-011)

  - thumbnail: 400px (Tailwind xs/sm range)
  - small: 768px (Tailwind md breakpoint)
  - medium: 1280px (Tailwind xl breakpoint)
  - large: 1920px (Full HD, unchanged)

  ## Quality Settings

  Quality should increase with size for professional portfolio standard:
  - thumbnail: 75 (acceptable for small preview)
  - small: 80 (good for tablet display)
  - medium: 85 (high quality for desktop)
  - large: 90 (maximum quality for fullscreen)

  ## Expected Benefits

  - 10-15% reduction in total weight (better granularity)
  - Optimal sizes per Tailwind breakpoint
  - Improved UX responsive
  """
  use ExUnit.Case, async: true

  alias Portfolio.ImageConfig

  @tailwind_breakpoints %{
    xs: 0,
    sm: 640,
    md: 768,
    lg: 1024,
    xl: 1280,
    "2xl": 1536
  }

  describe "Tailwind breakpoint alignment" do
    test "thumbnail variant aligns with Tailwind xs/sm (400px)" do
      # Target: 400px for cards and previews in xs/sm range (0-768px)
      assert ImageConfig.variant_width(:thumbnail) == 400
    end

    test "small variant aligns with Tailwind md breakpoint (768px)" do
      # Target: 768px for tablets (Tailwind md breakpoint)
      assert ImageConfig.variant_width(:small) == 768
    end

    test "medium variant aligns with Tailwind xl breakpoint (1280px)" do
      # Target: 1280px for desktop (Tailwind xl breakpoint)
      assert ImageConfig.variant_width(:medium) == 1280
    end

    test "large variant remains 1920px for Full HD display" do
      # Target: 1920px for fullscreen original (unchanged)
      assert ImageConfig.variant_width(:large) == 1920
    end
  end

  describe "quality progression" do
    test "thumbnail has quality 75 (acceptable for small previews)" do
      assert ImageConfig.variant_quality(:thumbnail) == 75
    end

    test "small has quality 80 (good for tablet display)" do
      assert ImageConfig.variant_quality(:small) == 80
    end

    test "medium has quality 85 (high quality for desktop)" do
      assert ImageConfig.variant_quality(:medium) == 85
    end

    test "large has quality 90 (maximum quality for fullscreen)" do
      # ADR-011: Quality increased to 90 for professional portfolio standard
      assert ImageConfig.variant_quality(:large) == 90
    end

    test "quality increases monotonically with width" do
      variants = ImageConfig.variants()

      sorted_by_width =
        variants
        |> Enum.sort_by(fn {_name, config} -> config.width end)

      qualities =
        sorted_by_width
        |> Enum.map(fn {_name, config} -> config.quality end)

      # Each quality should be >= previous quality (monotonic increase)
      qualities
      |> Enum.chunk_every(2, 1, :discard)
      |> Enum.each(fn [prev_quality, next_quality] ->
        assert next_quality >= prev_quality,
               "Quality should increase with width: #{prev_quality} -> #{next_quality}"
      end)
    end
  end

  describe "optimal responsive coverage" do
    test "variants cover all major Tailwind breakpoint ranges" do
      widths = [
        ImageConfig.variant_width(:thumbnail),
        ImageConfig.variant_width(:small),
        ImageConfig.variant_width(:medium),
        ImageConfig.variant_width(:large)
      ]

      # Should cover: xs/sm (0-768), md (768-1024), lg/xl (1024-1536), 2xl+ (1536+)
      # With: 400px, 768px, 1280px, 1920px

      # Verify reasonable coverage
      assert Enum.at(widths, 0) < @tailwind_breakpoints.md,
             "Thumbnail should cover xs/sm range"

      assert Enum.at(widths, 1) >= @tailwind_breakpoints.md,
             "Small should cover md+ range"

      assert Enum.at(widths, 2) >= @tailwind_breakpoints.xl,
             "Medium should cover xl+ range"

      assert Enum.at(widths, 3) >= @tailwind_breakpoints[:"2xl"],
             "Large should cover 2xl+ range"
    end

    test "no significant gaps between consecutive variant sizes" do
      widths =
        ImageConfig.srcset_variants()
        |> Enum.map(&ImageConfig.variant_width/1)

      # Calculate gaps between consecutive widths
      gaps =
        widths
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, next] -> next - prev end)

      # Maximum gap should not exceed 2x previous width (reasonable scaling)
      widths
      |> Enum.zip(gaps)
      |> Enum.each(fn {width, gap} ->
        assert gap <= width * 2,
               "Gap between variants too large: #{gap}px after #{width}px variant"
      end)
    end
  end

  describe "performance optimization" do
    test "total variant count remains 4 (no complexity increase)" do
      # Should maintain 4 variants for simplicity
      assert map_size(ImageConfig.variants()) == 4
    end

    test "width progression follows reasonable scaling factor" do
      widths =
        ImageConfig.srcset_variants()
        |> Enum.map(&ImageConfig.variant_width/1)

      # Calculate scaling factors between consecutive widths
      scaling_factors =
        widths
        |> Enum.chunk_every(2, 1, :discard)
        |> Enum.map(fn [prev, next] -> next / prev end)

      # Scaling factor should be between 1.5x and 2x (reasonable progression)
      # 400 -> 768 = 1.92x
      # 768 -> 1280 = 1.67x
      # 1280 -> 1920 = 1.5x
      Enum.each(scaling_factors, fn factor ->
        assert factor >= 1.5 and factor <= 2.0,
               "Scaling factor should be between 1.5x and 2x, got #{factor}"
      end)
    end
  end

  describe "configuration validation" do
    test "all variants use exact target widths from ADR-011" do
      expected_widths = %{
        thumbnail: 400,
        small: 768,
        medium: 1280,
        large: 1920
      }

      for {variant_name, expected_width} <- expected_widths do
        actual_width = ImageConfig.variant_width(variant_name)

        assert actual_width == expected_width,
               "Expected #{variant_name} width to be #{expected_width}px (Tailwind-aligned), got #{actual_width}px"
      end
    end

    test "all variants use exact target qualities from ADR-011" do
      expected_qualities = %{
        thumbnail: 75,
        small: 80,
        medium: 85,
        large: 90
      }

      for {variant_name, expected_quality} <- expected_qualities do
        actual_quality = ImageConfig.variant_quality(variant_name)

        assert actual_quality == expected_quality,
               "Expected #{variant_name} quality to be #{expected_quality}, got #{actual_quality}"
      end
    end
  end
end
