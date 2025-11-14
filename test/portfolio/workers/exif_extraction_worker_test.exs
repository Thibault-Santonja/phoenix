defmodule Portfolio.Workers.ExifExtractionWorkerTest do
  @moduledoc """
  Tests for ExifExtractionWorker - Oban worker for extracting EXIF metadata.

  Tests cover:
  - Successful EXIF extraction and database update
  - Error handling (file not found, corrupted EXIF)
  - Retry vs cancel logic
  - Idempotency (multiple runs with same photo_id)
  """
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.Photography
  alias Portfolio.Workers.ExifExtractionWorker

  describe "perform/1" do
    @tag :skip
    test "extracts EXIF data and updates photo" do
      # Create photo with test image file that has EXIF
      album = create_album()
      photo = create_photo(album: album, file_path: "/test/photo_with_exif.jpg")

      # Perform job
      assert :ok = perform_job(ExifExtractionWorker, %{photo_id: photo.id})

      # Verify photo was updated with EXIF data
      {:ok, updated_photo} = Photography.get_photo(photo.id)

      assert updated_photo.captured_at != nil
      assert updated_photo.camera != nil
      assert updated_photo.exif_data != %{}
    end

    test "cancels job when photo not found" do
      # Non-existent photo ID
      assert {:cancel, "Photo not found"} =
               perform_job(ExifExtractionWorker, %{photo_id: Ecto.UUID.generate()})
    end

    @tag :skip
    test "cancels job when file not found" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/nonexistent/file.jpg")

      assert {:cancel, "File not found"} =
               perform_job(ExifExtractionWorker, %{photo_id: photo.id})
    end

    @tag :skip
    test "retries on transient errors" do
      # Test that network/IO errors trigger retry instead of cancel
      album = create_album()
      photo = create_photo(album: album, file_path: "/test/temporary_unavailable.jpg")

      # Should return error (not cancel) to trigger retry
      assert {:error, _reason} = perform_job(ExifExtractionWorker, %{photo_id: photo.id})
    end

    @tag :skip
    test "is idempotent - multiple runs with same photo_id safe" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/test/photo_with_exif.jpg")

      # Run twice
      assert :ok = perform_job(ExifExtractionWorker, %{photo_id: photo.id})
      assert :ok = perform_job(ExifExtractionWorker, %{photo_id: photo.id})

      # Should still have valid data
      {:ok, updated_photo} = Photography.get_photo(photo.id)
      assert updated_photo.exif_data != %{}
    end

    @tag :skip
    test "extracts captured_at from EXIF DateTimeOriginal" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/test/photo_dated_2024.jpg")

      assert :ok = perform_job(ExifExtractionWorker, %{photo_id: photo.id})

      {:ok, updated_photo} = Photography.get_photo(photo.id)
      assert updated_photo.captured_at != nil
      assert updated_photo.captured_at.year == 2024
    end

    @tag :skip
    test "extracts camera equipment data" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/test/photo_canon.jpg")

      assert :ok = perform_job(ExifExtractionWorker, %{photo_id: photo.id})

      {:ok, updated_photo} = Photography.get_photo(photo.id)
      assert updated_photo.camera =~ "Canon"
      assert updated_photo.iso != nil
      assert updated_photo.aperture != nil
    end

    @tag :skip
    test "extracts GPS coordinates but does not expose publicly" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/test/photo_with_gps.jpg")

      assert :ok = perform_job(ExifExtractionWorker, %{photo_id: photo.id})

      {:ok, updated_photo} = Photography.get_photo(photo.id)
      assert updated_photo.gps_latitude != nil
      assert updated_photo.gps_longitude != nil

      # GPS should be stored in DB but stripped from public files (tested elsewhere)
    end

    @tag :skip
    test "handles photos without EXIF gracefully" do
      album = create_album()
      photo = create_photo(album: album, file_path: "/test/photo_no_exif.jpg")

      # Should succeed but not crash
      assert :ok = perform_job(ExifExtractionWorker, %{photo_id: photo.id})

      {:ok, updated_photo} = Photography.get_photo(photo.id)
      # May have empty or minimal exif_data, that's OK
      assert is_map(updated_photo.exif_data)
    end
  end

  describe "worker configuration" do
    test "uses correct queue" do
      changeset = ExifExtractionWorker.new(%{photo_id: "123"})
      assert changeset.changes.queue == "exif_extraction"
    end

    test "has reasonable max_attempts" do
      # EXIF extraction should retry a few times (transient I/O errors)
      # but not too many (permanent errors like missing file)
      changeset = ExifExtractionWorker.new(%{photo_id: "123"})
      assert changeset.changes.max_attempts == 3
    end

    test "has lower priority than image processing" do
      # EXIF extraction is less critical than generating image variants
      # Priority: 0=high, 3=low
      changeset = ExifExtractionWorker.new(%{photo_id: "123"})
      assert changeset.changes.priority >= 1
    end
  end
end
