defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandlerTest do
  use ExUnit.Case, async: true

  alias Portfolio.Photography.EventHandlers.AlbumPublishedHandler
  alias Portfolio.Photography.Events.AlbumPublished

  describe "start_link/1" do
    test "starts the GenServer successfully" do
      # Stop existing handler if running
      if pid = Process.whereis(AlbumPublishedHandler) do
        GenServer.stop(pid)
      end

      assert {:ok, pid} = AlbumPublishedHandler.start_link([])
      assert is_pid(pid)
      assert Process.alive?(pid)

      # Clean up
      GenServer.stop(pid)
    end
  end

  describe "init/1" do
    test "initializes with empty state" do
      assert {:ok, %{}} = AlbumPublishedHandler.init([])
    end
  end

  describe "handle_info/2 - album_published" do
    test "handles AlbumPublished event" do
      event = %AlbumPublished{
        album_id: Ecto.UUID.generate(),
        title: "Test Album",
        slug: "test-album",
        published_at: DateTime.utc_now(),
        user_id: Ecto.UUID.generate()
      }

      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info({:album_published, event}, state)
    end

    test "handles event without user_id" do
      event = %AlbumPublished{
        album_id: Ecto.UUID.generate(),
        title: "System Published Album",
        slug: "system-album",
        published_at: DateTime.utc_now(),
        user_id: nil
      }

      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info({:album_published, event}, state)
    end

    test "preserves state after handling event" do
      event = %AlbumPublished{
        album_id: Ecto.UUID.generate(),
        title: "Another Album",
        slug: "another-album",
        published_at: DateTime.utc_now(),
        user_id: nil
      }

      initial_state = %{some_data: "value"}

      assert {:noreply, ^initial_state} =
               AlbumPublishedHandler.handle_info({:album_published, event}, initial_state)
    end
  end

  describe "handle_info/2 - unexpected messages" do
    test "handles unexpected messages gracefully" do
      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info({:unknown_event, %{}}, state)
    end

    test "handles random messages without crashing" do
      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info(:random_message, state)
    end

    test "handles nil message" do
      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info(nil, state)
    end
  end
end
