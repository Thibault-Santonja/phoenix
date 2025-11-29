defmodule Portfolio.Services.Photography.PhotoDeletionServiceTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Photography
  alias Portfolio.Services.Photography.PhotoDeletionService

  describe "execute/2" do
    setup do
      {:ok, album} =
        Photography.create_album(%{
          title: "Test Album",
          type: :wedding,
          date_prise_vue: ~D[2024-01-15]
        })

      {:ok, photo} =
        Photography.create_photo(%{
          album_id: album.id,
          file_path: "/test/photos/test_photo.jpg",
          original_filename: "test_photo.jpg",
          display_order: 0
        })

      {:ok, album: album, photo: photo}
    end

    test "deletes photo successfully", %{photo: photo} do
      result = PhotoDeletionService.execute(photo)

      assert {:ok, %{photo: deleted_photo, file: :ok}} = result
      assert deleted_photo.id == photo.id
    end

    test "removes photo from database", %{photo: photo} do
      {:ok, _} = PhotoDeletionService.execute(photo)

      # Verify photo is deleted from database
      assert {:error, :not_found} = Photography.get_photo(photo.id)
    end

    test "handles missing file gracefully", %{album: album} do
      # Create photo with non-existent file path
      {:ok, photo} =
        Photography.create_photo(%{
          album_id: album.id,
          file_path: "/nonexistent/path/photo.jpg",
          original_filename: "ghost.jpg",
          display_order: 1
        })

      # Should succeed even if file doesn't exist
      result = PhotoDeletionService.execute(photo)

      assert {:ok, %{photo: _, file: :ok}} = result
    end

    test "emits telemetry event on execution", %{photo: photo} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :services, :photo_deletion, :executed]
        ])

      PhotoDeletionService.execute(photo)

      assert_received {[:portfolio, :services, :photo_deletion, :executed], ^ref, _measurements,
                       %{photo_id: _, album_id: _}}
    end

    test "deletes photo and updates album photo count", %{album: album, photo: photo} do
      # Verify initial count
      initial_count = Photography.count_photos_in_album(album.id)
      assert initial_count == 1

      {:ok, _} = PhotoDeletionService.execute(photo)

      # Verify count after deletion
      final_count = Photography.count_photos_in_album(album.id)
      assert final_count == 0
    end
  end
end
