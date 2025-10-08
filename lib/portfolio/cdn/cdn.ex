defmodule Portfolio.CDN do
  @moduledoc """
  Behaviour for CDN cache invalidation.

  This defines the contract for CDN providers (CloudFlare, CloudFront, etc.)
  to invalidate cached content when albums are published or updated.

  ## Usage

  Configure the CDN module in config:

      config :portfolio, :cdn_module, Portfolio.CDN.CloudFlare

  ## Implementing a CDN Provider

      defmodule Portfolio.CDN.CloudFlare do
        @behaviour Portfolio.CDN

        @impl true
        def invalidate(paths) do
          # Implementation for CloudFlare API
        end
      end
  """

  @doc """
  Invalidates the CDN cache for the given paths.

  ## Parameters

  - `paths` - List of URL paths to invalidate (e.g., ["/albums/wedding-2024"])

  ## Returns

  - `:ok` - Cache invalidation successful
  - `{:error, reason}` - Cache invalidation failed
  """
  @callback invalidate(paths :: [String.t()]) :: :ok | {:error, term()}
end
