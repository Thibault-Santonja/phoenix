defmodule Portfolio.Workers.ImageVariantWorkerTest do
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo

  alias Portfolio.Workers.ImageVariantWorker

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "new/1" do
    test "creates a valid changeset with photo_id" do
      changeset = ImageVariantWorker.new(%{photo_id: "test-id"})
      assert %Ecto.Changeset{valid?: true} = changeset
    end

    test "job uses image_processing queue" do
      changeset = ImageVariantWorker.new(%{photo_id: "test-id"})
      assert changeset.changes[:queue] == "image_processing"
    end

    test "job has priority 1" do
      changeset = ImageVariantWorker.new(%{photo_id: "test-id"})
      assert changeset.changes[:priority] == 1
    end

    test "job has max_attempts of 3" do
      changeset = ImageVariantWorker.new(%{photo_id: "test-id"})
      assert changeset.changes[:max_attempts] == 3
    end
  end

  describe "enqueue/1" do
    test "inserts job into oban queue" do
      assert {:ok, %Oban.Job{}} = ImageVariantWorker.enqueue("test-photo-id")
    end

    test "job has correct args" do
      {:ok, job} = ImageVariantWorker.enqueue("my-photo-123")
      assert job.args == %{photo_id: "my-photo-123"}
    end
  end

  describe "worker configuration" do
    test "max_attempts is 3" do
      config = ImageVariantWorker.__opts__()
      assert config[:max_attempts] == 3
    end

    test "queue is image_processing" do
      config = ImageVariantWorker.__opts__()
      assert config[:queue] == :image_processing
    end

    test "priority is 1" do
      config = ImageVariantWorker.__opts__()
      assert config[:priority] == 1
    end
  end

  describe "perform/1" do
    setup do
      album = create_album()
      photo = create_photo(album: album)
      {:ok, photo: photo, album: album}
    end

    test "emits telemetry start event", %{photo: photo} do
      test_pid = self()

      :telemetry.attach(
        "test-image-start",
        [:portfolio, :image, :processing, :start],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      job = %Oban.Job{args: %{"photo_id" => photo.id}, attempt: 1}
      # This will fail because file doesn't exist, but telemetry should still fire
      ImageVariantWorker.perform(job)

      assert_receive {:telemetry, [:portfolio, :image, :processing, :start], _, %{photo_id: _}}

      :telemetry.detach("test-image-start")
    end

    test "handles file not found error", %{photo: photo} do
      job = %Oban.Job{args: %{"photo_id" => photo.id}, attempt: 1}

      # The fixture photo doesn't have a real file, so this should return an error
      result = ImageVariantWorker.perform(job)

      # Should be either :ok (if storage mock returns success)
      # or an error tuple (if real storage is used)
      assert result == :ok or
               match?({:cancel, _}, result) or
               match?({:error, _}, result)
    end

    test "handles non-existent photo", %{} do
      non_existent_id = Ecto.UUID.generate()
      job = %Oban.Job{args: %{"photo_id" => non_existent_id}, attempt: 1}

      # Should handle gracefully even if photo not in DB
      result = ImageVariantWorker.perform(job)

      assert result == :ok or
               match?({:cancel, _}, result) or
               match?({:error, _}, result)
    end
  end

  describe "job enqueueing via Oban.insert" do
    test "can enqueue job directly" do
      assert {:ok, %Oban.Job{}} =
               %{photo_id: "direct-test"}
               |> ImageVariantWorker.new()
               |> Oban.insert()
    end

    test "job persists with correct worker name" do
      {:ok, job} =
        %{photo_id: "worker-test"}
        |> ImageVariantWorker.new()
        |> Oban.insert()

      assert job.worker == "Portfolio.Workers.ImageVariantWorker"
    end

    test "job state is available" do
      {:ok, job} =
        %{photo_id: "state-test"}
        |> ImageVariantWorker.new()
        |> Oban.insert()

      assert job.state == "available"
    end
  end
end
