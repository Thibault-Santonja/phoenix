defmodule Portfolio.CDN.NoOp do
  @moduledoc """
  No-op CDN implementation for development and environments without CDN.

  This implementation does nothing and always returns success.
  Used as the default when no CDN is configured.

  ## Usage

  This is the default CDN module. To explicitly configure:

      config :portfolio, :cdn_module, Portfolio.CDN.NoOp
  """

  @behaviour Portfolio.CDN

  require Logger

  @impl true
  @doc """
  No-op implementation that logs the invalidation request but does nothing.
  """
  def invalidate(paths) when is_list(paths) do
    Logger.debug("CDN invalidation (no-op)",
      paths: paths,
      message: "CDN not configured, skipping cache invalidation"
    )

    :ok
  end
end
