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
end
