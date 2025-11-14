defmodule Portfolio.Workers.SessionCleanerWorker do
  @moduledoc """
  Oban worker for periodically cleaning up expired sessions.

  This worker is automatically executed via Oban.Plugins.Cron according to the configuration.
  It deletes sessions whose last activity exceeds the configured
  expiration delay (default 2 hours of inactivity).

  ## Benefits

  - Frees up database space
  - Maintains data consistency (expired sessions = deleted)
  - Improves query performance (less data to scan)
  - Respects security policy (inactive sessions revoked)

  ## Configuration

  The execution frequency is configured in `config/config.exs`:

      config :portfolio, Oban,
        plugins: [
          {Oban.Plugins.Cron,
           crontab: [
             {"*/15 * * * *", Portfolio.Workers.SessionCleanerWorker}  # Every 15 minutes
           ]}
        ]

  The session expiration delay is configured via:

      config :portfolio, :auth,
        session_expiration_seconds: 2 * 60 * 60  # 2 hours

  ## Metrics

  Emits a telemetry event `[:portfolio, :workers, :session_cleaner, :executed]`
  with the number of deleted sessions and execution duration.
  """

  use Oban.Worker, queue: :default, max_attempts: 3

  alias Portfolio.Auth.SessionService

  require Logger

  @impl Oban.Worker
  @doc """
  Executes the cleanup of expired sessions.

  Deletes all sessions whose last activity exceeds
  the configured expiration delay.

  ## Examples

      iex> perform(%Oban.Job{})
      :ok
  """
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{} = _job) do
    start_time = System.monotonic_time()

    Logger.info("Starting sessions cleanup")

    {count, _} = SessionService.delete_expired_sessions()

    duration = System.monotonic_time() - start_time

    Logger.info("Sessions cleanup completed: #{count} expired sessions deleted")

    # Emit telemetry metrics
    :telemetry.execute(
      [:portfolio, :workers, :session_cleaner, :executed],
      %{duration: duration, deleted_count: count},
      %{success: true}
    )

    :ok
  end
end
