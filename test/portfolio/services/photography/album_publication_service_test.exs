defmodule Portfolio.Services.Photography.AlbumPublicationServiceTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Photography
  alias Portfolio.Services.Photography.AlbumPublicationService

  describe "execute/2" do
    setup do
      {:ok, album} =
        Photography.create_album(%{
          title: "Test Album for Publication",
          type: :wedding,
          date_prise_vue: ~D[2024-01-15],
          published: false
        })

      {:ok, album: album}
    end

    test "publishes album successfully", %{album: album} do
      assert album.published == false

      result = AlbumPublicationService.execute(album)

      assert {:ok, published_album} = result
      assert published_album.published == true
    end

    test "accepts user_id option", %{album: album} do
      user_id = Ecto.UUID.generate()

      result = AlbumPublicationService.execute(album, user_id: user_id)

      assert {:ok, _published_album} = result
    end

    test "updates album in database", %{album: album} do
      {:ok, _} = AlbumPublicationService.execute(album)

      # Reload from database
      {:ok, reloaded} = Photography.get_album(album.id)
      assert reloaded.published == true
    end

    test "invalidates cache", %{album: album} do
      # Pre-populate cache
      Cachex.put(:portfolio_cache, {:published_albums_by_year, []}, [])
      Cachex.put(:portfolio_cache, {:published_albums_by_year, [:photos]}, [])

      {:ok, _} = AlbumPublicationService.execute(album)

      # Cache should be invalidated
      assert {:ok, nil} = Cachex.get(:portfolio_cache, {:published_albums_by_year, []})
      assert {:ok, nil} = Cachex.get(:portfolio_cache, {:published_albums_by_year, [:photos]})
    end

    test "emits telemetry event", %{album: album} do
      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:portfolio, :services, :album_publication, :executed]
        ])

      AlbumPublicationService.execute(album)

      assert_received {[:portfolio, :services, :album_publication, :executed], ^ref,
                       %{duration: _}, %{album_id: _, result: :ok}}
    end

    test "raises StaleEntryError for deleted album" do
      # Create album then delete it to simulate invalid state
      {:ok, album} =
        Photography.create_album(%{
          title: "To Delete",
          type: :wedding,
          date_prise_vue: ~D[2024-01-01]
        })

      Photography.delete_album(album)

      # Try to publish deleted album - Ecto raises StaleEntryError
      assert_raise Ecto.StaleEntryError, fn ->
        AlbumPublicationService.execute(album)
      end
    end
  end
end
