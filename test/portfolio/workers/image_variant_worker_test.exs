defmodule Portfolio.Workers.ImageVariantWorkerTest do
  # Must be async: false to avoid config pollution
  use Portfolio.DataCase, async: false
  use Oban.Testing, repo: Portfolio.Repo

  import ExUnit.CaptureLog
  import Mox

  alias Portfolio.Photography.Storage.MockStorage
  alias Portfolio.Workers.ImageVariantWorker

  # Allow Mox expectations to be verified
  setup :verify_on_exit!

  setup do
    # Store original config and set mock
    original_config = Application.get_env(:portfolio, :file_storage)
    Application.put_env(:portfolio, :file_storage, backend: MockStorage)

    on_exit(fn ->
      # Always restore original config to avoid polluting other tests
      Application.put_env(:portfolio, :file_storage, original_config)
    end)

    :ok
  end

  describe "perform/1" do
    test "successfully generates variants for a photo" do
      MockStorage
      |> expect(:generate_variants, fn "success_photo" ->
        {:ok, %{thumbnail: "/path/thumb.webp", small: "/path/small.webp"}}
      end)

      # The worker returns :ok even if photo is not in DB (variants were generated)
      assert :ok = perform_job(ImageVariantWorker, %{"photo_id" => "success_photo"})
    end

    test "cancels job for file not found error" do
      MockStorage
      |> expect(:generate_variants, fn "not_found_photo" ->
        {:error, :file_not_found}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "not_found_photo"})
          assert {:cancel, {:error, :file_not_found}} = result
        end)

      assert log =~ "Photo file not found - cancelling job"
    end

    test "cancels job for corrupted file error" do
      MockStorage
      |> expect(:generate_variants, fn "corrupted_photo" ->
        {:error, :corrupted_file}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "corrupted_photo"})
          assert {:cancel, {:error, :corrupted_file}} = result
        end)

      assert log =~ "Photo file is corrupted - cancelling job"
    end

    test "snoozes job when circuit breaker is open" do
      MockStorage
      |> expect(:generate_variants, fn "circuit_breaker_photo" ->
        {:error, :service_unavailable}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "circuit_breaker_photo"})
          assert {:snooze, 30} = result
        end)

      assert log =~ "circuit breaker open"
    end

    test "returns error for transient failures to trigger retry" do
      MockStorage
      |> expect(:generate_variants, fn "transient_error_photo" ->
        {:error, :io_error}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => "transient_error_photo"})
          assert {:error, :io_error} = result
        end)

      assert log =~ "Image processing failed, will retry"
    end

    test "emits telemetry events on start" do
      MockStorage
      |> expect(:generate_variants, fn "success_photo" ->
        {:ok, %{thumbnail: "/path/thumb.webp", small: "/path/small.webp"}}
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :image, :processing, :start]
        ])

      perform_job(ImageVariantWorker, %{"photo_id" => "success_photo"})

      assert_received {[:portfolio, :image, :processing, :start], ^ref, %{system_time: _},
                       %{photo_id: "success_photo"}}
    end

    test "emits telemetry events on stop" do
      MockStorage
      |> expect(:generate_variants, fn "success_photo" ->
        {:ok, %{thumbnail: "/path/thumb.webp", small: "/path/small.webp"}}
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :image, :processing, :stop]
        ])

      perform_job(ImageVariantWorker, %{"photo_id" => "success_photo"})

      assert_received {[:portfolio, :image, :processing, :stop], ^ref, %{duration: _},
                       %{photo_id: "success_photo", variant_count: 2}}
    end

    test "emits telemetry events on exception" do
      MockStorage
      |> expect(:generate_variants, fn "not_found_photo" ->
        {:error, :file_not_found}
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :image, :processing, :exception]
        ])

      perform_job(ImageVariantWorker, %{"photo_id" => "not_found_photo"})

      assert_received {[:portfolio, :image, :processing, :exception], ^ref, %{},
                       %{photo_id: "not_found_photo", reason: :file_not_found}}
    end
  end

  describe "enqueue/1" do
    test "creates an Oban job for image variant generation" do
      assert {:ok, job} = ImageVariantWorker.enqueue("test_photo_id")
      assert job.args == %{photo_id: "test_photo_id"}
      assert job.queue == "image_processing"
    end
  end

  describe "job configuration" do
    test "uses image_processing queue" do
      job = ImageVariantWorker.new(%{photo_id: "test"})
      assert job.changes.queue == "image_processing"
    end

    test "has max_attempts of 3" do
      job = ImageVariantWorker.new(%{photo_id: "test"})
      assert job.changes.max_attempts == 3
    end

    test "has priority of 1" do
      job = ImageVariantWorker.new(%{photo_id: "test"})
      assert job.changes.priority == 1
    end
  end

  describe "perform/1 with database photo" do
    import PortfolioTest.Fixtures.PhotographyFixtures

    test "handles photo that exists in DB without crashing" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn photo_id when is_binary(photo_id) ->
        {:ok, %{thumbnail: "/path/thumb.webp", small: "/path/small.webp"}}
      end)

      # Should complete without error even if update fails (fields may not exist)
      assert :ok = perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
    end

    test "handles file not found for photo in DB without crashing" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :file_not_found}
      end)

      # Should cancel job and attempt to mark as failed
      capture_log(fn ->
        assert {:cancel, {:error, :file_not_found}} =
                 perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
      end)

      # Photo should still exist (not deleted)
      assert {:ok, _photo} = Portfolio.Photography.get_photo(photo.id)
    end

    test "handles corrupted file for photo in DB without crashing" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :corrupted_file}
      end)

      # Should cancel job and attempt to mark as failed
      capture_log(fn ->
        assert {:cancel, {:error, :corrupted_file}} =
                 perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
      end)

      # Photo should still exist (not deleted)
      assert {:ok, _photo} = Portfolio.Photography.get_photo(photo.id)
    end
  end
end
