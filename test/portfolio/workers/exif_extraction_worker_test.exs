defmodule Portfolio.Workers.ExifExtractionWorkerTest do
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.Workers.ExifExtractionWorker

  describe "perform/1" do
    test "returns cancel when photo not found" do
      assert {:cancel, "Photo not found"} =
               perform_job(ExifExtractionWorker, %{"photo_id" => Ecto.UUID.generate()})
    end

    test "returns cancel when file not found" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/nonexistent/path.jpg")

      assert {:cancel, "File not found"} =
               perform_job(ExifExtractionWorker, %{"photo_id" => photo.id})
    end

    test "handles photo with existing exif_data" do
      album = create_album()
      photo = create_photo(album: album, exif_data: %{"existing" => "data"})

      # File doesn't exist, so will return cancel
      result = perform_job(ExifExtractionWorker, %{"photo_id" => photo.id})
      assert {:cancel, "File not found"} = result
    end
  end

  describe "job creation" do
    test "can create a new job" do
      job_changeset = ExifExtractionWorker.new(%{photo_id: Ecto.UUID.generate()})
      assert %Ecto.Changeset{} = job_changeset
    end

    test "creates job with correct args" do
      photo_id = Ecto.UUID.generate()
      job_changeset = ExifExtractionWorker.new(%{photo_id: photo_id})

      # Apply the changeset to get the job struct
      job = Ecto.Changeset.apply_changes(job_changeset)
      # Args are stored with atom keys before DB insertion
      assert job.args[:photo_id] == photo_id or job.args["photo_id"] == photo_id
    end

    test "job is configured for exif_extraction queue" do
      photo_id = Ecto.UUID.generate()
      job_changeset = ExifExtractionWorker.new(%{photo_id: photo_id})
      job = Ecto.Changeset.apply_changes(job_changeset)

      assert job.queue == "exif_extraction"
    end

    test "job has priority 2" do
      photo_id = Ecto.UUID.generate()
      job_changeset = ExifExtractionWorker.new(%{photo_id: photo_id})
      job = Ecto.Changeset.apply_changes(job_changeset)

      assert job.priority == 2
    end

    test "job has max_attempts of 3" do
      photo_id = Ecto.UUID.generate()
      job_changeset = ExifExtractionWorker.new(%{photo_id: photo_id})
      job = Ecto.Changeset.apply_changes(job_changeset)

      assert job.max_attempts == 3
    end
  end
end
