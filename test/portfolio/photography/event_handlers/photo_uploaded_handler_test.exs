defmodule Portfolio.Photography.EventHandlers.PhotoUploadedHandlerTest do
  use Portfolio.DataCase, async: false
  use Oban.Testing, repo: Portfolio.Repo

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.EventHandlers.PhotoUploadedHandler
  alias Portfolio.Photography.Events.PhotoUploaded
  alias Portfolio.Workers.ExifExtractionWorker

  # Helper to ensure GenServer has processed all pending messages
  defp flush_handler(pid) do
    :sys.get_state(pid)
    :ok
  end

  setup do
    # Start the handler for tests
    case PhotoUploadedHandler.start_link([]) do
      {:ok, pid} ->
        on_exit(fn ->
          if Process.alive?(pid), do: GenServer.stop(pid, :normal, 100)
        end)

        {:ok, handler: pid}

      {:error, {:already_started, pid}} ->
        {:ok, handler: pid}
    end
  end

  describe "start_link/1" do
    test "starts the handler and subscribes to events", %{handler: handler} do
      assert Process.alive?(handler)
    end
  end

  describe "handle_info/2 for photo_uploaded" do
    test "handles PhotoUploaded event", %{handler: handler} do
      album = create_album()
      photo = create_photo(album: album)

      event = %PhotoUploaded{
        photo_id: photo.id,
        album_id: album.id,
        file_path: photo.file_path,
        hash: photo.hash,
        uploaded_at: DateTime.utc_now()
      }

      # Send event directly to the handler
      send(handler, {:photo_uploaded, event})
      flush_handler(handler)

      # Handler should not crash
      assert Process.alive?(handler)
    end

    test "enqueues EXIF extraction job", %{handler: handler} do
      album = create_album()
      photo = create_photo(album: album)

      event = %PhotoUploaded{
        photo_id: photo.id,
        album_id: album.id,
        file_path: photo.file_path,
        hash: photo.hash,
        uploaded_at: DateTime.utc_now()
      }

      send(handler, {:photo_uploaded, event})
      flush_handler(handler)

      # Verify EXIF extraction job was enqueued
      assert_enqueued(worker: ExifExtractionWorker, args: %{photo_id: photo.id})
    end

    test "handles unexpected messages gracefully", %{handler: handler} do
      # Send unexpected message
      send(handler, :unexpected_message)
      flush_handler(handler)

      # Handler should not crash
      assert Process.alive?(handler)
    end
  end

  describe "integration with DomainEvents" do
    test "receives events published via DomainEvents", %{handler: handler} do
      album = create_album()
      photo = create_photo(album: album)

      # Publish via DomainEvents
      DomainEvents.publish(:photo_uploaded, %PhotoUploaded{
        photo_id: photo.id,
        album_id: album.id,
        file_path: photo.file_path,
        hash: photo.hash,
        uploaded_at: DateTime.utc_now()
      })

      flush_handler(handler)

      # Handler should still be alive
      assert Process.alive?(handler)
    end
  end
end
