defmodule Portfolio.Workers.ObanJobScenariosTest do
  @moduledoc """
  Tests for Oban job scenarios: retry behavior, snooze, cancellation, and timeout handling.

  These tests verify that our workers correctly implement Oban's job lifecycle
  and error handling patterns.
  """

  use Portfolio.DataCase, async: false
  use Oban.Testing, repo: Portfolio.Repo

  import ExUnit.CaptureLog
  import Mox

  alias Portfolio.Photography.Storage.MockStorage
  alias Portfolio.Workers.ImageVariantWorker

  setup :verify_on_exit!
  setup :set_mox_from_context

  setup do
    original_config = Application.get_env(:portfolio, :file_storage)
    Application.put_env(:portfolio, :file_storage, backend: MockStorage)

    on_exit(fn ->
      Application.put_env(:portfolio, :file_storage, original_config)
    end)

    :ok
  end

  describe "retry scenarios" do
    test "transient errors trigger retry with proper backoff" do
      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :io_error}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "retry-test-photo"})
          # Transient errors should return {:error, _} to trigger Oban retry
          assert {:error, :io_error} = result
        end)

      assert log =~ "Image processing failed, will retry"
    end

    test "permanent errors cancel job without retry" do
      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :file_not_found}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "permanent-error-photo"})
          # Permanent errors should return {:cancel, _} to stop retries
          assert {:cancel, {:error, :file_not_found}} = result
        end)

      assert log =~ "Photo file not found - cancelling job"
    end

    test "corrupted file cancels job" do
      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :corrupted_file}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "corrupted-photo"})
          assert {:cancel, {:error, :corrupted_file}} = result
        end)

      assert log =~ "Photo file is corrupted - cancelling job"
    end
  end

  describe "snooze scenarios" do
    test "circuit breaker open snoozes job for 30 seconds" do
      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :service_unavailable}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "snooze-test-photo"})
          # Service unavailable should snooze to wait for circuit breaker recovery
          assert {:snooze, 30} = result
        end)

      assert log =~ "circuit breaker open"
    end
  end

  describe "job configuration" do
    test "ImageVariantWorker has correct queue configuration" do
      job = ImageVariantWorker.new(%{photo_id: "test"})

      assert job.changes.queue == "image_processing"
      assert job.changes.max_attempts == 3
      assert job.changes.priority == 1
    end

    test "multiple jobs can be enqueued for same photo_id" do
      # Without unique configuration, multiple jobs can be enqueued
      {:ok, job1} = ImageVariantWorker.enqueue("same-photo-id")
      {:ok, job2} = ImageVariantWorker.enqueue("same-photo-id")

      # Jobs are separate (no uniqueness constraint)
      refute job1.id == job2.id
      assert job1.args == job2.args
    end

    test "different photos create separate jobs" do
      {:ok, job1} = ImageVariantWorker.enqueue("photo-1")
      {:ok, job2} = ImageVariantWorker.enqueue("photo-2")

      refute job1.id == job2.id
    end
  end

  describe "telemetry integration" do
    test "successful job emits start and stop events" do
      test_pid = self()
      handler_id = "oban-scenario-test-#{System.unique_integer([:positive])}"

      events = [
        [:portfolio, :image, :processing, :start],
        [:portfolio, :image, :processing, :stop]
      ]

      :telemetry.attach_many(
        handler_id,
        events,
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:ok, %{thumbnail: "/path/thumb.webp"}}
      end)

      perform_job(ImageVariantWorker, %{"photo_id" => "telemetry-test"})

      assert_receive {:telemetry, [:portfolio, :image, :processing, :start], %{system_time: _},
                      %{photo_id: "telemetry-test"}}

      assert_receive {:telemetry, [:portfolio, :image, :processing, :stop], %{duration: duration},
                      %{photo_id: "telemetry-test", variant_count: 1}}

      # Duration may be 0 if execution is very fast (mock)
      assert is_integer(duration) and duration >= 0
    end

    test "failed job emits exception event" do
      test_pid = self()
      handler_id = "oban-exception-test-#{System.unique_integer([:positive])}"

      :telemetry.attach(
        handler_id,
        [:portfolio, :image, :processing, :exception],
        fn _event, _measurements, metadata, _config ->
          send(test_pid, {:telemetry_exception, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler_id) end)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :file_not_found}
      end)

      capture_log(fn ->
        perform_job(ImageVariantWorker, %{"photo_id" => "exception-test"})
      end)

      assert_receive {:telemetry_exception,
                      %{photo_id: "exception-test", reason: :file_not_found}}
    end
  end

  describe "error handling edge cases" do
    test "handles unknown error types gracefully" do
      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :unknown_weird_error}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "unknown-error-photo"})
          # Unknown errors should be returned for retry
          assert {:error, :unknown_weird_error} = result
        end)

      assert log =~ "Image processing failed"
    end

    test "handles nil photo_id gracefully" do
      MockStorage
      |> expect(:generate_variants, fn nil ->
        {:error, :invalid_photo_id}
      end)

      log =
        capture_log(fn ->
          # Worker should handle nil gracefully
          result = perform_job(ImageVariantWorker, %{"photo_id" => nil})

          assert match?({:error, _}, result) or match?({:cancel, _}, result)
        end)

      # Should log something about the failure
      assert log != ""
    end
  end
end
