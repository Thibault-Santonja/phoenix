defmodule Portfolio.Services.Service do
  @moduledoc """
  Behaviour for Application Services in the Service Layer.

  Services encapsulate complex business workflows that:
  - Coordinate multiple domain operations
  - Span multiple bounded contexts
  - Require orchestration logic (Ecto.Multi, Task.async_stream, etc.)
  - Emit domain events and telemetry
  - Handle cross-cutting concerns (caching, rate limiting, etc.)

  ## Service Layer vs Context

  **Contexts** (Photography, Auth):
  - Define the public API for a bounded context
  - Delegate to repositories, query objects, and services
  - Focus on domain operations within the bounded context

  **Services** (PhotoUploadService, AlbumPublicationService):
  - Implement complex workflows that may span multiple entities
  - Handle orchestration, error recovery, and compensating actions
  - Emit telemetry and domain events
  - Keep contexts thin and focused

  ## Example Service

      defmodule Portfolio.Services.Photography.AlbumPublicationService do
        @behaviour Portfolio.Services.Service

        alias Portfolio.Photography.{Album, Photo}
        alias Portfolio.DomainEvents

        @impl true
        def execute(%Album{} = album, opts \\\\ []) do
          # Complex workflow orchestration
        end
      end

  ## Usage in Context

      def publish_album(%Album{} = album, user_id \\\\ nil) do
        AlbumPublicationService.execute(album, user_id: user_id)
      end
  """

  @doc """
  Executes the service with given parameters.

  Returns `{:ok, result}` on success or `{:error, reason}` on failure.
  """
  @callback execute(params :: term(), opts :: keyword()) ::
              {:ok, term()} | {:error, term()}

  @doc """
  Macro to include telemetry helpers in service modules.

  Provides `with_telemetry/3` function to wrap service execution
  with automatic timing and telemetry emission.

  ## Example

      defmodule MyService do
        use Portfolio.Services.Service

        def execute(params, opts) do
          with_telemetry(
            [:my_app, :service, :executed],
            %{param_count: length(params)},
            fn -> do_work(params, opts) end
          )
        end

        defp do_work(params, opts) do
          # Service logic here
          {:ok, result}
        end
      end
  """
  defmacro __using__(_opts) do
    quote do
      @behaviour Portfolio.Services.Service

      # Wraps a function with telemetry instrumentation.
      #
      # Measures execution time and emits a telemetry event with the result.
      #
      # ## Parameters
      #
      # - `event_name` - List representing the telemetry event name
      # - `metadata` - Map of additional metadata to include in the event
      # - `fun` - Zero-arity function to execute and measure
      #
      # ## Returns
      #
      # The result of executing `fun`, unchanged.
      #
      # ## Telemetry Event
      #
      # Emits `event_name` with:
      # - Measurements: `%{duration: integer()}` - Time in native units
      # - Metadata: `%{result: :ok | :error, ...}` - Result status + provided metadata
      #
      # ## Example
      #
      #     with_telemetry(
      #       [:portfolio, :photography, :album, :published],
      #       %{user_id: user_id},
      #       fn ->
      #         AlbumRepository.update(album, %{published: true})
      #       end
      #     )
      defp with_telemetry(event_name, metadata, fun)
           when is_list(event_name) and is_map(metadata) and is_function(fun, 0) do
        start_time = System.monotonic_time()
        result = fun.()
        duration = System.monotonic_time() - start_time

        :telemetry.execute(
          event_name,
          %{duration: duration},
          Map.merge(%{result: elem(result, 0)}, metadata)
        )

        result
      end
    end
  end
end
