defmodule Portfolio.Workers.MagicLinkCleanerWorker do
  @moduledoc """
  Oban worker for periodically cleaning up expired magic links.

  This worker is automatically executed via Oban.Plugins.Cron according to the configuration.
  It deletes magic links whose expiration date has passed to:
  - Free up database space
  - Maintain data consistency
  - Follow security best practices (expired tokens = deleted)

  ## Configuration

  The execution frequency is configured in `config/config.exs`:

      config :portfolio, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"0 * * * *", Portfolio.Workers.MagicLinkCleanerWorker}  # Every hour
           ]}
        ]

  ## Metrics

  Emits a telemetry event `[:portfolio, :workers, :magic_link_cleaner, :executed]`
  with the number of deleted magic links.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Portfolio.Auth.MagicLinkService

  require Logger

  @impl Oban.Worker
  @doc """
  Executes the cleanup of expired magic links.

  ## Examples

      iex> perform(%Oban.Job{})
      :ok
  """
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{} = _job) do
    start_time = System.monotonic_time()

    Logger.info("Starting magic links cleanup")

    {count, _} = MagicLinkService.delete_expired_magic_links()

    duration = System.monotonic_time() - start_time

    Logger.info("Magic links cleanup completed: #{count} expired magic links deleted")

    # Emit telemetry metrics
    :telemetry.execute(
      [:portfolio, :workers, :magic_link_cleaner, :executed],
      %{duration: duration, deleted_count: count},
      %{success: true}
    )

    :ok
  end
end
