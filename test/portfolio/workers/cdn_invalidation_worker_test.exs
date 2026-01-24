defmodule Portfolio.Workers.CdnInvalidationWorkerTest do
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo

  import ExUnit.CaptureLog

  alias Portfolio.Workers.CdnInvalidationWorker

  describe "enqueue/2" do
    test "creates a job with correct args" do
      assert {:ok, job} =
               CdnInvalidationWorker.enqueue("wedding-2024", ["/", "/albums/wedding-2024"])

      # Args are atom keys before insertion, string keys after JSON serialization
      assert job.args[:album_slug] == "wedding-2024"
      assert job.args[:paths] == ["/", "/albums/wedding-2024"]
      assert job.queue == "cdn"
      assert job.max_attempts == 5
      assert job.priority == 2
    end

    test "accepts empty paths list" do
      assert {:ok, job} = CdnInvalidationWorker.enqueue("album-slug", [])
      assert job.args[:paths] == []
    end
  end

  describe "perform/1" do
    test "successfully invalidates CDN cache with NoOp module" do
      # Default config uses NoOp which always returns :ok
      assert :ok =
               perform_job(CdnInvalidationWorker, %{
                 "album_slug" => "test-album",
                 "paths" => ["/", "/albums/test-album"]
               })
    end

    test "emits telemetry span on execution" do
      test_pid = self()

      :telemetry.attach(
        "test-cdn-invalidation-start",
        [:portfolio, :cdn, :invalidation, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_start, event, measurements, metadata})
        end,
        nil
      )

      :telemetry.attach(
        "test-cdn-invalidation-stop",
        [:portfolio, :cdn, :invalidation, :stop],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry_stop, event, measurements, metadata})
        end,
        nil
      )

      perform_job(CdnInvalidationWorker, %{
        "album_slug" => "telemetry-test",
        "paths" => ["/test"]
      })

      assert_receive {:telemetry_start, [:portfolio, :cdn, :invalidation, :start], _, metadata}
      assert metadata.album_slug == "telemetry-test"
      assert metadata.path_count == 1

      assert_receive {:telemetry_stop, [:portfolio, :cdn, :invalidation, :stop], measurements, _}
      assert is_integer(measurements.duration)

      :telemetry.detach("test-cdn-invalidation-start")
      :telemetry.detach("test-cdn-invalidation-stop")
    end

    test "handles multiple paths" do
      paths = ["/", "/albums", "/albums/wedding-2024", "/albums/wedding-2024/photos"]

      assert :ok =
               perform_job(CdnInvalidationWorker, %{
                 "album_slug" => "wedding-2024",
                 "paths" => paths
               })
    end

    test "returns error when CDN module fails" do
      # Create a mock CDN module that fails
      defmodule FailingCDN do
        @behaviour Portfolio.CDN

        @impl true
        def invalidate(_paths), do: {:error, :network_timeout}
      end

      # Temporarily override CDN module
      original_cdn = Application.get_env(:portfolio, :cdn_module)
      Application.put_env(:portfolio, :cdn_module, FailingCDN)

      try do
        log =
          capture_log([level: :warning], fn ->
            result =
              perform_job(CdnInvalidationWorker, %{
                "album_slug" => "fail-test",
                "paths" => ["/test"]
              })

            assert {:error, :network_timeout} = result
          end)

        assert log =~ "CDN invalidation failed"
        assert log =~ "will retry"
      after
        # Restore original config
        if original_cdn do
          Application.put_env(:portfolio, :cdn_module, original_cdn)
        else
          Application.delete_env(:portfolio, :cdn_module)
        end
      end
    end

    test "handles empty paths list" do
      assert :ok =
               perform_job(CdnInvalidationWorker, %{
                 "album_slug" => "empty-test",
                 "paths" => []
               })
    end
  end

  describe "job configuration" do
    test "uses cdn queue" do
      assert CdnInvalidationWorker.__opts__()[:queue] == :cdn
    end

    test "has max 5 attempts" do
      assert CdnInvalidationWorker.__opts__()[:max_attempts] == 5
    end

    test "has priority 2" do
      assert CdnInvalidationWorker.__opts__()[:priority] == 2
    end
  end
end
