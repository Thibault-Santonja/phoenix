defmodule Portfolio.ImageProcessing.Domain.ValueObjects.ImageDimensions do
  @moduledoc """
  Value Object représentant les dimensions d'une image.

  Garantit que les dimensions sont toujours valides (positives).
  """

  @enforce_keys [:width, :height]
  defstruct [:width, :height]

  @type t :: %__MODULE__{
          width: pos_integer(),
          height: pos_integer()
        }

  @doc """
  Crée de nouvelles dimensions.

  ## Exemples

      iex> ImageDimensions.new(1920, 1080)
      {:ok, %ImageDimensions{width: 1920, height: 1080}}

      iex> ImageDimensions.new(0, 100)
      {:error, :invalid_dimensions}

      iex> ImageDimensions.new(-100, 100)
      {:error, :invalid_dimensions}
  """
  @spec new(integer(), integer()) :: {:ok, t()} | {:error, :invalid_dimensions}
  def new(width, height) when is_integer(width) and is_integer(height) do
    if width > 0 and height > 0 do
      {:ok, %__MODULE__{width: width, height: height}}
    else
      {:error, :invalid_dimensions}
    end
  end

  def new(_, _), do: {:error, :invalid_dimensions}

  @doc """
  Calcule l'aspect ratio.

  ## Exemples

      iex> dims = ImageDimensions.new!(1920, 1080)
      iex> ImageDimensions.aspect_ratio(dims)
      1.7777777777777777
  """
  @spec aspect_ratio(t()) :: float()
  def aspect_ratio(%__MODULE__{width: width, height: height}) do
    width / height
  end

  @doc """
  Calcule les nouvelles dimensions pour une largeur cible en préservant l'aspect ratio.

  Ne fait pas d'upscaling si la largeur cible est plus grande que l'originale.

  ## Exemples

      iex> dims = ImageDimensions.new!(1920, 1080)
      iex> ImageDimensions.resize_to_width(dims, 960)
      {:ok, %ImageDimensions{width: 960, height: 540}}

      iex> dims = ImageDimensions.new!(800, 600)
      iex> ImageDimensions.resize_to_width(dims, 1920)
      {:no_upscale, dims}
  """
  @spec resize_to_width(t(), pos_integer()) :: {:ok, t()} | {:no_upscale, t()}
  def resize_to_width(%__MODULE__{width: current_width} = dims, target_width)
      when target_width >= current_width do
    {:no_upscale, dims}
  end

  def resize_to_width(%__MODULE__{width: width, height: height}, target_width) do
    scale = target_width / width
    new_height = round(height * scale)
    {:ok, %__MODULE__{width: target_width, height: new_height}}
  end

  @doc """
  Version ! qui lève une exception en cas d'erreur.

  ## Exemples

      iex> ImageDimensions.new!(1920, 1080)
      %ImageDimensions{width: 1920, height: 1080}

      iex> ImageDimensions.new!(0, 100)
      ** (ArgumentError) Invalid dimensions: width and height must be positive
  """
  @spec new!(integer(), integer()) :: t()
  def new!(width, height) do
    case new(width, height) do
      {:ok, dims} ->
        dims

      {:error, :invalid_dimensions} ->
        raise ArgumentError, "Invalid dimensions: width and height must be positive"
    end
  end

  @doc """
  Vérifie si les dimensions sont en mode portrait.

  ## Exemples

      iex> dims = ImageDimensions.new!(1080, 1920)
      iex> ImageDimensions.portrait?(dims)
      true
  """
  @spec portrait?(t()) :: boolean()
  def portrait?(%__MODULE__{width: width, height: height}), do: height > width

  @doc """
  Vérifie si les dimensions sont en mode paysage.

  ## Exemples

      iex> dims = ImageDimensions.new!(1920, 1080)
      iex> ImageDimensions.landscape?(dims)
      true
  """
  @spec landscape?(t()) :: boolean()
  def landscape?(%__MODULE__{width: width, height: height}), do: width > height

  @doc """
  Vérifie si les dimensions sont carrées.

  ## Exemples

      iex> dims = ImageDimensions.new!(1080, 1080)
      iex> ImageDimensions.square?(dims)
      true
  """
  @spec square?(t()) :: boolean()
  def square?(%__MODULE__{width: width, height: height}), do: width == height
end
