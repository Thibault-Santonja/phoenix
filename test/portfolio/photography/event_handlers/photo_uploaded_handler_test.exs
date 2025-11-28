defmodule Portfolio.Photography.EventHandlers.PhotoUploadedHandlerTest do
  use Portfolio.DataCase, async: false
  use Oban.Testing, repo: Portfolio.Repo

  alias Portfolio.Photography.EventHandlers.PhotoUploadedHandler
  alias Portfolio.Photography.Events.PhotoUploaded
  alias Portfolio.Workers.ExifExtractionWorker

  describe "start_link/1" do
    test "starts the GenServer successfully" do
      # Stop existing handler if running
      if pid = Process.whereis(PhotoUploadedHandler) do
        GenServer.stop(pid)
      end

      assert {:ok, pid} = PhotoUploadedHandler.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "init/1" do
    test "initializes with empty state" do
      assert {:ok, %{}} = PhotoUploadedHandler.init([])
    end

    test "handles already_registered error gracefully" do
      # First init subscribes
      {:ok, %{}} = PhotoUploadedHandler.init([])
      # Second init should handle already_registered
      {:ok, %{}} = PhotoUploadedHandler.init([])
    end
  end

  describe "handle_info/2 - photo_uploaded" do
    test "handles PhotoUploaded event and enqueues EXIF extraction job" do
      photo_id = Ecto.UUID.generate()

      event = %PhotoUploaded{
        photo_id: photo_id,
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/albums/test/photos/image.jpg",
        hash: "abc123hash",
        uploaded_at: DateTime.utc_now()
      }

      state = %{}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event}, state)

      # Verify EXIF extraction job was enqueued
      assert_enqueued(worker: ExifExtractionWorker, args: %{photo_id: photo_id})
    end

    test "preserves state after handling event" do
      event = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/test.jpg",
        hash: "xyz789",
        uploaded_at: DateTime.utc_now()
      }

      initial_state = %{counter: 42}

      assert {:noreply, ^initial_state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event}, initial_state)
    end
  end

  describe "handle_info/2 - unexpected messages" do
    test "handles unexpected messages gracefully" do
      state = %{}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:unknown_event, %{}}, state)
    end

    test "handles random messages without crashing" do
      state = %{data: "test"}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info(:random_atom, state)
    end
  end
end
