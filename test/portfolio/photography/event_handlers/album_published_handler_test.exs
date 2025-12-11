defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandlerTest do
  @moduledoc """
  Tests for AlbumPublishedHandler GenServer.
  """
  use Portfolio.DataCase, async: false

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

      GenServer.stop(pid)
    end
  end

  describe "init/1" do
    test "initializes with empty state" do
      # Stop existing handler if running
      if pid = Process.whereis(AlbumPublishedHandler) do
        GenServer.stop(pid)
      end

      {:ok, pid} = AlbumPublishedHandler.start_link([])
      assert Process.alive?(pid)

      GenServer.stop(pid)
    end
  end

  describe "handle_info/2 - album_published event" do
    test "handles AlbumPublished event successfully" do
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

    test "preserves state after handling event" do
      event = %AlbumPublished{
        album_id: Ecto.UUID.generate(),
        title: "My Album",
        slug: "my-album",
        published_at: DateTime.utc_now(),
        user_id: Ecto.UUID.generate()
      }

      initial_state = %{counter: 10}

      assert {:noreply, ^initial_state} =
               AlbumPublishedHandler.handle_info({:album_published, event}, initial_state)
    end

    test "handles event with special characters in title" do
      event = %AlbumPublished{
        album_id: Ecto.UUID.generate(),
        title: "Album été 2024 - été/hiver",
        slug: "album-ete-2024",
        published_at: DateTime.utc_now(),
        user_id: Ecto.UUID.generate()
      }

      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info({:album_published, event}, state)
    end
  end

  describe "handle_info/2 - unexpected messages" do
    test "handles unexpected messages gracefully" do
      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info({:unknown_event, %{}}, state)
    end

    test "handles random atom messages" do
      state = %{data: "test"}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info(:random_message, state)
    end

    test "handles nil message" do
      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info(nil, state)
    end

    test "handles tuple with wrong event type" do
      state = %{}

      assert {:noreply, ^state} =
               AlbumPublishedHandler.handle_info({:album_deleted, %{}}, state)
    end
  end

  describe "cache invalidation" do
    test "clears cache after album publication" do
      # Ensure cache has some data
      Cachex.put(:portfolio_cache, {:published_albums_by_year, []}, "cached_data")

      event = %AlbumPublished{
        album_id: Ecto.UUID.generate(),
        title: "Cache Test Album",
        slug: "cache-test-album",
        published_at: DateTime.utc_now(),
        user_id: Ecto.UUID.generate()
      }

      state = %{}
      {:noreply, _state} = AlbumPublishedHandler.handle_info({:album_published, event}, state)

      # Give async task time to complete
      Process.sleep(50)

      # Cache should be cleared
      {:ok, result} = Cachex.get(:portfolio_cache, {:published_albums_by_year, []})
      assert result == nil
    end
  end

  describe "multiple event processing" do
    test "handles multiple album publications sequentially" do
      state = %{}

      events =
        for i <- 1..3 do
          %AlbumPublished{
            album_id: Ecto.UUID.generate(),
            title: "Album #{i}",
            slug: "album-#{i}",
            published_at: DateTime.utc_now(),
            user_id: Ecto.UUID.generate()
          }
        end

      final_state =
        Enum.reduce(events, state, fn event, acc_state ->
          {:noreply, new_state} =
            AlbumPublishedHandler.handle_info({:album_published, event}, acc_state)

          new_state
        end)

      assert final_state == state
    end
  end
end
