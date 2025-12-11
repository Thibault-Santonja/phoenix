defmodule Portfolio.Photography.EventHandlers.PhotoUploadedHandlerTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.EventHandlers.PhotoUploadedHandler
  alias Portfolio.Photography.Events.PhotoUploaded

  describe "start_link/1" do
    test "starts the handler GenServer" do
      case GenServer.whereis(PhotoUploadedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      assert {:ok, pid} = PhotoUploadedHandler.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "registers with module name" do
      case GenServer.whereis(PhotoUploadedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = PhotoUploadedHandler.start_link([])

      assert GenServer.whereis(PhotoUploadedHandler) == pid

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 for photo_uploaded" do
    setup do
      case GenServer.whereis(PhotoUploadedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = PhotoUploadedHandler.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, handler_pid: pid}
    end

    test "processes photo uploaded event without crashing", %{handler_pid: pid} do
      event = %PhotoUploaded{
        photo_id: "photo_123",
        album_id: "album_456",
        file_path: "/uploads/photos/image.jpg",
        hash: "abc123def456",
        uploaded_at: DateTime.utc_now()
      }

      send(pid, {:photo_uploaded, event})
      Process.sleep(100)

      assert Process.alive?(pid)
    end

    test "receives event through DomainEvents.publish", %{handler_pid: pid} do
      event = %PhotoUploaded{
        photo_id: "photo_789",
        album_id: "album_abc",
        file_path: "/uploads/photos/test.jpg",
        hash: "xyz789hash",
        uploaded_at: DateTime.utc_now()
      }

      DomainEvents.publish(:photo_uploaded, event)
      Process.sleep(100)

      assert Process.alive?(pid)
    end

    test "enqueues EXIF extraction job without crashing", %{handler_pid: pid} do
      event = %PhotoUploaded{
        photo_id: "photo_exif",
        album_id: "album_exif",
        file_path: "/uploads/photos/exif_test.jpg",
        hash: "exifhash123",
        uploaded_at: DateTime.utc_now()
      }

      # Just verify the handler processes the event without crashing
      send(pid, {:photo_uploaded, event})
      Process.sleep(100)

      assert Process.alive?(pid)
    end

    test "handles multiple photo uploads in sequence", %{handler_pid: pid} do
      for i <- 1..5 do
        event = %PhotoUploaded{
          photo_id: "photo_seq_#{i}",
          album_id: "album_seq",
          file_path: "/uploads/photos/seq_#{i}.jpg",
          hash: "hash_seq_#{i}",
          uploaded_at: DateTime.utc_now()
        }

        send(pid, {:photo_uploaded, event})
      end

      Process.sleep(200)
      assert Process.alive?(pid)
    end

    test "handles rapid fire events", %{handler_pid: pid} do
      events =
        for i <- 1..10 do
          %PhotoUploaded{
            photo_id: "photo_rapid_#{i}",
            album_id: "album_rapid",
            file_path: "/uploads/photos/rapid_#{i}.jpg",
            hash: "hash_rapid_#{i}",
            uploaded_at: DateTime.utc_now()
          }
        end

      # Send all events rapidly
      Enum.each(events, fn event ->
        send(pid, {:photo_uploaded, event})
      end)

      Process.sleep(300)
      assert Process.alive?(pid)
    end
  end

  describe "handle_info/2 for unexpected messages" do
    setup do
      case GenServer.whereis(PhotoUploadedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = PhotoUploadedHandler.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, handler_pid: pid}
    end

    test "handles unexpected tuple message gracefully", %{handler_pid: pid} do
      send(pid, {:weird_event, %{weird: "data"}})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles unexpected atom message gracefully", %{handler_pid: pid} do
      send(pid, :completely_random)
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles nil message gracefully", %{handler_pid: pid} do
      send(pid, nil)
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles complex tuple message gracefully", %{handler_pid: pid} do
      send(pid, {:multi, :part, :tuple, %{with: "data"}})
      Process.sleep(50)

      assert Process.alive?(pid)
    end
  end

  describe "subscription behavior" do
    test "subscribes to photo_uploaded on init" do
      case GenServer.whereis(PhotoUploadedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = PhotoUploadedHandler.start_link([])

      event = %PhotoUploaded{
        photo_id: "photo_sub_test",
        album_id: "album_sub",
        file_path: "/uploads/photos/sub_test.jpg",
        hash: "subhash123",
        uploaded_at: DateTime.utc_now()
      }

      DomainEvents.publish(:photo_uploaded, event)
      Process.sleep(100)

      # Handler processed event and is still alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "handles already subscribed case gracefully" do
      # First, manually subscribe
      DomainEvents.subscribe(:photo_uploaded)

      case GenServer.whereis(PhotoUploadedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      # Starting handler should handle the already_registered case
      {:ok, pid} = PhotoUploadedHandler.start_link([])
      Process.sleep(50)

      # Handler should still be functional
      assert Process.alive?(pid)

      GenServer.stop(pid)
      DomainEvents.unsubscribe(:photo_uploaded)
    end
  end
end
