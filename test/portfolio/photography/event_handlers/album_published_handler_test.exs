defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandlerTest do
  use ExUnit.Case, async: false

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.EventHandlers.AlbumPublishedHandler
  alias Portfolio.Photography.Events.AlbumPublished

  describe "start_link/1" do
    test "starts the handler GenServer" do
      case GenServer.whereis(AlbumPublishedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      assert {:ok, pid} = AlbumPublishedHandler.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end

    test "registers with module name" do
      case GenServer.whereis(AlbumPublishedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = AlbumPublishedHandler.start_link([])

      assert GenServer.whereis(AlbumPublishedHandler) == pid

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 for album_published" do
    setup do
      case GenServer.whereis(AlbumPublishedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = AlbumPublishedHandler.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, handler_pid: pid}
    end

    test "processes album published event without crashing", %{handler_pid: pid} do
      event = %AlbumPublished{
        album_id: "album_123",
        title: "Wedding Photos",
        slug: "wedding-photos",
        published_at: DateTime.utc_now(),
        user_id: "user_456"
      }

      send(pid, {:album_published, event})
      Process.sleep(150)

      assert Process.alive?(pid)
    end

    test "receives event through DomainEvents.publish", %{handler_pid: pid} do
      event = %AlbumPublished{
        album_id: "album_789",
        title: "Nature Gallery",
        slug: "nature-gallery",
        published_at: DateTime.utc_now(),
        user_id: "user_abc"
      }

      DomainEvents.publish(:album_published, event)
      Process.sleep(150)

      assert Process.alive?(pid)
    end

    test "handles CDN cache invalidation without crashing", %{handler_pid: pid} do
      event = %AlbumPublished{
        album_id: "album_cdn",
        title: "CDN Test",
        slug: "cdn-test",
        published_at: DateTime.utc_now(),
        user_id: "user_cdn"
      }

      # The CDN module is configurable; in test, it uses NoOp
      send(pid, {:album_published, event})
      Process.sleep(200)

      assert Process.alive?(pid)
    end

    test "handles cache clearing without crashing", %{handler_pid: pid} do
      event = %AlbumPublished{
        album_id: "album_cache",
        title: "Cache Test",
        slug: "cache-test",
        published_at: DateTime.utc_now(),
        user_id: "user_cache"
      }

      # Cache operations may fail if Cachex isn't running, but handler shouldn't crash
      send(pid, {:album_published, event})
      Process.sleep(150)

      assert Process.alive?(pid)
    end

    test "handles multiple album published events in sequence", %{handler_pid: pid} do
      for i <- 1..5 do
        event = %AlbumPublished{
          album_id: "album_seq_#{i}",
          title: "Album #{i}",
          slug: "album-#{i}",
          published_at: DateTime.utc_now(),
          user_id: "user_seq"
        }

        send(pid, {:album_published, event})
      end

      Process.sleep(300)
      assert Process.alive?(pid)
    end
  end

  describe "handle_info/2 for unexpected messages" do
    setup do
      case GenServer.whereis(AlbumPublishedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = AlbumPublishedHandler.start_link([])
      on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
      {:ok, handler_pid: pid}
    end

    test "handles unexpected tuple message gracefully", %{handler_pid: pid} do
      send(pid, {:unknown_event, %{data: "test"}})
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles unexpected atom message gracefully", %{handler_pid: pid} do
      send(pid, :something_random)
      Process.sleep(50)

      assert Process.alive?(pid)
    end

    test "handles nil message gracefully", %{handler_pid: pid} do
      send(pid, nil)
      Process.sleep(50)

      assert Process.alive?(pid)
    end
  end

  describe "subscription behavior" do
    test "subscribes to album_published on init" do
      case GenServer.whereis(AlbumPublishedHandler) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      {:ok, pid} = AlbumPublishedHandler.start_link([])

      event = %AlbumPublished{
        album_id: "album_sub_test",
        title: "Subscription Test",
        slug: "sub-test",
        published_at: DateTime.utc_now(),
        user_id: "user_sub"
      }

      DomainEvents.publish(:album_published, event)
      Process.sleep(150)

      # Handler processed event and is still alive
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end
end
