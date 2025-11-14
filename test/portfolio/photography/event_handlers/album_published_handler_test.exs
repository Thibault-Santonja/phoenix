defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandlerTest do
  use ExUnit.Case, async: false

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.EventHandlers.AlbumPublishedHandler
  alias Portfolio.Photography.Events.AlbumPublished

  setup do
    # Start the handler if not already running
    # Event handlers are disabled by default in test env to avoid DB ownership issues
    # But these specific tests need the handler running
    case Process.whereis(AlbumPublishedHandler) do
      nil ->
        {:ok, pid} = AlbumPublishedHandler.start_link([])
        on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)
        :ok

      _pid ->
        :ok
    end
  end

  describe "AlbumPublishedHandler" do
    test "handler is started and registered" do
      # Verify handler is running
      assert Process.whereis(AlbumPublishedHandler) != nil
      assert Process.alive?(Process.whereis(AlbumPublishedHandler))
    end

    @tag :skip
    test "handler is supervised and restarts on crash" do
      # This test only makes sense in production where handler is supervised
      # In tests, we start the handler manually in setup
      pid = Process.whereis(AlbumPublishedHandler)
      assert pid != nil

      # Kill the handler
      Process.exit(pid, :kill)

      # Give supervisor time to restart
      Process.sleep(100)

      # Handler should be restarted with different PID
      new_pid = Process.whereis(AlbumPublishedHandler)
      assert new_pid != nil
      assert new_pid != pid
      assert Process.alive?(new_pid)
    end

    test "handler invalidates cache on album published event" do
      # Seed cache with dummy data
      cache_key_without_photos = {:published_albums_by_year, []}
      cache_key_with_photos = {:published_albums_by_year, [:photos]}

      {:ok, true} = Cachex.put(:portfolio_cache, cache_key_without_photos, "dummy_data_1")
      {:ok, true} = Cachex.put(:portfolio_cache, cache_key_with_photos, "dummy_data_2")

      # Verify cache is populated
      assert {:ok, "dummy_data_1"} == Cachex.get(:portfolio_cache, cache_key_without_photos)
      assert {:ok, "dummy_data_2"} == Cachex.get(:portfolio_cache, cache_key_with_photos)

      # Publish event
      event = %AlbumPublished{
        album_id: Ecto.UUID.generate(),
        title: "Test Album",
        slug: "test-album",
        published_at: DateTime.utc_now(),
        user_id: Ecto.UUID.generate()
      }

      DomainEvents.publish(:album_published, event)

      # Give handler time to process event
      Process.sleep(100)

      # Verify cache was invalidated (entries should be removed)
      assert {:ok, nil} == Cachex.get(:portfolio_cache, cache_key_without_photos)
      assert {:ok, nil} == Cachex.get(:portfolio_cache, cache_key_with_photos)
    end
  end
end
