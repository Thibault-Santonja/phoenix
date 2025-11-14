defmodule PortfolioWeb.Telemetry do
  use Supervisor
  import Telemetry.Metrics

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(_arg) do
    attach_handlers()

    children = [
      # Telemetry poller will execute the given period measurements
      # every 10_000ms. Learn more here: https://hexdocs.pm/telemetry_metrics
      {:telemetry_poller, measurements: periodic_measurements(), period: 10_000}
      # Add reporters as children of your supervision tree.
      # {Telemetry.Metrics.ConsoleReporter, metrics: metrics()}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def metrics do
    [
      # Photography Metrics - Albums
      counter("portfolio.photography.album.created.count"),
      distribution("portfolio.photography.album.created.duration",
        unit: {:native, :millisecond}
      ),
      counter("portfolio.photography.album.updated.count"),
      distribution("portfolio.photography.album.updated.duration",
        unit: {:native, :millisecond}
      ),

      # Photography Metrics - Photos
      counter("portfolio.photography.photo.created.count"),
      distribution("portfolio.photography.photo.created.duration",
        unit: {:native, :millisecond}
      ),
      counter("portfolio.photography.photo.updated.count"),
      distribution("portfolio.photography.photo.updated.duration",
        unit: {:native, :millisecond}
      ),
      counter("portfolio.photography.photo.deleted.count"),
      distribution("portfolio.photography.photo.deleted.duration",
        unit: {:native, :millisecond}
      ),
      counter("portfolio.photography.photos.uploaded.count"),
      sum("portfolio.photography.photos.uploaded.total",
        measurement: :count
      ),
      distribution("portfolio.photography.photos.uploaded.duration",
        unit: {:native, :millisecond}
      ),

      # Auth Metrics
      counter("portfolio.auth.magic_link.requested.count"),
      distribution("portfolio.auth.magic_link.requested.duration",
        unit: {:native, :millisecond}
      ),
      counter("portfolio.auth.magic_link.verified.count"),
      distribution("portfolio.auth.magic_link.verified.duration",
        unit: {:native, :millisecond}
      ),

      # Rate Limiter Metrics
      counter("portfolio.rate_limiter.check.count",
        tags: [:action, :result]
      ),
      distribution("portfolio.rate_limiter.check.duration",
        tags: [:action],
        unit: {:native, :millisecond}
      ),
      counter("portfolio.rate_limiter.allowed.count",
        tags: [:action]
      ),
      counter("portfolio.rate_limiter.denied.count",
        tags: [:action]
      ),
      summary("portfolio.rate_limiter.remaining.value",
        tags: [:action],
        unit: :unit
      ),
      summary("portfolio.rate_limiter.retry_after.value",
        tags: [:action],
        unit: {:native, :millisecond}
      ),

      # Phoenix Metrics
      summary("phoenix.endpoint.start.system_time",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.endpoint.stop.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.start.system_time",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.exception.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.router_dispatch.stop.duration",
        tags: [:route],
        unit: {:native, :millisecond}
      ),
      summary("phoenix.socket_connected.duration",
        unit: {:native, :millisecond}
      ),
      sum("phoenix.socket_drain.count"),
      summary("phoenix.channel_joined.duration",
        unit: {:native, :millisecond}
      ),
      summary("phoenix.channel_handled_in.duration",
        tags: [:event],
        unit: {:native, :millisecond}
      ),

      # VM Metrics
      summary("vm.memory.total", unit: {:byte, :kilobyte}),
      summary("vm.total_run_queue_lengths.total"),
      summary("vm.total_run_queue_lengths.cpu"),
      summary("vm.total_run_queue_lengths.io")
    ]
  end

  defp periodic_measurements do
    [
      # A module, function and arguments to be invoked periodically.
      # This function must call :telemetry.execute/3 and a metric must be added above.
      # {PortfolioWeb, :count_users, []}
    ]
  end

  defp attach_handlers do
    :telemetry.attach(
      "portfolio-photography-album-created",
      [:portfolio, :photography, :album, :created],
      &__MODULE__.handle_album_created/4,
      nil
    )

    :telemetry.attach(
      "portfolio-photography-photos-uploaded",
      [:portfolio, :photography, :photos, :uploaded],
      &__MODULE__.handle_photos_uploaded/4,
      nil
    )

    :telemetry.attach(
      "portfolio-auth-magic-link-requested",
      [:portfolio, :auth, :magic_link, :requested],
      &__MODULE__.handle_magic_link_requested/4,
      nil
    )

    :telemetry.attach(
      "portfolio-auth-magic-link-verified",
      [:portfolio, :auth, :magic_link, :verified],
      &__MODULE__.handle_magic_link_verified/4,
      nil
    )

    :telemetry.attach(
      "portfolio-rate-limiter-check",
      [:portfolio, :rate_limiter, :check],
      &__MODULE__.handle_rate_limiter_check/4,
      nil
    )
  end

  def handle_album_created(_event, %{duration: duration}, %{result: result}, _config) do
    require Logger

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.info("Album created",
      result: result,
      duration_ms: duration_ms
    )
  end

  def handle_photos_uploaded(_event, %{duration: duration}, metadata, _config) do
    require Logger

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.info("Photos uploaded",
      album_slug: metadata.album_slug,
      count: metadata.count,
      result: metadata.result,
      duration_ms: duration_ms
    )
  end

  def handle_magic_link_requested(_event, %{duration: duration}, metadata, _config) do
    require Logger

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.info("Magic link requested",
      email: metadata.email,
      result: metadata.result,
      duration_ms: duration_ms
    )
  end

  def handle_magic_link_verified(_event, %{duration: duration}, %{result: result}, _config) do
    require Logger

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    Logger.info("Magic link verified",
      result: result,
      duration_ms: duration_ms
    )
  end

  def handle_rate_limiter_check(_event, %{duration: duration}, metadata, _config) do
    require Logger

    duration_ms = System.convert_time_unit(duration, :native, :millisecond)

    case metadata.result do
      :allow ->
        Logger.debug("Rate limit check: allowed",
          action: metadata.action,
          identifier: metadata.identifier,
          remaining: metadata.remaining,
          duration_ms: duration_ms
        )

      :deny ->
        retry_after_seconds = div(metadata.retry_after_ms, 1000)

        Logger.warning("Rate limit check: denied",
          action: metadata.action,
          identifier: metadata.identifier,
          retry_after_seconds: retry_after_seconds,
          duration_ms: duration_ms
        )
    end
  end
end
