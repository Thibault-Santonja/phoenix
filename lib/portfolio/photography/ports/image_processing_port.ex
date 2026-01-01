defmodule Portfolio.Photography.Ports.ImageProcessingPort do
  @moduledoc """
  Port (behaviour) defining the contract for image processing operations.

  This port defines the interface that the Photography bounded context
  expects from any image processing implementation. It follows the
  Hexagonal Architecture (Ports & Adapters) pattern.

  ## Architecture

  The Photography context defines this port (what it needs), and the
  ImageProcessing context provides an adapter that implements it.
  This ensures:

  1. Photography doesn't depend on ImageProcessing internals
  2. ImageProcessing can be swapped without changing Photography
  3. Testing is easier (mock implementations)
  4. Clear boundaries between bounded contexts

  ## Usage

  The adapter is configured at runtime:

      config :portfolio, Portfolio.Photography.Ports.ImageProcessingPort,
        adapter: Portfolio.Photography.Adapters.ImageProcessingAdapter

  Or for testing:

      config :portfolio, Portfolio.Photography.Ports.ImageProcessingPort,
        adapter: Portfolio.Photography.Adapters.MockImageProcessingAdapter

  ## Example

      alias Portfolio.Photography.Ports.ImageProcessingPort

      # Generate variants for a photo
      {:ok, variants} = ImageProcessingPort.generate_variants(photo)

      # Check service availability
      if ImageProcessingPort.service_available?() do
        # ...
      end
  """

  alias Portfolio.Photography.Photo

  @type variant_result :: %{
          thumbnail: String.t() | nil,
          small: String.t() | nil,
          medium: String.t() | nil,
          large: String.t() | nil
        }

  @type processing_error ::
          :file_not_found
          | :corrupted_file
          | :processing_failed
          | :service_unavailable
          | :timeout

  @doc """
  Generates image variants for a photo synchronously.

  ## Parameters

  - `photo` - The Photo entity to process

  ## Returns

  - `{:ok, variants}` - Map of variant URLs keyed by size
  - `{:error, reason}` - Processing error
  """
  @callback generate_variants(photo :: Photo.t()) ::
              {:ok, variant_result()} | {:error, processing_error()}

  @doc """
  Enqueues asynchronous variant generation for a photo.

  This is the preferred method for photo uploads to avoid blocking
  the request while processing images.

  ## Parameters

  - `photo` - The Photo entity to process

  ## Returns

  - `{:ok, job}` - The enqueued job
  - `{:error, reason}` - Enqueueing failed
  """
  @callback enqueue_variant_generation(photo :: Photo.t()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Checks if image processing service is available.

  Useful for health checks and graceful degradation.

  ## Returns

  - `true` if the service is available
  - `false` if the service is unavailable
  """
  @callback service_available?() :: boolean()

  # ============================================================================
  # Delegating functions (facade)
  # ============================================================================

  @doc """
  Generates image variants for a photo.

  Delegates to the configured adapter.
  """
  @spec generate_variants(Photo.t()) :: {:ok, variant_result()} | {:error, processing_error()}
  def generate_variants(%Photo{} = photo) do
    adapter().generate_variants(photo)
  end

  @doc """
  Enqueues asynchronous variant generation.

  Delegates to the configured adapter.
  """
  @spec enqueue_variant_generation(Photo.t()) :: {:ok, term()} | {:error, term()}
  def enqueue_variant_generation(%Photo{} = photo) do
    adapter().enqueue_variant_generation(photo)
  end

  @doc """
  Checks if the image processing service is available.

  Delegates to the configured adapter.
  """
  @spec service_available?() :: boolean()
  def service_available? do
    adapter().service_available?()
  end

  # Returns the configured adapter module
  @spec adapter() :: module()
  defp adapter do
    Application.get_env(
      :portfolio,
      __MODULE__,
      []
    )
    |> Keyword.get(:adapter, Portfolio.Photography.Adapters.ImageProcessingAdapter)
  end
end
