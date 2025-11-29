defmodule Portfolio.Services.Photography.AlbumDeletionServiceTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Photography
  alias Portfolio.Services.Photography.AlbumDeletionService

  describe "execute/2" do
    setup do
      # Create an album with photos for testing
      {:ok, album} =
        Photography.create_album(%{
          title: "Test Album for Deletion",
          type: :wedding,
          date_prise_vue: ~D[2024-01-15]
        })

      {:ok, album: album}
    end

    test "deletes album successfully", %{album: album} do
      result = AlbumDeletionService.execute(album)

      assert {:ok, %{album: deleted_album, photos: photos, files: :ok}} = result
      assert deleted_album.id == album.id
      assert is_list(photos)

      # Verify album is deleted from database
      assert {:error, :not_found} = Photography.get_album(album.id)
    end

    test "returns deleted photos list", %{album: album} do
      # Add a photo to the album
      {:ok, _photo} =
        Photography.create_photo(%{
          album_id: album.id,
          file_path: "/test/photo1.jpg",
          original_filename: "photo1.jpg",
          display_order: 0
        })

      result = AlbumDeletionService.execute(album)

      assert {:ok, %{photos: photos}} = result
      assert length(photos) == 1
    end

    test "handles album with no photos", %{album: album} do
      result = AlbumDeletionService.execute(album)

      assert {:ok, %{photos: []}} = result
    end

    test "emits telemetry event on execution" do
      {:ok, album} =
        Photography.create_album(%{
          title: "Telemetry Test Album",
          type: :wedding,
          date_prise_vue: ~D[2024-02-01]
        })

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :services, :album_deletion, :executed]
        ])

      AlbumDeletionService.execute(album)

      assert_received {[:portfolio, :services, :album_deletion, :executed], ^ref, _measurements,
                       %{album_id: _}}
    end
  end
end
