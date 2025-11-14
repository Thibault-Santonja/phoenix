defmodule Portfolio.ImageProcessing.Domain.ValueObjects.ImageQuality do
  @moduledoc """
  Value Object représentant la qualité de compression d'une image.

  La qualité est exprimée sur une échelle de 1 à 100, où:
  - 1-50: Basse qualité (très compressé)
  - 51-75: Qualité moyenne
  - 76-90: Haute qualité
  - 91-100: Très haute qualité (peu de compression)
  """

  @type t :: pos_integer()

  @min_quality 1
  @max_quality 100

  @doc """
  Crée une valeur de qualité.

  ## Exemples

      iex> ImageQuality.new(85)
      {:ok, 85}

      iex> ImageQuality.new(0)
      {:error, :invalid_quality}

      iex> ImageQuality.new(101)
      {:error, :invalid_quality}
  """
  @spec new(integer()) :: {:ok, t()} | {:error, :invalid_quality}
  def new(quality)
      when is_integer(quality) and quality >= @min_quality and quality <= @max_quality do
    {:ok, quality}
  end

  def new(_), do: {:error, :invalid_quality}

  @doc """
  Version ! qui lève une exception en cas d'erreur.

  ## Exemples

      iex> ImageQuality.new!(85)
      85

      iex> ImageQuality.new!(0)
      ** (ArgumentError) Invalid quality: must be between 1 and 100
  """
  @spec new!(integer()) :: t()
  def new!(quality) do
    case new(quality) do
      {:ok, q} ->
        q

      {:error, :invalid_quality} ->
        raise ArgumentError, "Invalid quality: must be between 1 and 100"
    end
  end

  @doc """
  Valide qu'une qualité est dans la plage acceptable.

  ## Exemples

      iex> ImageQuality.valid?(85)
      true

      iex> ImageQuality.valid?(0)
      false
  """
  @spec valid?(integer()) :: boolean()
  def valid?(quality)
      when is_integer(quality) and quality >= @min_quality and quality <= @max_quality,
      do: true

  def valid?(_), do: false

  @doc """
  Retourne la qualité minimale acceptable.

  ## Exemples

      iex> ImageQuality.min()
      1
  """
  @spec min() :: pos_integer()
  def min, do: @min_quality

  @doc """
  Retourne la qualité maximale.

  ## Exemples

      iex> ImageQuality.max()
      100
  """
  @spec max() :: pos_integer()
  def max, do: @max_quality

  @doc """
  Catégorise une qualité.

  ## Exemples

      iex> ImageQuality.category(85)
      :high

      iex> ImageQuality.category(40)
      :low
  """
  @spec category(t()) :: :low | :medium | :high | :very_high
  def category(quality) when quality <= 50, do: :low
  def category(quality) when quality <= 75, do: :medium
  def category(quality) when quality <= 90, do: :high
  def category(_quality), do: :very_high
end
