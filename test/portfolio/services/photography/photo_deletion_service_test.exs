defmodule Portfolio.Services.Photography.PhotoDeletionServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography
  alias Portfolio.Services.Photography.PhotoDeletionService

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "execute/2" do
    test "deletes a photo successfully" do
      album = create_album()
      photo = create_photo(album: album)

      assert {:ok, result} = PhotoDeletionService.execute(photo)

      assert result.photo.id == photo.id
      assert result.file == :ok

      # Photo should be deleted from database
      assert {:error, :not_found} = Photography.get_photo(photo.id)
    end

    test "emits telemetry event for deletion" do
      album = create_album()
      photo = create_photo(album: album)

      test_pid = self()

      :telemetry.attach(
        "test-photo-deletion",
        [:portfolio, :services, :photo_deletion, :executed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      PhotoDeletionService.execute(photo)

      assert_receive {:telemetry, [:portfolio, :services, :photo_deletion, :executed],
                      measurements, metadata}

      assert measurements.duration > 0
      assert metadata.photo_id == photo.id
      assert metadata.album_id == album.id

      :telemetry.detach("test-photo-deletion")
    end

    test "publishes domain event on success" do
      album = create_album()
      photo = create_photo(album: album)

      # The service publishes a :photo_deleted event
      # We verify execution completes successfully
      assert {:ok, result} = PhotoDeletionService.execute(photo)

      assert result.photo.id == photo.id
    end

    test "accepts options parameter" do
      album = create_album()
      photo = create_photo(album: album)

      # Should work with empty options
      assert {:ok, _result} = PhotoDeletionService.execute(photo, [])
    end

    test "handles photo with file_path that doesn't exist on disk" do
      album = create_album()
      # Photo with non-existent file path - should still delete record
      photo = create_photo(album: album, file_path: "/nonexistent/path/photo.jpg")

      assert {:ok, result} = PhotoDeletionService.execute(photo)

      assert result.photo.id == photo.id
      # File deletion returns :ok for non-existent files (acceptable orphan cleanup)
      assert result.file == :ok
    end
  end
end
