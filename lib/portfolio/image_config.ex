defmodule Portfolio.ImageConfig do
  @moduledoc """
  Centralized configuration for image variants.

  This module provides a single source of truth for all image processing
  configuration, avoiding duplication across ImageProcessor and ImageHelpers.

  ## Configuration

  Reads from Application config `:portfolio, :image_variants`:

      config :portfolio, :image_variants,
        thumbnail: [width: 320, quality: 75],
        small: [width: 640, quality: 80],
        medium: [width: 1024, quality: 85],
        large: [width: 1920, quality: 85]

  ## Usage

      # Get all variants
      ImageConfig.variants()
      #=> %{thumbnail: %{width: 320, quality: 75}, ...}

      # Get specific variant
      ImageConfig.variant(:thumbnail)
      #=> %{width: 320, quality: 75}

      # Get variant width
      ImageConfig.variant_width(:medium)
      #=> 1024

      # Get widths for srcset (string keys)
      ImageConfig.variant_widths()
      #=> %{"thumbnail" => 320, "medium" => 1024, ...}
  """

  @type variant_name :: atom()
  @type image_format :: :webp | :avif | :jpeg
  @type variant_config :: %{
          width: pos_integer(),
          quality: pos_integer(),
          format: image_format(),
          effort: pos_integer()
        }
  @type variants_map :: %{variant_name() => variant_config()}

  @doc """
  Returns all configured image variants.

  ## Examples

      iex> variants = Portfolio.ImageConfig.variants()
      iex> Map.has_key?(variants, :thumbnail)
      true
      iex> variants[:thumbnail].width
      320
  """
  @spec variants() :: variants_map()
  def variants do
    Application.get_env(:portfolio, :image_variants, %{})
    |> Enum.map(fn {name, config} ->
      {name, normalize_variant_config(config)}
    end)
    |> Map.new()
  end

  @doc """
  Returns configuration for a specific variant.

  Accepts both atom and string variant names.

  ## Examples

      iex> Portfolio.ImageConfig.variant(:thumbnail)
      %{width: 320, quality: 75}

      iex> Portfolio.ImageConfig.variant("medium")
      %{width: 1024, quality: 85}

      iex> Portfolio.ImageConfig.variant(:nonexistent)
      nil
  """
  @spec variant(variant_name() | String.t()) :: variant_config() | nil
  def variant(name) when is_atom(name) do
    Map.get(variants(), name)
  end

  def variant(name) when is_binary(name) do
    variant(String.to_existing_atom(name))
  rescue
    ArgumentError -> nil
  end

  @doc """
  Returns the width for a specific variant.

  ## Examples

      iex> Portfolio.ImageConfig.variant_width(:thumbnail)
      320

      iex> Portfolio.ImageConfig.variant_width(:nonexistent)
      nil
  """
  @spec variant_width(variant_name()) :: pos_integer() | nil
  def variant_width(name) do
    case variant(name) do
      nil -> nil
      config -> config.width
    end
  end

  @doc """
  Returns the quality setting for a specific variant.

  ## Examples

      iex> Portfolio.ImageConfig.variant_quality(:thumbnail)
      75

      iex> Portfolio.ImageConfig.variant_quality(:large)
      85
  """
  @spec variant_quality(variant_name()) :: pos_integer() | nil
  def variant_quality(name) do
    case variant(name) do
      nil -> nil
      config -> config.quality
    end
  end

  @doc """
  Returns a map of variant names (as strings) to their widths.

  This format is useful for srcset attributes and JSON serialization.

  ## Examples

      iex> widths = Portfolio.ImageConfig.variant_widths()
      iex> widths["thumbnail"]
      320
      iex> widths["large"]
      1920
  """
  @spec variant_widths() :: %{String.t() => pos_integer()}
  def variant_widths do
    variants()
    |> Enum.map(fn {name, config} ->
      {Atom.to_string(name), config.width}
    end)
    |> Map.new()
  end

  @doc """
  Returns the default variant to use when none is specified.

  Currently returns `:medium` as a balanced default.

  ## Examples

      iex> Portfolio.ImageConfig.default_variant()
      :medium
  """
  @spec default_variant() :: :medium
  def default_variant do
    :medium
  end

  @doc """
  Returns the maximum width across all variants.

  Useful for determining image upload size limits.

  ## Examples

      iex> Portfolio.ImageConfig.max_width()
      1920
  """
  @spec max_width() :: pos_integer()
  def max_width do
    variants()
    |> Map.values()
    |> Enum.map(& &1.width)
    |> Enum.max()
  end

  @doc """
  Returns list of variant names suitable for srcset, ordered by width ascending.

  These variants are appropriate for responsive images using the srcset attribute.

  ## Examples

      iex> Portfolio.ImageConfig.srcset_variants()
      [:thumbnail, :small, :medium, :large]
  """
  @spec srcset_variants() :: [variant_name()]
  def srcset_variants do
    variants()
    |> Enum.sort_by(fn {_name, config} -> config.width end)
    |> Enum.map(fn {name, _config} -> name end)
  end

  # Private Functions

  # Normalizes variant configuration from keyword list to map with atom keys
  defp normalize_variant_config(config) when is_list(config) do
    %{
      width: Keyword.fetch!(config, :width),
      quality: Keyword.fetch!(config, :quality),
      format: Keyword.get(config, :format, :webp),
      effort: Keyword.get(config, :effort, 4)
    }
  end

  defp normalize_variant_config(config) when is_map(config) do
    # Already normalized, ensure defaults
    config
    |> Map.put_new(:format, :webp)
    |> Map.put_new(:effort, 4)
  end
end
