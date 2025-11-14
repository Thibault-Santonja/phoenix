defmodule Portfolio.ImageProcessing.Infrastructure.VipsAdapter do
  @moduledoc """
  Adaptateur pour la bibliothèque libvips via Vix.

  Isole le domaine de l'implémentation technique du traitement d'images.
  Permet de changer de bibliothèque de traitement d'images sans impacter le domaine.
  """

  require Logger

  alias Portfolio.ImageProcessing.Domain.ValueObjects.{ImageDimensions, VariantSpecification}
  alias Vix.Vips.Image
  alias Vix.Vips.Operation

  @type load_result ::
          {:ok, Image.t(), ImageDimensions.t()} | {:error, :file_not_found | :corrupted_file}
  @type resize_result :: {:ok, Image.t()} | {:error, term()}
  @type save_result :: :ok | {:error, term()}

  @doc """
  Charge une image depuis un fichier.

  Retourne l'image Vix et ses dimensions originales.

  ## Exemples

      iex> VipsAdapter.load_image("/path/to/photo.jpg")
      {:ok, %Vix.Vips.Image{}, %ImageDimensions{width: 4000, height: 3000}}

      iex> VipsAdapter.load_image("/invalid/path.jpg")
      {:error, :file_not_found}
  """
  @spec load_image(String.t()) :: load_result()
  def load_image(path) do
    if File.exists?(path) do
      do_load_image(path)
    else
      Logger.error("Source file not found", path: path)
      {:error, :file_not_found}
    end
  end

  defp do_load_image(path) do
    case Image.new_from_file(path) do
      {:ok, image} ->
        width = Image.width(image)
        height = Image.height(image)

        case ImageDimensions.new(width, height) do
          {:ok, dimensions} ->
            {:ok, image, dimensions}

          {:error, :invalid_dimensions} ->
            Logger.error("Invalid image dimensions", path: path, width: width, height: height)
            {:error, :corrupted_file}
        end

      {:error, reason} ->
        Logger.error("Failed to load image", path: path, reason: inspect(reason))
        {:error, :corrupted_file}
    end
  end

  @doc """
  Redimensionne une image selon une spécification.

  Préserve l'aspect ratio et ne fait pas d'upscaling.

  ## Exemples

      iex> VipsAdapter.resize_image(image, spec)
      {:ok, resized_image}
  """
  @spec resize_image(Image.t(), VariantSpecification.t(), ImageDimensions.t()) :: resize_result()
  def resize_image(image, %VariantSpecification{width: target_width}, original_dims) do
    case ImageDimensions.resize_to_width(original_dims, target_width) do
      {:no_upscale, _dims} ->
        # Image déjà plus petite que la cible, on la garde telle quelle
        {:ok, image}

      {:ok, _new_dims} ->
        # Calculer le scale factor
        scale = target_width / original_dims.width

        case Operation.resize(image, scale, kernel: :VIPS_KERNEL_LANCZOS3) do
          {:ok, resized} ->
            {:ok, resized}

          {:error, reason} ->
            Logger.error("Failed to resize image", reason: inspect(reason))
            {:error, {:resize_failed, reason}}
        end
    end
  end

  @doc """
  Sauvegarde une image dans un fichier avec le format et la qualité spécifiés.

  ## Exemples

      iex> spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      iex> VipsAdapter.save_image(image, "/path/output.webp", spec)
      :ok
  """
  @spec save_image(Image.t(), String.t(), VariantSpecification.t()) :: save_result()
  def save_image(image, output_path, %VariantSpecification{
        format: format,
        quality: quality,
        effort: effort
      }) do
    # Construire les options de format pour Vix
    suffix = build_format_suffix(format, quality, effort)

    case Image.write_to_file(image, output_path <> suffix) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.error("Failed to save image",
          output_path: output_path,
          format: format,
          reason: inspect(reason)
        )

        {:error, {:image_save_failed, format, reason}}
    end
  end

  @doc """
  Crée le répertoire de sortie s'il n'existe pas.

  ## Exemples

      iex> VipsAdapter.ensure_output_directory("/path/to/output")
      :ok

      iex> VipsAdapter.ensure_output_directory("/invalid/path")
      {:error, :directory_creation_failed}
  """
  @spec ensure_output_directory(String.t()) ::
          :ok | {:error, :disk_full | {:directory_creation_failed, term()}}
  def ensure_output_directory(path) do
    case File.mkdir_p(path) do
      :ok ->
        :ok

      {:error, :enospc} ->
        Logger.error("Disk full", path: path)
        {:error, :disk_full}

      {:error, reason} ->
        Logger.error("Failed to create directory", path: path, reason: reason)
        {:error, {:directory_creation_failed, reason}}
    end
  end

  # Private functions

  defp build_format_suffix(:webp, quality, effort) do
    # WebP options: Q for quality, effort for compression level (0-6)
    "[Q=#{quality},effort=#{effort}]"
  end

  defp build_format_suffix(:avif, quality, effort) do
    # AVIF options: Q for quality, effort for compression level (0-9)
    "[Q=#{quality},effort=#{effort}]"
  end

  defp build_format_suffix(:jpeg, quality, _effort) do
    # JPEG options: Q for quality
    "[Q=#{quality}]"
  end
end
