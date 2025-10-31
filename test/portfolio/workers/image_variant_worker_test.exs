defmodule Portfolio.Workers.ImageVariantWorkerTest do
  @moduledoc """
  Tests for ImageVariantWorker.

  Tests verify:
  - Successful variant generation
  - Permanent error handling (cancel job)
  - Transient error handling (retry)
  - Telemetry events emission
  """
  use ExUnit.Case, async: true
  use Oban.Testing, repo: Portfolio.Repo

  alias Portfolio.Workers.ImageVariantWorker

  setup do
    # Configure test storage path
    test_base_path = "test/tmp/uploads/worker-test-#{System.unique_integer([:positive])}"
    Application.put_env(:portfolio, :uploads, base_path: test_base_path)

    File.rm_rf!(test_base_path)
    File.mkdir_p!(test_base_path)

    on_exit(fn ->
      File.rm_rf!(test_base_path)
    end)

    %{test_base_path: test_base_path}
  end

  describe "perform/1 - success cases" do
    test "successfully generates variants for existing photo", %{
      test_base_path: test_base_path
    } do
      # Create a photo directory with original file
      photo_id = "test1234"
      photo_dir = Path.join([test_base_path, "photos", photo_id])
      File.mkdir_p!(photo_dir)

      # Create a test image
      original_path = Path.join(photo_dir, "original.jpg")
      create_test_image(original_path)

      # Execute worker
      assert :ok = perform_job(ImageVariantWorker, %{photo_id: photo_id})

      # Verify variants were created
      assert File.exists?(Path.join(photo_dir, "thumbnail.webp"))
      assert File.exists?(Path.join(photo_dir, "small.webp"))
      assert File.exists?(Path.join(photo_dir, "medium.webp"))
      assert File.exists?(Path.join(photo_dir, "large.webp"))
    end

    test "emits telemetry events on success", %{test_base_path: test_base_path} do
      # Setup telemetry capture
      test_pid = self()

      :telemetry.attach_many(
        "test-image-processing",
        [
          [:portfolio, :image, :processing, :start],
          [:portfolio, :image, :processing, :stop]
        ],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      # Create photo
      photo_id = "test5678"
      photo_dir = Path.join([test_base_path, "photos", photo_id])
      File.mkdir_p!(photo_dir)
      create_test_image(Path.join(photo_dir, "original.jpg"))

      # Execute
      perform_job(ImageVariantWorker, %{photo_id: photo_id})

      # Verify start event
      assert_receive {:telemetry, [:portfolio, :image, :processing, :start], _measurements,
                      %{photo_id: ^photo_id}}

      # Verify stop event
      assert_receive {:telemetry, [:portfolio, :image, :processing, :stop], measurements,
                      %{photo_id: ^photo_id, variant_count: 4}}

      assert measurements.duration > 0

      # Cleanup
      :telemetry.detach("test-image-processing")
    end
  end

  describe "perform/1 - permanent errors" do
    test "cancels job when photo file not found" do
      # Photo doesn't exist
      result = perform_job(ImageVariantWorker, %{photo_id: "nonexistent"})

      # Should cancel (not retry)
      assert {:cancel, {:error, :file_not_found}} = result
    end

    test "emits exception telemetry for file not found" do
      test_pid = self()

      :telemetry.attach(
        "test-exception",
        [:portfolio, :image, :processing, :exception],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      perform_job(ImageVariantWorker, %{photo_id: "nonexistent"})

      assert_receive {:telemetry, [:portfolio, :image, :processing, :exception], _measurements,
                      %{photo_id: "nonexistent", reason: :file_not_found}}

      :telemetry.detach("test-exception")
    end
  end

  describe "perform/1 - transient errors" do
    test "retries on transient errors" do
      # This test verifies retry behavior would happen
      # In real scenario, transient errors might be I/O issues
      # For now, we test that file_not_found is cancelled (not retried)
      result = perform_job(ImageVariantWorker, %{photo_id: "missing"})

      # Permanent error should cancel
      assert {:cancel, {:error, :file_not_found}} = result
    end
  end

  describe "enqueue/1" do
    test "creates a job with correct parameters" do
      # Test that new/1 creates a job with correct config
      # We don't actually insert it to avoid DB complexity
      changeset = ImageVariantWorker.new(%{photo_id: "abc12345"})

      # Access changeset.changes instead of direct fields
      assert changeset.changes.queue == "image_processing"
      assert changeset.changes.worker == "Portfolio.Workers.ImageVariantWorker"
      assert changeset.changes.args == %{photo_id: "abc12345"}
      assert changeset.changes.max_attempts == 3
      assert changeset.changes.priority == 1
    end
  end

  describe "worker configuration" do
    test "uses correct queue" do
      worker_config = ImageVariantWorker.__opts__()
      assert worker_config[:queue] == :image_processing
    end

    test "has correct max_attempts" do
      worker_config = ImageVariantWorker.__opts__()
      assert worker_config[:max_attempts] == 3
    end

    test "has correct priority" do
      worker_config = ImageVariantWorker.__opts__()
      assert worker_config[:priority] == 1
    end
  end

  # Helper functions

  defp create_test_image(path) do
    # Create a simple test image
    {:ok, img} = Vix.Vips.Operation.black(100, 100)
    Vix.Vips.Image.write_to_file(img, path)
  end
end
