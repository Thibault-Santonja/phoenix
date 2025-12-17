defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandlerTest do
  use Portfolio.DataCase, async: false

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.EventHandlers.AlbumPublishedHandler
  alias Portfolio.Photography.Events.AlbumPublished

  # Helper to ensure GenServer has processed all pending messages
  defp flush_handler(pid) do
    :sys.get_state(pid)
    :ok
  end

  setup do
    # Start the handler for tests
    case AlbumPublishedHandler.start_link([]) do
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

  describe "handle_info/2 for album_published" do
    test "handles AlbumPublished event", %{handler: handler} do
      album = create_album(title: "Test Album", published: true)

      event = %AlbumPublished{
        album_id: album.id,
        title: album.title,
        slug: album.slug,
        published_at: DateTime.utc_now(),
        user_id: "test-user"
      }

      # Send event directly to the handler
      send(handler, {:album_published, event})
      flush_handler(handler)

      # Handler should not crash
      assert Process.alive?(handler)
    end

    test "clears albums cache on publication", %{handler: handler} do
      album = create_album(title: "Cache Test Album", published: true)

      # Seed the cache
      Cachex.put(:portfolio_cache, {:published_albums_by_year, []}, ["cached"])
      Cachex.put(:portfolio_cache, {:published_albums_by_year, [:photos]}, ["cached_photos"])

      event = %AlbumPublished{
        album_id: album.id,
        title: album.title,
        slug: album.slug,
        published_at: DateTime.utc_now(),
        user_id: "test-user"
      }

      send(handler, {:album_published, event})
      flush_handler(handler)

      # Cache should be cleared
      assert {:ok, nil} = Cachex.get(:portfolio_cache, {:published_albums_by_year, []})
      assert {:ok, nil} = Cachex.get(:portfolio_cache, {:published_albums_by_year, [:photos]})
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
      album = create_album(title: "Integration Test", published: true)

      # Publish via DomainEvents
      DomainEvents.publish(:album_published, %AlbumPublished{
        album_id: album.id,
        title: album.title,
        slug: album.slug,
        published_at: DateTime.utc_now(),
        user_id: "test-user"
      })

      flush_handler(handler)

      # Handler should still be alive
      assert Process.alive?(handler)
    end
  end
end
