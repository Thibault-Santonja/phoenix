defmodule Portfolio.Photography.EventHandlers.PhotoUploadedHandlerTest do
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo

  alias Portfolio.Photography.EventHandlers.PhotoUploadedHandler
  alias Portfolio.Photography.Events.PhotoUploaded

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "handle_info/2 with :photo_uploaded event" do
    test "processes photo uploaded event and logs" do
      album = create_album()
      photo = create_photo(album: album)

      event = %PhotoUploaded{
        photo_id: photo.id,
        album_id: album.id,
        file_path: photo.file_path,
        hash: photo.hash,
        uploaded_at: DateTime.utc_now()
      }

      # Send event to handler
      assert {:noreply, %{}} = PhotoUploadedHandler.handle_info({:photo_uploaded, event}, %{})
    end

    test "handles missing photo gracefully" do
      album = create_album()

      event = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: album.id,
        file_path: "/nonexistent.jpg",
        hash: "abc123",
        uploaded_at: DateTime.utc_now()
      }

      # Should not crash
      assert {:noreply, %{}} = PhotoUploadedHandler.handle_info({:photo_uploaded, event}, %{})
    end
  end

  describe "handle_info/2 with unexpected messages" do
    test "handles unexpected messages gracefully" do
      assert {:noreply, %{}} =
               PhotoUploadedHandler.handle_info({:unexpected, :message}, %{})
    end
  end
end
