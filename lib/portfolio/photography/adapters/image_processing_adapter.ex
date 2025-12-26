defmodule Portfolio.Photography.Adapters.ImageProcessingAdapter do
  @moduledoc """
  Anti-Corruption Layer between Photography and ImageProcessing bounded contexts.

  This adapter translates between Photography domain concepts and ImageProcessing
  domain concepts, preventing tight coupling between contexts while allowing
  them to communicate.

  ## Architecture (DDD Anti-Corruption Layer)

  The Photography context should not directly depend on ImageProcessing internals.
  This adapter:

  1. Translates Photography entities (Photo) to ImageProcessing inputs
  2. Translates ImageProcessing outputs back to Photography domain
  3. Handles errors in Photography-specific terms
  4. Isolates ImageProcessing implementation details

  ## Usage

      # Instead of calling ImageProcessing directly:
      ImageProcessingAdapter.generate_variants(photo)

      # Or for async processing:
      ImageProcessingAdapter.enqueue_variant_generation(photo)

  ## Benefits

  - Photography context can evolve independently of ImageProcessing
  - Easier testing (mock adapter per context)
  - Clear translation between domain languages
  - ImageProcessing domain model doesn't leak into Photography
  """

  require Logger

  alias Portfolio.ImageProcessing
  alias Portfolio.ImageProcessing.CircuitBreaker
  alias Portfolio.Photography.Photo
  alias Portfolio.Workers.ImageVariantWorker

  @type variant_result :: %{
          thumbnail: String.t(),
          small: String.t(),
          medium: String.t(),
          large: String.t()
        }

  @type processing_error ::
          :file_not_found
          | :corrupted_file
          | :processing_failed
          | :service_unavailable
          | :timeout

  @doc """
  Generates image variants for a photo synchronously.

  Translates the Photo entity to ImageProcessing inputs and handles
  the response in Photography domain terms.

  ## Parameters

  - `photo` - The Photo entity to process

  ## Returns

  - `{:ok, variants}` - Map of variant URLs keyed by size
  - `{:error, reason}` - Processing error in Photography domain terms

  ## Examples

      iex> {:ok, variants} = ImageProcessingAdapter.generate_variants(photo)
      iex> Map.keys(variants)
      [:thumbnail, :small, :medium, :large]
  """
  @spec generate_variants(Photo.t()) :: {:ok, variant_result()} | {:error, processing_error()}
  def generate_variants(%Photo{id: photo_id, file_path: file_path} = photo) do
    output_path = build_output_path(photo)

    Logger.debug("ACL: Translating Photo to ImageProcessing request",
      photo_id: photo_id,
      source: file_path,
      output: output_path
    )

    # Delegate to ImageProcessing context
    case ImageProcessing.generate_variants(photo_id, file_path, output_path) do
      {:ok, variants} ->
        # Translate ImageProcessing response to Photography domain
        translated = translate_variants(variants)
        {:ok, translated}

      {:error, :file_not_found} = error ->
        Logger.warning("ACL: Source file not found", photo_id: photo_id)
        error

      {:error, :corrupted_file} = error ->
        Logger.warning("ACL: Corrupted file detected", photo_id: photo_id)
        error

      {:error, :service_unavailable} = error ->
        Logger.warning("ACL: ImageProcessing service unavailable (circuit breaker open)",
          photo_id: photo_id
        )

        error

      {:error, reason} ->
        Logger.error("ACL: ImageProcessing failed",
          photo_id: photo_id,
          reason: inspect(reason)
        )

        {:error, :processing_failed}
    end
  end

  @doc """
  Enqueues asynchronous variant generation for a photo.

  This is the preferred method for photo uploads to avoid blocking
  the request while processing images.

  ## Parameters

  - `photo` - The Photo entity to process

  ## Returns

  - `{:ok, job}` - The enqueued Oban job
  - `{:error, reason}` - Enqueueing failed
  """
  @spec enqueue_variant_generation(Photo.t()) ::
          {:ok, Oban.Job.t()} | {:error, Oban.Job.changeset()}
  def enqueue_variant_generation(%Photo{id: photo_id}) do
    ImageVariantWorker.enqueue(photo_id)
  end

  @doc """
  Checks if image processing service is available.

  Useful for health checks and graceful degradation.

  ## Returns

  - `true` if the circuit breaker is closed (service available)
  - `false` if the circuit breaker is open (service unavailable)
  """
  @spec service_available?() :: boolean()
  def service_available? do
    not CircuitBreaker.blown?()
  end

  # Private functions

  # Builds the output path for variants based on Photo entity
  @spec build_output_path(Photo.t()) :: String.t()
  defp build_output_path(%Photo{id: photo_id, album_id: album_id}) do
    upload_dir = Application.get_env(:portfolio, :upload_dir, "priv/static/uploads")
    Path.join([upload_dir, "albums", album_id, "photos", photo_id])
  end

  # Translates ImageProcessing variant format to Photography domain format
  @spec translate_variants(map()) :: variant_result()
  defp translate_variants(variants) when is_map(variants) do
    # ImageProcessing might use different keys or structures
    # This translation ensures Photography context gets consistent format
    %{
      thumbnail: Map.get(variants, :thumbnail, Map.get(variants, "thumbnail")),
      small: Map.get(variants, :small, Map.get(variants, "small")),
      medium: Map.get(variants, :medium, Map.get(variants, "medium")),
      large: Map.get(variants, :large, Map.get(variants, "large"))
    }
  end
end
