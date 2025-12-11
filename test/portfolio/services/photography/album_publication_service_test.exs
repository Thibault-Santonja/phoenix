defmodule Portfolio.Services.Photography.AlbumPublicationServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Services.Photography.AlbumPublicationService

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
  end
end
