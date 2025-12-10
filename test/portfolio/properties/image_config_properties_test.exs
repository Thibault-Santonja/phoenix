defmodule Portfolio.Properties.ImageConfigPropertiesTest do
  @moduledoc """
  Property-based tests for ImageConfig module.

  Tests invariants for image configuration consistency.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolio.ImageConfig

  describe "variants/0 properties" do
    test "returns a map" do
      variants = ImageConfig.variants()
      assert is_map(variants)
    end

    test "all variant names are atoms" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, _config} ->
        assert is_atom(name)
      end)
    end

    test "all variant configs have required keys" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {_name, config} ->
        assert Map.has_key?(config, :width)
        assert Map.has_key?(config, :quality)
        assert Map.has_key?(config, :format)
        assert Map.has_key?(config, :effort)
      end)
    end

    test "all widths are positive integers" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, config} ->
        assert is_integer(config.width),
               "Variant #{name} width should be integer"

        assert config.width > 0,
               "Variant #{name} width should be positive"
      end)
    end

    test "all qualities are in valid range (1-100)" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, config} ->
        assert is_integer(config.quality),
               "Variant #{name} quality should be integer"

        assert config.quality >= 1 and config.quality <= 100,
               "Variant #{name} quality should be between 1 and 100"
      end)
    end

    test "all formats are valid atoms" do
      valid_formats = [:webp, :avif, :jpeg]
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, config} ->
        assert config.format in valid_formats,
               "Variant #{name} format #{config.format} should be one of #{inspect(valid_formats)}"
      end)
    end

    test "all efforts are non-negative integers" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, config} ->
        assert is_integer(config.effort),
               "Variant #{name} effort should be integer"

        assert config.effort >= 0,
               "Variant #{name} effort should be non-negative"
      end)
    end
  end

  describe "variant/1 properties" do
    test "variant by atom returns same as from variants map" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, expected_config} ->
        assert ImageConfig.variant(name) == expected_config
      end)
    end

    test "variant by string returns same as by atom" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, _config} ->
        atom_result = ImageConfig.variant(name)
        string_result = ImageConfig.variant(Atom.to_string(name))
        assert atom_result == string_result
      end)
    end

    test "nonexistent variant returns nil" do
      assert ImageConfig.variant(:definitely_not_a_variant) == nil
      assert ImageConfig.variant("also_not_a_variant") == nil
    end
  end

  describe "variant_width/1 properties" do
    test "matches width from variant config" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, config} ->
        assert ImageConfig.variant_width(name) == config.width
      end)
    end

    test "nonexistent variant returns nil" do
      assert ImageConfig.variant_width(:nonexistent) == nil
    end
  end

  describe "variant_quality/1 properties" do
    test "matches quality from variant config" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, config} ->
        assert ImageConfig.variant_quality(name) == config.quality
      end)
    end

    test "nonexistent variant returns nil" do
      assert ImageConfig.variant_quality(:nonexistent) == nil
    end
  end

  describe "variant_widths/0 properties" do
    test "returns map with string keys" do
      widths = ImageConfig.variant_widths()

      Enum.each(widths, fn {key, _value} ->
        assert is_binary(key)
      end)
    end

    test "all values are positive integers" do
      widths = ImageConfig.variant_widths()

      Enum.each(widths, fn {name, width} ->
        assert is_integer(width), "Width for #{name} should be integer"
        assert width > 0, "Width for #{name} should be positive"
      end)
    end

    test "keys match atom variants converted to strings" do
      variants = ImageConfig.variants()
      widths = ImageConfig.variant_widths()

      variant_names = variants |> Map.keys() |> Enum.map(&Atom.to_string/1) |> MapSet.new()
      width_names = widths |> Map.keys() |> MapSet.new()

      assert variant_names == width_names
    end

    test "widths match variant configs" do
      variants = ImageConfig.variants()
      widths = ImageConfig.variant_widths()

      Enum.each(variants, fn {name, config} ->
        string_name = Atom.to_string(name)
        assert widths[string_name] == config.width
      end)
    end
  end

  describe "max_width/0 properties" do
    test "returns positive integer" do
      max = ImageConfig.max_width()
      assert is_integer(max)
      assert max > 0
    end

    test "equals maximum of all variant widths" do
      variants = ImageConfig.variants()
      expected_max = variants |> Map.values() |> Enum.map(& &1.width) |> Enum.max()
      assert ImageConfig.max_width() == expected_max
    end

    test "no variant has width greater than max_width" do
      max = ImageConfig.max_width()
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, config} ->
        assert config.width <= max,
               "Variant #{name} width #{config.width} should not exceed max #{max}"
      end)
    end
  end

  describe "srcset_variants/0 properties" do
    test "returns list of atoms" do
      srcset = ImageConfig.srcset_variants()
      assert is_list(srcset)

      Enum.each(srcset, fn name ->
        assert is_atom(name)
      end)
    end

    test "all returned variants exist" do
      srcset = ImageConfig.srcset_variants()
      variants = ImageConfig.variants()

      Enum.each(srcset, fn name ->
        assert Map.has_key?(variants, name),
               "Srcset variant #{name} should exist in variants"
      end)
    end

    test "variants are ordered by width ascending" do
      srcset = ImageConfig.srcset_variants()
      widths = Enum.map(srcset, &ImageConfig.variant_width/1)

      sorted_widths = Enum.sort(widths)
      assert widths == sorted_widths, "Srcset variants should be ordered by width ascending"
    end

    test "contains all variants" do
      srcset = ImageConfig.srcset_variants()
      variants = ImageConfig.variants()

      assert length(srcset) == map_size(variants)
    end
  end

  describe "default_variant/0 properties" do
    test "returns an atom" do
      default = ImageConfig.default_variant()
      assert is_atom(default)
    end

    test "default variant exists in variants" do
      default = ImageConfig.default_variant()
      variants = ImageConfig.variants()
      assert Map.has_key?(variants, default)
    end
  end

  describe "consistency properties" do
    test "all accessor functions are consistent with variants/0" do
      variants = ImageConfig.variants()

      Enum.each(variants, fn {name, config} ->
        # variant/1 consistency
        assert ImageConfig.variant(name) == config

        # variant_width/1 consistency
        assert ImageConfig.variant_width(name) == config.width

        # variant_quality/1 consistency
        assert ImageConfig.variant_quality(name) == config.quality

        # variant_widths/0 consistency
        assert ImageConfig.variant_widths()[Atom.to_string(name)] == config.width
      end)
    end

    test "repeated calls return same results (deterministic)" do
      # Call multiple times and verify consistency
      for _ <- 1..5 do
        v1 = ImageConfig.variants()
        v2 = ImageConfig.variants()
        assert v1 == v2

        w1 = ImageConfig.variant_widths()
        w2 = ImageConfig.variant_widths()
        assert w1 == w2

        m1 = ImageConfig.max_width()
        m2 = ImageConfig.max_width()
        assert m1 == m2

        s1 = ImageConfig.srcset_variants()
        s2 = ImageConfig.srcset_variants()
        assert s1 == s2
      end
    end
  end
end
