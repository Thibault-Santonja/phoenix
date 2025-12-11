defmodule Portfolio.Services.Photography.AlbumDeletionServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography
  alias Portfolio.Services.Photography.AlbumDeletionService

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "execute/2" do
    test "deletes an album with no photos" do
      album = create_album()

      assert {:ok, result} = AlbumDeletionService.execute(album)

      assert result.album.id == album.id
      assert result.photos == []

      # Album should be deleted from database
      assert {:error, :not_found} = Photography.get_album(album.id)
    end

    test "deletes an album with photos" do
      album = create_album()
      photo1 = create_photo(album: album)
      photo2 = create_photo(album: album)

      assert {:ok, result} = AlbumDeletionService.execute(album)

      assert result.album.id == album.id
      assert length(result.photos) == 2

      # Album and photos should be deleted
      assert {:error, :not_found} = Photography.get_album(album.id)
      assert {:error, :not_found} = Photography.get_photo(photo1.id)
      assert {:error, :not_found} = Photography.get_photo(photo2.id)
    end

    test "emits telemetry event for deletion" do
      album = create_album()

      test_pid = self()

      :telemetry.attach(
        "test-album-deletion",
        [:portfolio, :services, :album_deletion, :executed],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      AlbumDeletionService.execute(album)

      assert_receive {:telemetry, [:portfolio, :services, :album_deletion, :executed],
                      measurements, metadata}

      assert measurements.duration > 0
      assert metadata.album_id == album.id

      :telemetry.detach("test-album-deletion")
    end

    test "emits photo count telemetry" do
      album = create_album()
      _photo = create_photo(album: album)

      test_pid = self()

      :telemetry.attach(
        "test-album-deletion-count",
        [:portfolio, :services, :album_deletion, :photo_count],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      AlbumDeletionService.execute(album)

      assert_receive {:telemetry, [:portfolio, :services, :album_deletion, :photo_count],
                      measurements, metadata}

      assert measurements.photo_count == 1
      assert metadata.album_id == album.id

      :telemetry.detach("test-album-deletion-count")
    end

    test "handles album with many photos" do
      album = create_album()

      # Create multiple photos
      for _ <- 1..5 do
        create_photo(album: album)
      end

      assert {:ok, result} = AlbumDeletionService.execute(album)

      assert length(result.photos) == 5
      assert {:error, :not_found} = Photography.get_album(album.id)
    end
  end
end
