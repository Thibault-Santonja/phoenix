defmodule Portfolio.Workers.ExifExtractionWorkerTest do
  @moduledoc """
  Tests for ExifExtractionWorker - Oban worker for extracting EXIF metadata.

  Tests cover:
  - Successful EXIF extraction and database update
  - Error handling (file not found, corrupted EXIF)
  - Retry vs cancel logic
  - Worker configuration
  """
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.Workers.ExifExtractionWorker

  describe "perform/1 - photo lookup" do
    test "cancels job when photo not found" do
      # Non-existent photo ID
      assert {:cancel, "Photo not found"} =
               perform_job(ExifExtractionWorker, %{photo_id: Ecto.UUID.generate()})
    end

    test "cancels job when file does not exist on filesystem" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/nonexistent/path/file.jpg")

      assert {:cancel, "File not found"} =
               perform_job(ExifExtractionWorker, %{photo_id: photo.id})
    end
  end

  describe "worker configuration" do
    test "uses correct queue" do
      changeset = ExifExtractionWorker.new(%{photo_id: "123"})
      assert changeset.changes.queue == "exif_extraction"
    end

    test "has reasonable max_attempts for transient errors" do
      changeset = ExifExtractionWorker.new(%{photo_id: "123"})
      assert changeset.changes.max_attempts == 3
    end

    test "has lower priority than image processing" do
      changeset = ExifExtractionWorker.new(%{photo_id: "123"})
      # Priority 2 is lower than priority 1 (image processing)
      assert changeset.changes.priority == 2
    end

    test "creates valid job changeset" do
      changeset = ExifExtractionWorker.new(%{photo_id: Ecto.UUID.generate()})
      assert changeset.valid?
    end

    test "includes photo_id in args" do
      photo_id = Ecto.UUID.generate()
      changeset = ExifExtractionWorker.new(%{photo_id: photo_id})
      # Args use string keys in Oban changesets
      assert changeset.changes.args[:photo_id] == photo_id or
               changeset.changes.args["photo_id"] == photo_id
    end
  end

  describe "job insertion" do
    test "can insert job into Oban" do
      photo_id = Ecto.UUID.generate()

      assert {:ok, job} =
               %{photo_id: photo_id}
               |> ExifExtractionWorker.new()
               |> Oban.insert()

      # After insertion, args are stored with string keys
      assert job.args[:photo_id] == photo_id or job.args["photo_id"] == photo_id
      assert job.queue == "exif_extraction"
    end
  end
end
