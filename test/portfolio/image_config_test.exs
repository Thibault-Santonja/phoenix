defmodule Portfolio.ImageConfigTest do
  @moduledoc """
  Tests for centralized image configuration module.

  This module provides a single source of truth for image variant
  configurations, avoiding duplication across ImageProcessor and ImageHelpers.
  """
  use ExUnit.Case, async: true

  alias Portfolio.ImageConfig

  describe "variants/0" do
    test "returns map of all image variants" do
      variants = ImageConfig.variants()

      assert is_map(variants)
      assert map_size(variants) > 0
    end

    test "includes all expected variant keys" do
      variants = ImageConfig.variants()

      # Current variants from config
      assert Map.has_key?(variants, :thumbnail)
      assert Map.has_key?(variants, :small)
      assert Map.has_key?(variants, :medium)
      assert Map.has_key?(variants, :large)
    end

    test "each variant has required configuration keys" do
      variants = ImageConfig.variants()

      for {_name, config} <- variants do
        assert Map.has_key?(config, :width)
        assert Map.has_key?(config, :quality)

        # Validate types
        assert is_integer(config.width)
        assert config.width > 0
        assert is_integer(config.quality)
        assert config.quality > 0
        assert config.quality <= 100
      end
    end
  end

  describe "variant/1" do
    test "returns configuration for valid variant" do
      config = ImageConfig.variant(:thumbnail)

      assert is_map(config)
      assert Map.has_key?(config, :width)
      assert Map.has_key?(config, :quality)
    end

    test "returns nil for unknown variant" do
      assert ImageConfig.variant(:nonexistent) == nil
    end

    test "works with string keys" do
      config = ImageConfig.variant("thumbnail")

      assert is_map(config)
      assert config.width > 0
    end
  end

  describe "variant_width/1" do
    test "returns width for valid variant" do
      width = ImageConfig.variant_width(:thumbnail)

      assert is_integer(width)
      assert width > 0
    end

    test "returns nil for unknown variant" do
      assert ImageConfig.variant_width(:nonexistent) == nil
    end

    test "returns expected widths from application config" do
      # These should match config/config.exs values
      config_variants = Application.get_env(:portfolio, :image_variants)

      for {variant_name, variant_config} <- config_variants do
        expected_width = variant_config[:width]
        actual_width = ImageConfig.variant_width(variant_name)

        assert actual_width == expected_width,
               "Expected width for #{variant_name} to be #{expected_width}, got #{actual_width}"
      end
    end
  end

  describe "variant_quality/1" do
    test "returns quality for valid variant" do
      quality = ImageConfig.variant_quality(:thumbnail)

      assert is_integer(quality)
      assert quality > 0
      assert quality <= 100
    end

    test "returns nil for unknown variant" do
      assert ImageConfig.variant_quality(:nonexistent) == nil
    end

    test "returns expected qualities from application config" do
      config_variants = Application.get_env(:portfolio, :image_variants)

      for {variant_name, variant_config} <- config_variants do
        expected_quality = variant_config[:quality]
        actual_quality = ImageConfig.variant_quality(variant_name)

        assert actual_quality == expected_quality,
               "Expected quality for #{variant_name} to be #{expected_quality}, got #{actual_quality}"
      end
    end
  end

  describe "variant_widths/0" do
    test "returns map with string keys" do
      widths = ImageConfig.variant_widths()

      assert is_map(widths)

      # All keys should be strings
      for key <- Map.keys(widths) do
        assert is_binary(key), "Expected string key, got: #{inspect(key)}"
      end
    end

    test "returns width values for all variants" do
      widths = ImageConfig.variant_widths()

      assert is_integer(widths["thumbnail"])
      assert is_integer(widths["small"])
      assert is_integer(widths["medium"])
      assert is_integer(widths["large"])
    end

    test "string keys match atom variant names" do
      variants = ImageConfig.variants()
      widths = ImageConfig.variant_widths()

      for {atom_key, config} <- variants do
        string_key = Atom.to_string(atom_key)
        assert widths[string_key] == config.width
      end
    end
  end

  describe "default_variant/0" do
    test "returns a valid variant name" do
      default = ImageConfig.default_variant()

      assert is_atom(default)
      assert ImageConfig.variant(default) != nil
    end

    test "default variant exists in variants map" do
      default = ImageConfig.default_variant()
      variants = ImageConfig.variants()

      assert Map.has_key?(variants, default),
             "Default variant #{default} not found in variants"
    end
  end

  describe "max_width/0" do
    test "returns the largest width across all variants" do
      max_width = ImageConfig.max_width()
      variants = ImageConfig.variants()

      # Find actual max width
      actual_max =
        variants
        |> Map.values()
        |> Enum.map(& &1.width)
        |> Enum.max()

      assert max_width == actual_max
    end

    test "max width is greater than all individual variant widths" do
      max_width = ImageConfig.max_width()
      variants = ImageConfig.variants()

      for {_name, config} <- variants do
        assert max_width >= config.width
      end
    end
  end

  describe "srcset_variants/0" do
    test "returns list of variant names suitable for srcset" do
      srcset_variants = ImageConfig.srcset_variants()

      assert is_list(srcset_variants)
      assert srcset_variants != []
    end

    test "all srcset variants exist in main variants" do
      srcset_variants = ImageConfig.srcset_variants()
      all_variants = ImageConfig.variants()

      for variant_name <- srcset_variants do
        assert Map.has_key?(all_variants, variant_name),
               "Srcset variant #{variant_name} not found in main variants"
      end
    end

    test "srcset variants are ordered by width ascending" do
      srcset_variants = ImageConfig.srcset_variants()

      widths =
        Enum.map(srcset_variants, fn variant ->
          ImageConfig.variant_width(variant)
        end)

      assert widths == Enum.sort(widths),
             "Srcset variants should be ordered by width (ascending)"
    end
  end

  describe "configuration consistency" do
    test "no duplicate widths across variants" do
      variants = ImageConfig.variants()

      widths =
        variants
        |> Map.values()
        |> Enum.map(& &1.width)

      unique_widths = Enum.uniq(widths)

      assert length(widths) == length(unique_widths),
             "Found duplicate widths across variants"
    end

    test "all variants have reasonable quality settings" do
      variants = ImageConfig.variants()

      for {_name, config} <- variants do
        assert config.quality >= 70,
               "Quality should be at least 70 for acceptable image quality"

        assert config.quality <= 95,
               "Quality above 95 provides diminishing returns in file size"
      end
    end

    test "larger variants do not have dramatically lower quality" do
      variants = ImageConfig.variants()
      sorted_variants = Enum.sort_by(variants, fn {_name, config} -> config.width end)

      qualities = Enum.map(sorted_variants, fn {_name, config} -> config.quality end)

      min_quality = Enum.min(qualities)
      max_quality = Enum.max(qualities)

      # Quality variance should not be too large (within 20 points)
      assert max_quality - min_quality <= 20,
             "Quality variance too large: #{min_quality} to #{max_quality}"
    end
  end
end
