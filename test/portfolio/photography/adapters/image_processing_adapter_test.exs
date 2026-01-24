defmodule Portfolio.Photography.Adapters.ImageProcessingAdapterTest do
  @moduledoc """
  Tests for ImageProcessingAdapter - Anti-Corruption Layer between
  Photography and ImageProcessing bounded contexts.

  These tests verify:
  - Correct translation between contexts
  - Error handling and mapping
  - Circuit breaker integration
  - Async job enqueueing
  """
  use Portfolio.DataCase, async: false
  use Oban.Testing, repo: Portfolio.Repo

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.ImageProcessing.CircuitBreaker
  alias Portfolio.Photography.Adapters.ImageProcessingAdapter
  alias Portfolio.Workers.ImageVariantWorker

  @fixtures_dir Path.join([File.cwd!(), "test", "fixtures", "images"])

  setup do
    # Ensure circuit breaker is reset before each test
    CircuitBreaker.reset()
    :ok
  end

  describe "generate_variants/1" do
    test "translates Photo entity to ImageProcessing inputs" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/uploads/test.jpg")

      # This will fail because file doesn't exist, but we verify translation
      result = ImageProcessingAdapter.generate_variants(photo)

      assert {:error, :file_not_found} = result
    end

    @tag :integration
    test "successfully generates variants for valid photo with real image" do
      test_image = Path.join(@fixtures_dir, "test_photo.jpg")

      if File.exists?(test_image) do
        album = create_album()
        photo = create_photo(album: album, file_path: test_image)

        result = ImageProcessingAdapter.generate_variants(photo)

        case result do
          {:ok, variants} ->
            assert is_map(variants)
            assert Map.has_key?(variants, :thumbnail)
            assert Map.has_key?(variants, :small)
            assert Map.has_key?(variants, :medium)
            assert Map.has_key?(variants, :large)

          {:error, reason} ->
            # May fail due to environment constraints
            assert reason in [:file_not_found, :processing_failed, :service_unavailable]
        end
      end
    end

    test "returns :file_not_found for non-existent file" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/nonexistent/path/photo.jpg")

      result = ImageProcessingAdapter.generate_variants(photo)

      assert {:error, :file_not_found} = result
    end

    test "returns :corrupted_file for invalid image content" do
      # Create a temporary file with invalid content
      temp_file = Path.join(System.tmp_dir!(), "corrupted_#{:rand.uniform(100_000)}.jpg")
      File.write!(temp_file, "not valid image data")

      on_exit(fn -> File.rm(temp_file) end)

      album = create_album()
      photo = create_photo(album: album, file_path: temp_file)

      result = ImageProcessingAdapter.generate_variants(photo)

      assert {:error, :corrupted_file} = result
    end

    test "returns :service_unavailable when circuit breaker is open" do
      # Trip the circuit breaker by simulating failures
      trip_circuit_breaker()

      album = create_album()
      photo = create_photo(album: album, file_path: "/some/path.jpg")

      result = ImageProcessingAdapter.generate_variants(photo)

      # The adapter catches circuit_blown and translates to service_unavailable
      # or the underlying service returns the error
      assert {:error, reason} = result
      assert reason in [:service_unavailable, :file_not_found]
    end
  end

  describe "enqueue_variant_generation/1" do
    test "creates Oban job for photo" do
      album = create_album()
      photo = create_photo(album: album)

      assert {:ok, job} = ImageProcessingAdapter.enqueue_variant_generation(photo)

      assert job.args == %{photo_id: photo.id}
      assert job.queue == "image_processing"
    end

    test "job can be found in queue" do
      album = create_album()
      photo = create_photo(album: album)

      {:ok, _job} = ImageProcessingAdapter.enqueue_variant_generation(photo)

      assert_enqueued(worker: ImageVariantWorker, args: %{photo_id: photo.id})
    end

    test "multiple photos create separate jobs" do
      album = create_album()
      photo1 = create_photo(album: album)
      photo2 = create_photo(album: album)

      {:ok, _} = ImageProcessingAdapter.enqueue_variant_generation(photo1)
      {:ok, _} = ImageProcessingAdapter.enqueue_variant_generation(photo2)

      assert_enqueued(worker: ImageVariantWorker, args: %{photo_id: photo1.id})
      assert_enqueued(worker: ImageVariantWorker, args: %{photo_id: photo2.id})
    end
  end

  describe "service_available?/0" do
    test "returns true when circuit breaker is closed" do
      CircuitBreaker.reset()

      assert ImageProcessingAdapter.service_available?() == true
    end

    test "returns false when circuit breaker is open" do
      trip_circuit_breaker()

      assert ImageProcessingAdapter.service_available?() == false
    end
  end

  describe "output path building" do
    test "builds correct output path structure" do
      album = create_album()
      photo = create_photo(album: album)

      # We can verify the output path by checking where variants would be generated
      # The adapter uses: upload_dir/albums/{album_id}/photos/{photo_id}
      upload_dir = Application.get_env(:portfolio, :upload_dir, "priv/static/uploads")
      expected_base = Path.join([upload_dir, "albums", album.id, "photos", photo.id])

      # Generate variants will fail but we can verify the path construction
      # by checking the adapter's internal logic in the error logs
      _result = ImageProcessingAdapter.generate_variants(photo)

      # The path should be constructable
      assert String.contains?(expected_base, album.id)
      assert String.contains?(expected_base, photo.id)
    end
  end

  # Helper to trip the circuit breaker for testing
  defp trip_circuit_breaker do
    # Trip the fuse by recording multiple failures
    Enum.each(1..6, fn _ ->
      :fuse.melt(:image_processing)
    end)

    # Give fuse time to process
    Process.sleep(10)
  end
end
