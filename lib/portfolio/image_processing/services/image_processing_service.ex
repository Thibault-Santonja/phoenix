defmodule Portfolio.ImageProcessing.Services.ImageProcessingService do
  @moduledoc """
  Service applicatif orchestrant le traitement d'images.

  Responsabilités:
  - Charger l'image source
  - Générer tous les variants configurés
  - Émettre les événements domaine
  - Gérer les erreurs de traitement
  """

  require Logger

  alias Portfolio.DomainEvents
  alias Portfolio.ImageConfig
  alias Portfolio.ImageProcessing.Domain.Entities.ProcessedImage

  alias Portfolio.ImageProcessing.Domain.Events.{
    ImageProcessingCompleted,
    ImageProcessingFailed,
    ImageProcessingStarted
  }

  alias Portfolio.ImageProcessing.CircuitBreaker
  alias Portfolio.ImageProcessing.Domain.ValueObjects.VariantSpecification
  alias Portfolio.ImageProcessing.Infrastructure.VipsAdapter

  @type variant_result :: %{atom() => String.t()}
  @type processing_result :: {:ok, variant_result()} | {:error, term()}

  @doc """
  Génère tous les variants d'une image.

  ## Paramètres

    * `image_id` - Identifiant unique de l'image
    * `source_path` - Chemin vers l'image source
    * `output_base_path` - Répertoire de sortie pour les variants

  ## Retour

    * `{:ok, variants_map}` - Map des variants générés (nom => chemin)
    * `{:error, reason}` - Erreur de traitement

  ## Exemples

      iex> ImageProcessingService.generate_variants("abc123", "/tmp/photo.jpg", "/uploads/abc123")
      {:ok, %{thumbnail: "/uploads/abc123/thumbnail.webp", ...}}
  """
  @spec generate_variants(String.t(), String.t(), String.t()) :: processing_result()
  def generate_variants(image_id, source_path, output_base_path) do
    Logger.metadata(image_id: image_id)

    image = ProcessedImage.new(image_id, source_path, output_base_path)
    start_time = System.monotonic_time(:millisecond)

    # Récupérer les spécifications de variants depuis la configuration
    variant_specs = load_variant_specifications()

    # Émettre événement de début
    emit_processing_started(image, variant_specs)

    # Pipeline de traitement with circuit breaker protection
    with :ok <- VipsAdapter.ensure_output_directory(output_base_path),
         {:ok, vix_image, dimensions} <- load_image_with_circuit_breaker(source_path) do
      image = ProcessedImage.start_processing(image, dimensions)

      case process_all_variants(vix_image, variant_specs, image, dimensions) do
        {:ok, variants} ->
          duration_ms = System.monotonic_time(:millisecond) - start_time
          image = ProcessedImage.mark_completed(image, variants)

          emit_processing_completed(image, duration_ms)

          {:ok, variants}

        {:error, reason} = error ->
          image = ProcessedImage.mark_failed(image, reason)
          emit_processing_failed(image)

          error
      end
    else
      {:error, reason} = error ->
        image = ProcessedImage.mark_failed(image, reason)
        emit_processing_failed(image)

        error
    end
  end

  # Private functions

  # Wraps VipsAdapter.load_image with circuit breaker protection
  @spec load_image_with_circuit_breaker(String.t()) ::
          {:ok, Vix.Vips.Image.t(),
           Portfolio.ImageProcessing.Domain.ValueObjects.ImageDimensions.t()}
          | {:error, term()}
  defp load_image_with_circuit_breaker(source_path) do
    case CircuitBreaker.call(fn -> VipsAdapter.load_image(source_path) end) do
      # CircuitBreaker wraps {:ok, image, dims} as {:ok, {:ok, image, dims}}
      {:ok, {:ok, vix_image, dimensions}} ->
        {:ok, vix_image, dimensions}

      {:error, :circuit_blown} ->
        Logger.error("Image processing circuit breaker open - service unavailable",
          source_path: source_path
        )

        {:error, :service_unavailable}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Charge les spécifications de variants depuis la configuration
  @spec load_variant_specifications() :: [VariantSpecification.t()]
  defp load_variant_specifications do
    ImageConfig.variants()
    |> Enum.map(fn {name, config} ->
      VariantSpecification.new!(
        name,
        config.width,
        config.quality,
        config.format,
        config.effort
      )
    end)
  end

  # Traite tous les variants
  @spec process_all_variants(
          Vix.Vips.Image.t(),
          [VariantSpecification.t()],
          ProcessedImage.t(),
          Portfolio.ImageProcessing.Domain.ValueObjects.ImageDimensions.t()
        ) :: {:ok, variant_result()} | {:error, term()}
  defp process_all_variants(vix_image, variant_specs, image, original_dims) do
    variant_specs
    |> Enum.reduce_while({:ok, %{}}, fn spec, {:ok, acc} ->
      case process_single_variant(vix_image, spec, image, original_dims) do
        {:ok, output_path} ->
          variant_name = VariantSpecification.name(spec)
          {:cont, {:ok, Map.put(acc, variant_name, output_path)}}

        {:error, reason} ->
          {:halt, {:error, {:variant_failed, VariantSpecification.name(spec), reason}}}
      end
    end)
  end

  # Traite un seul variant
  @spec process_single_variant(
          Vix.Vips.Image.t(),
          VariantSpecification.t(),
          ProcessedImage.t(),
          Portfolio.ImageProcessing.Domain.ValueObjects.ImageDimensions.t()
        ) :: {:ok, String.t()} | {:error, term()}
  defp process_single_variant(vix_image, spec, image, original_dims) do
    output_path = ProcessedImage.output_path_for_variant(image, spec)
    variant_name = VariantSpecification.name(spec)

    Logger.debug("Processing variant",
      variant: variant_name,
      width: spec.width,
      quality: spec.quality,
      format: spec.format
    )

    with {:ok, resized_image} <- VipsAdapter.resize_image(vix_image, spec, original_dims),
         :ok <- VipsAdapter.save_image(resized_image, output_path, spec) do
      {:ok, output_path}
    else
      {:error, reason} ->
        Logger.error("Failed to process variant",
          variant: variant_name,
          reason: inspect(reason)
        )

        {:error, reason}
    end
  end

  # Émet l'événement de début de traitement
  @spec emit_processing_started(ProcessedImage.t(), [VariantSpecification.t()]) :: :ok
  defp emit_processing_started(image, variant_specs) do
    variant_names = Enum.map(variant_specs, &VariantSpecification.name/1)

    event =
      ImageProcessingStarted.new(
        image.id,
        image.source_path,
        variant_names,
        DateTime.utc_now()
      )

    DomainEvents.publish(:image_processing_started, event)
  end

  # Émet l'événement de traitement réussi
  @spec emit_processing_completed(ProcessedImage.t(), non_neg_integer()) :: :ok
  defp emit_processing_completed(image, duration_ms) do
    {:ok, variants} = ProcessedImage.variants(image)

    event =
      ImageProcessingCompleted.new(
        image.id,
        variants,
        duration_ms,
        DateTime.utc_now()
      )

    DomainEvents.publish(:image_processing_completed, event)
  end

  # Émet l'événement d'échec de traitement
  @spec emit_processing_failed(ProcessedImage.t()) :: :ok
  defp emit_processing_failed(image) do
    event =
      ImageProcessingFailed.new(
        image.id,
        image.error,
        DateTime.utc_now()
      )

    DomainEvents.publish(:image_processing_failed, event)
  end
end
