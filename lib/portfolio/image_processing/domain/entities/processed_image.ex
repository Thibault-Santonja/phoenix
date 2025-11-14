defmodule Portfolio.ImageProcessing.Domain.Entities.ProcessedImage do
  @moduledoc """
  Entité représentant une image et ses variants générés.

  Cette entité encapsule le cycle de vie du traitement d'une image :
  - Chargement de l'image source
  - Génération des variants selon les spécifications
  - Suivi de l'état de traitement
  """

  alias Portfolio.ImageProcessing.Domain.ValueObjects.{ImageDimensions, VariantSpecification}

  @enforce_keys [:id, :source_path, :output_base_path]
  defstruct [
    :id,
    :source_path,
    :output_base_path,
    :original_dimensions,
    :variants,
    :processing_status,
    :error
  ]

  @type processing_status :: :pending | :processing | :completed | :failed
  @type variant_result :: %{atom() => String.t()}

  @type t :: %__MODULE__{
          id: String.t(),
          source_path: String.t(),
          output_base_path: String.t(),
          original_dimensions: ImageDimensions.t() | nil,
          variants: variant_result() | nil,
          processing_status: processing_status(),
          error: term() | nil
        }

  @doc """
  Crée une nouvelle image à traiter.

  ## Exemples

      iex> ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      %ProcessedImage{id: "abc123", source_path: "/tmp/photo.jpg", processing_status: :pending}
  """
  @spec new(String.t(), String.t(), String.t()) :: t()
  def new(id, source_path, output_base_path) do
    %__MODULE__{
      id: id,
      source_path: source_path,
      output_base_path: output_base_path,
      original_dimensions: nil,
      variants: nil,
      processing_status: :pending,
      error: nil
    }
  end

  @doc """
  Marque l'image comme en cours de traitement.

  ## Exemples

      iex> image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      iex> ProcessedImage.start_processing(image, %ImageDimensions{width: 4000, height: 3000})
      %ProcessedImage{processing_status: :processing, original_dimensions: %ImageDimensions{...}}
  """
  @spec start_processing(t(), ImageDimensions.t()) :: t()
  def start_processing(%__MODULE__{} = image, dimensions) do
    %{image | processing_status: :processing, original_dimensions: dimensions}
  end

  @doc """
  Marque l'image comme traitée avec succès.

  ## Exemples

      iex> image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      iex> variants = %{thumbnail: "/uploads/abc123/thumbnail.webp"}
      iex> ProcessedImage.mark_completed(image, variants)
      %ProcessedImage{processing_status: :completed, variants: %{thumbnail: "..."}}
  """
  @spec mark_completed(t(), variant_result()) :: t()
  def mark_completed(%__MODULE__{} = image, variants) do
    %{image | processing_status: :completed, variants: variants, error: nil}
  end

  @doc """
  Marque l'image comme échouée.

  ## Exemples

      iex> image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      iex> ProcessedImage.mark_failed(image, :file_not_found)
      %ProcessedImage{processing_status: :failed, error: :file_not_found}
  """
  @spec mark_failed(t(), term()) :: t()
  def mark_failed(%__MODULE__{} = image, reason) do
    %{image | processing_status: :failed, error: reason, variants: nil}
  end

  @doc """
  Vérifie si l'image a été traitée avec succès.

  ## Exemples

      iex> image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      iex> image = ProcessedImage.mark_completed(image, %{})
      iex> ProcessedImage.completed?(image)
      true
  """
  @spec completed?(t()) :: boolean()
  def completed?(%__MODULE__{processing_status: :completed}), do: true
  def completed?(_), do: false

  @doc """
  Vérifie si l'image a échoué.

  ## Exemples

      iex> image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      iex> image = ProcessedImage.mark_failed(image, :file_not_found)
      iex> ProcessedImage.failed?(image)
      true
  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{processing_status: :failed}), do: true
  def failed?(_), do: false

  @doc """
  Vérifie si l'image est en cours de traitement.

  ## Exemples

      iex> image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      iex> dims = ImageDimensions.new!(1920, 1080)
      iex> image = ProcessedImage.start_processing(image, dims)
      iex> ProcessedImage.processing?(image)
      true
  """
  @spec processing?(t()) :: boolean()
  def processing?(%__MODULE__{processing_status: :processing}), do: true
  def processing?(_), do: false

  @doc """
  Retourne le chemin d'un variant spécifique.

  ## Exemples

      iex> image = ProcessedImage.mark_completed(image, %{thumbnail: "/path/thumb.webp"})
      iex> ProcessedImage.variant_path(image, :thumbnail)
      {:ok, "/path/thumb.webp"}

      iex> ProcessedImage.variant_path(image, :nonexistent)
      {:error, :variant_not_found}
  """
  @spec variant_path(t(), atom()) ::
          {:ok, String.t()} | {:error, :variant_not_found | :not_processed}
  def variant_path(%__MODULE__{variants: nil}, _variant_name), do: {:error, :not_processed}

  def variant_path(%__MODULE__{variants: variants}, variant_name) do
    case Map.get(variants, variant_name) do
      nil -> {:error, :variant_not_found}
      path -> {:ok, path}
    end
  end

  @doc """
  Retourne tous les variants générés.

  ## Exemples

      iex> image = ProcessedImage.mark_completed(image, %{thumbnail: "/path/thumb.webp"})
      iex> ProcessedImage.variants(image)
      {:ok, %{thumbnail: "/path/thumb.webp"}}

      iex> image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      iex> ProcessedImage.variants(image)
      {:error, :not_processed}
  """
  @spec variants(t()) :: {:ok, variant_result()} | {:error, :not_processed}
  def variants(%__MODULE__{variants: nil}), do: {:error, :not_processed}
  def variants(%__MODULE__{variants: variants}), do: {:ok, variants}

  @doc """
  Calcule le chemin de sortie pour un variant donné.

  ## Exemples

      iex> image = ProcessedImage.new("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      iex> spec = VariantSpecification.new!(:thumbnail, 400, 75, :webp, 4)
      iex> ProcessedImage.output_path_for_variant(image, spec)
      "/uploads/abc123/thumbnail.webp"
  """
  @spec output_path_for_variant(t(), VariantSpecification.t()) :: String.t()
  def output_path_for_variant(%__MODULE__{output_base_path: base_path}, spec) do
    Path.join(base_path, VariantSpecification.filename(spec))
  end
end
