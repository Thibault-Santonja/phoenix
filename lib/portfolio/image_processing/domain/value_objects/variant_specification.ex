defmodule Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification do
  @moduledoc """
  Value Object représentant la spécification d'un variant d'image.

  Combine largeur cible, qualité, format et effort de compression.
  """

  alias Portfolio.ImageProcessing.Domain.ValueObjects.{ImageFormat, ImageQuality}

  @enforce_keys [:name, :width, :quality, :format, :effort]
  defstruct [:name, :width, :quality, :format, :effort]

  @type t :: %__MODULE__{
          name: atom(),
          width: pos_integer(),
          quality: ImageQuality.t(),
          format: ImageFormat.t(),
          effort: pos_integer()
        }

  @doc """
  Crée une nouvelle spécification de variant.

  ## Paramètres

    * `name` - Nom du variant (ex: :thumbnail, :large)
    * `width` - Largeur cible en pixels
    * `quality` - Qualité de compression (1-100)
    * `format` - Format d'image (:webp, :avif, :jpeg)
    * `effort` - Effort de compression (0-9 pour AVIF, 0-6 pour WebP)

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification
      iex> VariantSpecification.new(:thumbnail, 400, 75, :webp, 4)
      {:ok, %VariantSpecification{name: :thumbnail, width: 400, quality: 75, format: :webp, effort: 4}}

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification
      iex> VariantSpecification.new(:large, 1920, 150, :webp, 4)
      {:error, :invalid_quality}
  """
  @spec new(atom(), pos_integer(), integer(), ImageFormat.t(), integer()) ::
          {:ok, t()}
          | {:error, :invalid_quality | :invalid_format | :invalid_effort | :invalid_width}
  def new(name, width, quality, format, effort)
      when is_atom(name) and is_integer(width) and width > 0 do
    with {:ok, validated_quality} <- ImageQuality.new(quality),
         :ok <- validate_format(format),
         :ok <- validate_effort(effort, format) do
      {:ok,
       %__MODULE__{
         name: name,
         width: width,
         quality: validated_quality,
         format: format,
         effort: effort
       }}
    end
  end

  def new(_, _, _, _, _), do: {:error, :invalid_width}

  @doc """
  Version ! qui lève une exception en cas d'erreur.

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification
      iex> VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      %VariantSpecification{name: :thumbnail, width: 400, quality: 75, format: :webp, effort: 4}
  """
  @spec new!(atom(), pos_integer(), integer(), ImageFormat.t(), integer()) :: t()
  def new!(name, width, quality, format, effort) do
    case new(name, width, quality, format, effort) do
      {:ok, spec} -> spec
      {:error, reason} -> raise ArgumentError, "Invalid variant specification: #{reason}"
    end
  end

  @doc """
  Crée une spécification depuis une map de configuration.

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification
      iex> config = %{name: :thumbnail, width: 400, quality: 75, format: :webp, effort: 4}
      iex> VariantSpecification.from_config(config)
      {:ok, %VariantSpecification{name: :thumbnail, width: 400, quality: 75, format: :webp, effort: 4}}
  """
  @spec from_config(map()) :: {:ok, t()} | {:error, term()}
  def from_config(%{name: name, width: width, quality: quality, format: format, effort: effort}) do
    new(name, width, quality, format, effort)
  end

  def from_config(_), do: {:error, :missing_required_fields}

  @doc """
  Génère le nom de fichier pour ce variant.

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification
      iex> spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      iex> VariantSpecification.filename(spec)
      "thumbnail.webp"
  """
  @spec filename(t()) :: String.t()
  def filename(%__MODULE__{name: name, format: format}) do
    "#{name}.#{ImageFormat.extension(format)}"
  end

  @doc """
  Retourne le nom du variant.

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification
      iex> spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      iex> VariantSpecification.name(spec)
      :thumbnail
  """
  @spec name(t()) :: atom()
  def name(%__MODULE__{name: name}), do: name

  # Private functions

  defp validate_format(format) do
    if ImageFormat.valid?(format) do
      :ok
    else
      {:error, :invalid_format}
    end
  end

  defp validate_effort(effort, format) when is_integer(effort) do
    max_effort =
      case format do
        :webp -> 6
        :avif -> 9
        :jpeg -> 9
      end

    if effort >= 0 and effort <= max_effort do
      :ok
    else
      {:error, :invalid_effort}
    end
  end

  defp validate_effort(_, _), do: {:error, :invalid_effort}
end
