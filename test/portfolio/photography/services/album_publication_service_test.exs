defmodule Portfolio.Photography.Services.AlbumPublicationServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography.Services.AlbumPublicationService

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "execute/2" do
    test "publishes an unpublished album" do
      album = create_album(published: false)

      assert {:ok, published_album} = AlbumPublicationService.execute(album)

      assert published_album.published == true
    end

    test "returns ok for already published album" do
      album = create_album(published: true)

      assert {:ok, published_album} = AlbumPublicationService.execute(album)

      assert published_album.published == true
    end

    test "accepts user_id option" do
      album = create_album(published: false)
      user_id = Ecto.UUID.generate()

      assert {:ok, _album} = AlbumPublicationService.execute(album, user_id: user_id)
    end

    test "invalidates cache after publication" do
      album = create_album(published: false)

      # Put something in cache
      Cachex.put(:portfolio_cache, {:published_albums_by_year, []}, [])

      assert {:ok, _album} = AlbumPublicationService.execute(album)

      # Cache should be invalidated
      assert {:ok, nil} = Cachex.get(:portfolio_cache, {:published_albums_by_year, []})
    end

    test "emits telemetry event" do
      album = create_album(published: false)

      test_pid = self()

      :telemetry.attach(
        "test-album-publication",
        [:portfolio, :services, :album_publication, :executed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      AlbumPublicationService.execute(album)

      assert_receive {:telemetry, [:portfolio, :services, :album_publication, :executed],
                      measurements, metadata}

      assert measurements.duration > 0
      assert metadata.result == :ok
      assert metadata.album_id == album.id

      :telemetry.detach("test-album-publication")
    end

    test "emits domain event on publication" do
      album = create_album(published: false)

      # Subscribe to domain events
      Portfolio.DomainEvents.subscribe(:album_published)

      assert {:ok, _album} = AlbumPublicationService.execute(album, user_id: "test-user")

      # Should receive domain event
      assert_receive {:album_published, event}
      assert event.album_id == album.id
      assert event.title == album.title
      assert event.slug == album.slug
      assert event.user_id == "test-user"
    end

    test "invalidates both cache keys" do
      album = create_album(published: false)

      # Put something in both cache keys
      Cachex.put(:portfolio_cache, {:published_albums_by_year, []}, ["cached"])
      Cachex.put(:portfolio_cache, {:published_albums_by_year, [:photos]}, ["cached_with_photos"])

      assert {:ok, _album} = AlbumPublicationService.execute(album)

      # Both cache keys should be invalidated
      assert {:ok, nil} = Cachex.get(:portfolio_cache, {:published_albums_by_year, []})
      assert {:ok, nil} = Cachex.get(:portfolio_cache, {:published_albums_by_year, [:photos]})
    end
  end
end
