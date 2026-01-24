defmodule Portfolio.ImageProcessing.CircuitBreaker do
  @moduledoc """
  Circuit breaker for image processing operations.

  Protects the application from cascading failures when Vix/libvips encounters
  repeated errors (e.g., memory exhaustion, corrupted images, segfaults).

  ## Configuration

  The circuit breaker uses the following strategy:
  - Opens (trips) after 5 failures within 60 seconds
  - Stays open for 30 seconds before allowing retry attempts
  - Automatically resets after successful operations

  ## Usage

      case CircuitBreaker.call(:image_processing, fn -> VipsAdapter.load_image(path) end) do
        {:ok, result} -> handle_success(result)
        {:error, :circuit_blown} -> handle_service_unavailable()
        {:error, reason} -> handle_error(reason)
      end

  ## Why a Circuit Breaker?

  Vix wraps libvips, a C library. If libvips encounters issues:
  - Memory exhaustion from processing large/many images
  - Corrupted images causing repeated errors
  - Native code crashes that could destabilize the BEAM VM

  The circuit breaker prevents:
  - Cascading failures from overwhelming the system
  - Wasted resources retrying doomed operations
  - Complete system unavailability due to image processing
  """

  require Logger

  @fuse_name :image_processing
  @fuse_options {
    # Standard strategy: fail after N failures in time window
    {:standard, 5, 60_000},
    # Reset after 30 seconds
    {:reset, 30_000}
  }

  @doc """
  Installs the circuit breaker fuse.

  Should be called during application startup.
  """
  @spec install() :: :ok
  def install do
    case :fuse.install(@fuse_name, @fuse_options) do
      :ok ->
        Logger.info("Image processing circuit breaker installed")
        :ok

      {:error, :already_installed} ->
        :ok
    end
  end

  @doc """
  Executes a function with circuit breaker protection.

  Returns:
  - `{:ok, result}` if the function succeeds
  - `{:error, :circuit_blown}` if the circuit is open
  - `{:error, reason}` if the function fails (and records the failure)

  ## Examples

      CircuitBreaker.call(:image_processing, fn ->
        VipsAdapter.load_image(path)
      end)
  """
  @spec call(atom(), (-> result)) :: {:ok, result} | {:error, :circuit_blown | term()}
        when result: term()
  def call(fuse_name \\ @fuse_name, fun) when is_function(fun, 0) do
    case :fuse.ask(fuse_name, :sync) do
      :ok ->
        try do
          case fun.() do
            {:ok, result} ->
              {:ok, result}

            # Handle 3-element tuple from VipsAdapter.load_image
            {:ok, _image, _dimensions} = result ->
              {:ok, result}

            {:error, reason} = error ->
              # Record failure for circuit breaker
              :fuse.melt(fuse_name)

              Logger.warning("Image processing operation failed",
                reason: inspect(reason),
                fuse_name: fuse_name
              )

              error
          end
        rescue
          error ->
            # Native crashes or exceptions - definitely record failure
            :fuse.melt(fuse_name)

            Logger.error("Image processing exception",
              error: inspect(error),
              fuse_name: fuse_name
            )

            {:error, {:exception, error}}
        catch
          :exit, reason ->
            :fuse.melt(fuse_name)

            Logger.error("Image processing exit",
              reason: inspect(reason),
              fuse_name: fuse_name
            )

            {:error, {:exit, reason}}
        end

      :blown ->
        Logger.warning("Circuit breaker open - image processing disabled",
          fuse_name: fuse_name
        )

        {:error, :circuit_blown}

      {:error, :not_found} ->
        # Fuse not installed, install it and retry
        install()
        call(fuse_name, fun)
    end
  end

  @doc """
  Checks if the circuit breaker is currently open (blown).

  ## Examples

      if CircuitBreaker.blown?(), do: :skip, else: process_image()
  """
  @spec blown?(atom()) :: boolean()
  def blown?(fuse_name \\ @fuse_name) do
    case :fuse.ask(fuse_name, :sync) do
      :blown -> true
      _ -> false
    end
  end

  @doc """
  Manually resets the circuit breaker.

  Useful for testing or manual recovery after fixing the underlying issue.
  """
  @spec reset(atom()) :: :ok
  def reset(fuse_name \\ @fuse_name) do
    _ = :fuse.reset(fuse_name)
    Logger.info("Circuit breaker manually reset", fuse_name: fuse_name)
    :ok
  end

  @doc """
  Returns the current status of the circuit breaker.

  ## Examples

      CircuitBreaker.status()
      #=> :ok | :blown
  """
  @spec status(atom()) :: :ok | :blown | {:error, :not_found}
  def status(fuse_name \\ @fuse_name) do
    :fuse.ask(fuse_name, :sync)
  end
end
