defmodule Portfolio.Workers.ExifExtractionWorkerTest do
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo

  alias Portfolio.Workers.ExifExtractionWorker

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "new/1" do
    test "creates a valid changeset with photo_id" do
      changeset = ExifExtractionWorker.new(%{photo_id: 123})
      assert %Ecto.Changeset{valid?: true} = changeset
    end

    test "job uses exif_extraction queue" do
      changeset = ExifExtractionWorker.new(%{photo_id: 123})
      assert changeset.changes[:queue] == "exif_extraction"
    end

    test "job has correct priority" do
      changeset = ExifExtractionWorker.new(%{photo_id: 123})
      assert changeset.changes[:priority] == 2
    end

    test "job has max_attempts of 3" do
      changeset = ExifExtractionWorker.new(%{photo_id: 123})
      assert changeset.changes[:max_attempts] == 3
    end
  end

  describe "perform/1 with missing photo" do
    test "cancels job when photo not found" do
      # Use a valid UUID format that doesn't exist in DB
      non_existent_id = Ecto.UUID.generate()
      job = %Oban.Job{args: %{"photo_id" => non_existent_id}, attempt: 1}

      assert {:cancel, "Photo not found"} = ExifExtractionWorker.perform(job)
    end
  end

  describe "perform/1 with existing photo" do
    setup do
      album = create_album()
      photo = create_photo(album: album)
      {:ok, photo: photo, album: album}
    end

    test "cancels job when file does not exist", %{photo: photo} do
      job = %Oban.Job{args: %{"photo_id" => photo.id}, attempt: 1}

      # The photo fixture creates a photo with a non-existent file path
      result = ExifExtractionWorker.perform(job)

      # Should cancel because file doesn't exist
      assert {:cancel, "File not found"} = result
    end
  end

  describe "job enqueueing" do
    test "can enqueue job successfully" do
      assert {:ok, %Oban.Job{}} =
               %{photo_id: 123}
               |> ExifExtractionWorker.new()
               |> Oban.insert()
    end

    test "job is inserted with correct args" do
      {:ok, job} =
        %{photo_id: 456}
        |> ExifExtractionWorker.new()
        |> Oban.insert()

      # Args are stored with atom keys
      assert job.args == %{photo_id: 456}
    end
  end

  describe "worker configuration" do
    test "max_attempts is 3" do
      config = ExifExtractionWorker.__opts__()
      assert config[:max_attempts] == 3
    end

    test "queue is exif_extraction" do
      config = ExifExtractionWorker.__opts__()
      assert config[:queue] == :exif_extraction
    end

    test "priority is 2" do
      config = ExifExtractionWorker.__opts__()
      assert config[:priority] == 2
    end
  end
end
