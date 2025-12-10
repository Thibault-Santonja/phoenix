defmodule Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat do
  @moduledoc """
  Value Object représentant un format d'image.

  Formats supportés: WebP, AVIF, JPEG
  Chaque format a ses propres caractéristiques et extensions.
  """

  @type t :: :webp | :avif | :jpeg

  @valid_formats [:webp, :avif, :jpeg]

  @doc """
  Valide qu'un format est supporté.

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat
      iex> ImageFormat.valid?(:webp)
      true

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat
      iex> ImageFormat.valid?(:png)
      false
  """
  @spec valid?(atom()) :: boolean()
  def valid?(format) when format in @valid_formats, do: true
  def valid?(_), do: false

  @doc """
  Retourne l'extension de fichier pour un format.

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat
      iex> ImageFormat.extension(:webp)
      "webp"

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat
      iex> ImageFormat.extension(:jpeg)
      "jpg"
  """
  @spec extension(t()) :: String.t()
  def extension(:webp), do: "webp"
  def extension(:avif), do: "avif"
  def extension(:jpeg), do: "jpg"

  @doc """
  Retourne tous les formats valides.

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat
      iex> ImageFormat.all()
      [:webp, :avif, :jpeg]
  """
  @spec all() :: [:webp | :avif | :jpeg, ...]
  def all, do: @valid_formats

  # String representations of valid formats for pre-validation
  @valid_format_strings Enum.map(@valid_formats, &Atom.to_string/1)

  @doc """
  Parse un format depuis une chaîne.

  Validates the string against known formats BEFORE converting to atom,
  avoiding potential atom table exhaustion from arbitrary user input.

  ## Exemples

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat
      iex> ImageFormat.from_string("webp")
      {:ok, :webp}

      iex> alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat
      iex> ImageFormat.from_string("invalid")
      {:error, :invalid_format}
  """
  @spec from_string(String.t()) :: {:ok, t()} | {:error, :invalid_format}
  def from_string(str) when is_binary(str) do
    # Validate string is a known format BEFORE converting to atom
    # This prevents atom table exhaustion from arbitrary user input
    if str in @valid_format_strings do
      {:ok, String.to_existing_atom(str)}
    else
      {:error, :invalid_format}
    end
  end
end
