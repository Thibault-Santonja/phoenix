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

      iex> ImageFormat.valid?(:webp)
      true

      iex> ImageFormat.valid?(:png)
      false
  """
  @spec valid?(atom()) :: boolean()
  def valid?(format) when format in @valid_formats, do: true
  def valid?(_), do: false

  @doc """
  Retourne l'extension de fichier pour un format.

  ## Exemples

      iex> ImageFormat.extension(:webp)
      "webp"

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

      iex> ImageFormat.all()
      [:webp, :avif, :jpeg]
  """
  @spec all() :: [:webp | :avif | :jpeg, ...]
  def all, do: @valid_formats

  @doc """
  Parse un format depuis une chaîne.

  ## Exemples

      iex> ImageFormat.from_string("webp")
      {:ok, :webp}

      iex> ImageFormat.from_string("invalid")
      {:error, :invalid_format}
  """
  @spec from_string(String.t()) :: {:ok, t()} | {:error, :invalid_format}
  def from_string(str) when is_binary(str) do
    format = String.to_existing_atom(str)

    if valid?(format) do
      {:ok, format}
    else
      {:error, :invalid_format}
    end
  rescue
    ArgumentError -> {:error, :invalid_format}
  end
end
