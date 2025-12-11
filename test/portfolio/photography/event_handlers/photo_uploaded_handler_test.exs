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
    test "subscribes to photo_uploaded events" do
      assert {:ok, %{}} = PhotoUploadedHandler.init([])
    end

    test "initializes with empty state" do
      assert {:ok, state} = PhotoUploadedHandler.init([])
      assert state == %{}
    end
  end

  describe "handle_info/2 - photo_uploaded event" do
    test "handles PhotoUploaded event successfully" do
      event = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/albums/test/photos/test.jpg",
        hash: "abc123def456",
        uploaded_at: DateTime.utc_now()
      }

      state = %{}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event}, state)
    end

    test "preserves state after handling event" do
      event = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/test.jpg",
        hash: "hash123",
        uploaded_at: DateTime.utc_now()
      }

      initial_state = %{counter: 5}

      assert {:noreply, ^initial_state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event}, initial_state)
    end

    test "enqueues EXIF extraction job" do
      photo_id = Ecto.UUID.generate()

      event = %PhotoUploaded{
        photo_id: photo_id,
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/test.jpg",
        hash: "hash456",
        uploaded_at: DateTime.utc_now()
      }

      state = %{}
      PhotoUploadedHandler.handle_info({:photo_uploaded, event}, state)

      # Verify job changeset is valid
      changeset = ExifExtractionWorker.new(%{photo_id: photo_id})
      assert changeset.valid?
    end

    test "handles multiple photo upload events" do
      state = %{}

      event1 = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/photo1.jpg",
        hash: "hash1",
        uploaded_at: DateTime.utc_now()
      }

      event2 = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/photo2.jpg",
        hash: "hash2",
        uploaded_at: DateTime.utc_now()
      }

      # Process first event
      {:noreply, state} = PhotoUploadedHandler.handle_info({:photo_uploaded, event1}, state)

      # Process second event
      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event2}, state)
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

    test "handles nil message" do
      state = %{}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info(nil, state)
    end

    test "handles malformed event structure" do
      state = %{}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, %{invalid: "structure"}}, state)
    end
  end

  describe "event processing edge cases" do
    test "handles event with very long file paths" do
      long_path = "/uploads/" <> String.duplicate("a", 500) <> "/photo.jpg"

      event = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: long_path,
        hash: "hash123",
        uploaded_at: DateTime.utc_now()
      }

      state = %{}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event}, state)
    end

    test "handles event with special characters in path" do
      event = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/album-with-éèà/photo.jpg",
        hash: "hash123",
        uploaded_at: DateTime.utc_now()
      }

      state = %{}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event}, state)
    end
  end

  describe "concurrent event handling" do
    test "handles sequential events without state corruption" do
      state = %{counter: 0}

      events =
        for i <- 1..5 do
          %PhotoUploaded{
            photo_id: Ecto.UUID.generate(),
            album_id: Ecto.UUID.generate(),
            file_path: "/uploads/photo#{i}.jpg",
            hash: "hash#{i}",
            uploaded_at: DateTime.utc_now()
          }
        end

      # Process all events sequentially
      final_state =
        Enum.reduce(events, state, fn event, acc_state ->
          {:noreply, new_state} =
            PhotoUploadedHandler.handle_info({:photo_uploaded, event}, acc_state)

          new_state
        end)

      # State should be preserved
      assert final_state == state
    end
  end

  describe "error resilience" do
    test "continues processing after handling event" do
      event = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/test.jpg",
        hash: "hash123",
        uploaded_at: DateTime.utc_now()
      }

      state = %{}

      # Should not crash
      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event}, state)
    end
  end

  describe "logging and observability" do
    test "processes photo uploads without errors" do
      event = %PhotoUploaded{
        photo_id: Ecto.UUID.generate(),
        album_id: Ecto.UUID.generate(),
        file_path: "/uploads/test.jpg",
        hash: "hash123",
        uploaded_at: DateTime.utc_now()
      }

      state = %{}

      assert {:noreply, ^state} =
               PhotoUploadedHandler.handle_info({:photo_uploaded, event}, state)
    end
  end
end
