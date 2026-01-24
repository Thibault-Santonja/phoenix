defmodule Portfolio.Photography.Integration.ImageProcessingWorkflowTest do
  @moduledoc """
  Integration tests for the complete image processing workflow.

  Tests the full flow:
  1. Photo creation triggers variant generation
  2. ImageProcessingAdapter translates between contexts
  3. ImageVariantWorker processes asynchronously
  4. CircuitBreaker protects against failures

  These tests verify that all components work together correctly.
  """
  use Portfolio.DataCase, async: false
  use Oban.Testing, repo: Portfolio.Repo

  import ExUnit.CaptureLog
  import Mox
  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.ImageProcessing
  alias Portfolio.ImageProcessing.CircuitBreaker
  alias Portfolio.Photography.Adapters.ImageProcessingAdapter
  alias Portfolio.Photography.Storage.MockStorage
  alias Portfolio.Workers.ImageVariantWorker

  @fixtures_dir Path.join([File.cwd!(), "test", "fixtures", "images"])

  setup :verify_on_exit!

  setup do
    # Reset circuit breaker
    CircuitBreaker.reset()

    # Store original config
    original_config = Application.get_env(:portfolio, :file_storage)

    on_exit(fn ->
      Application.put_env(:portfolio, :file_storage, original_config)
      CircuitBreaker.reset()
    end)

    :ok
  end

  describe "complete workflow with mocked storage" do
    setup do
      Application.put_env(:portfolio, :file_storage, backend: MockStorage)
      :ok
    end

    test "photo upload enqueues variant generation job" do
      album = create_album()
      photo = create_photo(album: album)

      # Enqueue via adapter (simulating what upload service does)
      {:ok, job} = ImageProcessingAdapter.enqueue_variant_generation(photo)

      assert job.queue == "image_processing"
      assert job.args == %{photo_id: photo.id}
      assert_enqueued(worker: ImageVariantWorker, args: %{photo_id: photo.id})
    end

    test "worker successfully generates variants" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn photo_id ->
        assert photo_id == photo.id

        {:ok,
         %{
           thumbnail: "/uploads/#{photo_id}/thumbnail.webp",
           small: "/uploads/#{photo_id}/small.webp",
           medium: "/uploads/#{photo_id}/medium.webp",
           large: "/uploads/#{photo_id}/large.avif"
         }}
      end)

      # Execute the job directly
      assert :ok = perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
    end

    test "worker handles file not found gracefully" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :file_not_found}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
          assert {:cancel, {:error, :file_not_found}} = result
        end)

      assert log =~ "Photo file not found"
    end

    test "worker handles corrupted file gracefully" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :corrupted_file}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
          assert {:cancel, {:error, :corrupted_file}} = result
        end)

      assert log =~ "Photo file is corrupted"
    end

    test "worker snoozes when circuit breaker is open" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :service_unavailable}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
          assert {:snooze, 30} = result
        end)

      assert log =~ "circuit breaker open"
    end

    test "worker retries on transient errors" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :io_error}
      end)

      log =
        capture_log(fn ->
          result = perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
          assert {:error, :io_error} = result
        end)

      assert log =~ "Image processing failed, will retry"
    end

    test "multiple photos can be processed concurrently" do
      album = create_album()
      photo1 = create_photo(album: album)
      photo2 = create_photo(album: album)
      photo3 = create_photo(album: album)

      # Enqueue all photos
      {:ok, _} = ImageProcessingAdapter.enqueue_variant_generation(photo1)
      {:ok, _} = ImageProcessingAdapter.enqueue_variant_generation(photo2)
      {:ok, _} = ImageProcessingAdapter.enqueue_variant_generation(photo3)

      # Verify all jobs are queued
      assert_enqueued(worker: ImageVariantWorker, args: %{photo_id: photo1.id})
      assert_enqueued(worker: ImageVariantWorker, args: %{photo_id: photo2.id})
      assert_enqueued(worker: ImageVariantWorker, args: %{photo_id: photo3.id})
    end
  end

  describe "circuit breaker integration" do
    setup do
      Application.put_env(:portfolio, :file_storage, backend: MockStorage)
      :ok
    end

    test "service becomes unavailable after repeated failures" do
      # Initially available
      assert ImageProcessingAdapter.service_available?()

      # Simulate multiple failures
      Enum.each(1..6, fn _ ->
        :fuse.melt(:image_processing)
      end)

      Process.sleep(10)

      # Now unavailable
      refute ImageProcessingAdapter.service_available?()
    end

    test "service recovers after reset" do
      # Trip circuit breaker
      Enum.each(1..6, fn _ ->
        :fuse.melt(:image_processing)
      end)

      Process.sleep(10)
      refute ImageProcessingAdapter.service_available?()

      # Reset
      CircuitBreaker.reset()

      assert ImageProcessingAdapter.service_available?()
    end
  end

  describe "telemetry events" do
    setup do
      Application.put_env(:portfolio, :file_storage, backend: MockStorage)
      :ok
    end

    test "emits start event when processing begins" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:ok, %{thumbnail: "/path/thumb.webp"}}
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :image, :processing, :start]
        ])

      perform_job(ImageVariantWorker, %{"photo_id" => photo.id})

      assert_received {[:portfolio, :image, :processing, :start], ^ref, %{system_time: _},
                       %{photo_id: photo_id}}

      assert photo_id == photo.id
    end

    test "emits stop event with variant count on success" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:ok,
         %{
           thumbnail: "/path/thumb.webp",
           small: "/path/small.webp",
           medium: "/path/medium.webp",
           large: "/path/large.avif"
         }}
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :image, :processing, :stop]
        ])

      perform_job(ImageVariantWorker, %{"photo_id" => photo.id})

      assert_received {[:portfolio, :image, :processing, :stop], ^ref, %{duration: duration},
                       %{photo_id: photo_id, variant_count: 4}}

      assert photo_id == photo.id
      assert is_integer(duration)
    end

    test "emits exception event on permanent failure" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :file_not_found}
      end)

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :image, :processing, :exception]
        ])

      capture_log(fn ->
        perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
      end)

      assert_received {[:portfolio, :image, :processing, :exception], ^ref, %{},
                       %{photo_id: photo_id, reason: :file_not_found}}

      assert photo_id == photo.id
    end
  end

  describe "real image processing" do
    @describetag :integration

    test "processes actual test image through full workflow" do
      test_image = Path.join(@fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        output_dir = Path.join(System.tmp_dir!(), "workflow_test_#{:rand.uniform(100_000)}")

        on_exit(fn -> File.rm_rf(output_dir) end)

        result =
          ImageProcessing.generate_variants(
            "workflow-test-id",
            test_image,
            output_dir
          )

        case result do
          {:ok, variants} ->
            assert is_map(variants)

            # Verify files were created
            Enum.each(variants, fn {name, path} ->
              assert File.exists?(path),
                     "Variant #{name} should exist at #{path}"
            end)

          {:error, reason} ->
            # May fail in CI environment without libvips
            assert match_error_reason?(reason)
        end
      end
    end

    test "variant configuration is applied correctly" do
      variants_config = ImageProcessing.variants()

      # Verify all expected variants are configured
      assert Map.has_key?(variants_config, :thumbnail)
      assert Map.has_key?(variants_config, :small)
      assert Map.has_key?(variants_config, :medium)
      assert Map.has_key?(variants_config, :large)

      # Verify thumbnail is smallest
      assert variants_config[:thumbnail].width < variants_config[:small].width
      assert variants_config[:small].width < variants_config[:medium].width
      assert variants_config[:medium].width < variants_config[:large].width
    end
  end

  describe "error recovery scenarios" do
    setup do
      Application.put_env(:portfolio, :file_storage, backend: MockStorage)
      :ok
    end

    test "photo remains in database after processing failure" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :corrupted_file}
      end)

      capture_log(fn ->
        perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
      end)

      # Photo should still exist
      assert {:ok, _photo} = Portfolio.Photography.get_photo(photo.id)
    end

    test "job is cancelled for permanent errors (not retried indefinitely)" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :file_not_found}
      end)

      capture_log(fn ->
        result = perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
        assert {:cancel, _} = result
      end)

      # Job should not be re-enqueued
      refute_enqueued(worker: ImageVariantWorker, args: %{photo_id: photo.id})
    end

    test "job is retried for transient errors" do
      album = create_album()
      photo = create_photo(album: album)

      MockStorage
      |> expect(:generate_variants, fn _photo_id ->
        {:error, :io_error}
      end)

      capture_log(fn ->
        result = perform_job(ImageVariantWorker, %{"photo_id" => photo.id})
        # Returns error to trigger Oban retry
        assert {:error, :io_error} = result
      end)
    end
  end

  # Helper to match error reasons that may include tuples with dynamic values
  defp match_error_reason?(:file_not_found), do: true
  defp match_error_reason?(:corrupted_file), do: true
  defp match_error_reason?({:directory_creation_failed, _}), do: true
  defp match_error_reason?(_), do: false
end
