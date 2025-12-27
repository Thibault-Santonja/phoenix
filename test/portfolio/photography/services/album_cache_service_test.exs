defmodule Portfolio.Photography.Services.AlbumCacheServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Config.CacheConfig
  alias Portfolio.Photography.Services.AlbumCacheService

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "list_published_albums_by_year/1" do
    test "returns empty map when no published albums exist" do
      result = AlbumCacheService.list_published_albums_by_year()

      assert result == %{}
    end

    test "returns albums grouped by year" do
      album_2024 = create_album(published: true, date_prise_vue: ~D[2024-06-15])
      album_2023 = create_album(published: true, date_prise_vue: ~D[2023-03-20])
      album_2024_second = create_album(published: true, date_prise_vue: ~D[2024-09-10])

      result = AlbumCacheService.list_published_albums_by_year()

      assert map_size(result) == 2
      assert length(result[2024]) == 2
      assert length(result[2023]) == 1

      album_ids_2024 = Enum.map(result[2024], & &1.id)
      assert album_2024.id in album_ids_2024
      assert album_2024_second.id in album_ids_2024

      album_ids_2023 = Enum.map(result[2023], & &1.id)
      assert album_2023.id in album_ids_2023
    end

    test "excludes unpublished albums" do
      _published_album = create_album(published: true, date_prise_vue: ~D[2024-06-15])
      _unpublished_album = create_album(published: false, date_prise_vue: ~D[2024-03-20])

      result = AlbumCacheService.list_published_albums_by_year()

      assert map_size(result) == 1
      assert length(result[2024]) == 1
    end

    test "respects preload option" do
      album = create_album_with_photos(3, published: true, date_prise_vue: ~D[2024-06-15])

      result = AlbumCacheService.list_published_albums_by_year(preload: [:photos])

      albums_2024 = result[2024]
      retrieved_album = Enum.find(albums_2024, &(&1.id == album.id))

      assert retrieved_album.photos != []
      assert length(retrieved_album.photos) == 3
    end

    test "does not preload associations by default" do
      _album = create_album_with_photos(3, published: true, date_prise_vue: ~D[2024-06-15])

      result = AlbumCacheService.list_published_albums_by_year()

      albums_2024 = result[2024]
      retrieved_album = List.first(albums_2024)

      refute Ecto.assoc_loaded?(retrieved_album.photos)
    end

    test "skip_cache option bypasses cache" do
      _album = create_album(published: true, date_prise_vue: ~D[2024-06-15])

      result1 = AlbumCacheService.list_published_albums_by_year(skip_cache: true)
      assert map_size(result1) == 1

      _album2 = create_album(published: true, date_prise_vue: ~D[2024-03-20])

      result2 = AlbumCacheService.list_published_albums_by_year(skip_cache: true)
      assert length(result2[2024]) == 2
    end

    test "returns albums sorted by date within each year (most recent first)" do
      album_jan = create_album(published: true, date_prise_vue: ~D[2024-01-15])
      album_jun = create_album(published: true, date_prise_vue: ~D[2024-06-20])
      album_mar = create_album(published: true, date_prise_vue: ~D[2024-03-10])

      result = AlbumCacheService.list_published_albums_by_year()

      albums_2024 = result[2024]
      assert length(albums_2024) == 3

      assert Enum.at(albums_2024, 0).id == album_jun.id
      assert Enum.at(albums_2024, 1).id == album_mar.id
      assert Enum.at(albums_2024, 2).id == album_jan.id
    end

    test "handles albums from multiple years correctly" do
      create_album(published: true, date_prise_vue: ~D[2024-06-15])
      create_album(published: true, date_prise_vue: ~D[2023-03-20])
      create_album(published: true, date_prise_vue: ~D[2022-11-05])
      create_album(published: true, date_prise_vue: ~D[2024-01-10])

      result = AlbumCacheService.list_published_albums_by_year()

      assert map_size(result) == 3
      assert length(result[2024]) == 2
      assert length(result[2023]) == 1
      assert length(result[2022]) == 1
    end

    test "in test environment, always fetches from database" do
      _album1 = create_album(published: true, date_prise_vue: ~D[2024-06-15])

      result1 = AlbumCacheService.list_published_albums_by_year()
      assert length(result1[2024]) == 1

      _album2 = create_album(published: true, date_prise_vue: ~D[2024-03-20])

      result2 = AlbumCacheService.list_published_albums_by_year()
      assert length(result2[2024]) == 2
    end
  end

  describe "list_published_albums/1" do
    test "returns empty list when no published albums exist" do
      result = AlbumCacheService.list_published_albums()

      assert result == []
    end

    test "returns flat list of all published albums" do
      album_2024_1 = create_album(published: true, date_prise_vue: ~D[2024-06-15])
      album_2024_2 = create_album(published: true, date_prise_vue: ~D[2024-03-20])
      album_2023 = create_album(published: true, date_prise_vue: ~D[2023-09-10])

      result = AlbumCacheService.list_published_albums()

      assert length(result) == 3

      album_ids = Enum.map(result, & &1.id)
      assert album_2024_1.id in album_ids
      assert album_2024_2.id in album_ids
      assert album_2023.id in album_ids
    end

    test "excludes unpublished albums" do
      _published_album = create_album(published: true, date_prise_vue: ~D[2024-06-15])
      _unpublished_album = create_album(published: false, date_prise_vue: ~D[2024-03-20])

      result = AlbumCacheService.list_published_albums()

      assert length(result) == 1
    end

    test "respects preload option" do
      album = create_album_with_photos(3, published: true, date_prise_vue: ~D[2024-06-15])

      result = AlbumCacheService.list_published_albums(preload: [:photos])

      retrieved_album = Enum.find(result, &(&1.id == album.id))

      assert retrieved_album.photos != []
      assert length(retrieved_album.photos) == 3
    end

    test "returns all published albums from all years" do
      album_2024_jun = create_album(published: true, date_prise_vue: ~D[2024-06-15])
      album_2024_jan = create_album(published: true, date_prise_vue: ~D[2024-01-10])
      album_2023 = create_album(published: true, date_prise_vue: ~D[2023-09-10])

      result = AlbumCacheService.list_published_albums()

      album_ids = Enum.map(result, & &1.id)
      assert album_2024_jun.id in album_ids
      assert album_2024_jan.id in album_ids
      assert album_2023.id in album_ids
    end
  end

  describe "invalidate_cache/0" do
    test "invalidates cache for albums without preloads" do
      Cachex.put(:portfolio_cache, CacheConfig.published_albums_key(), %{2024 => []})

      assert {:ok, %{2024 => []}} =
               Cachex.get(:portfolio_cache, CacheConfig.published_albums_key())

      AlbumCacheService.invalidate_cache()

      assert {:ok, nil} = Cachex.get(:portfolio_cache, CacheConfig.published_albums_key())
    end

    test "invalidates cache for albums with photos preloaded" do
      Cachex.put(
        :portfolio_cache,
        CacheConfig.published_albums_key(preloads: [:photos]),
        %{2024 => []}
      )

      assert {:ok, %{2024 => []}} =
               Cachex.get(:portfolio_cache, CacheConfig.published_albums_key(preloads: [:photos]))

      AlbumCacheService.invalidate_cache()

      assert {:ok, nil} =
               Cachex.get(:portfolio_cache, CacheConfig.published_albums_key(preloads: [:photos]))
    end

    test "always returns :ok" do
      assert :ok = AlbumCacheService.invalidate_cache()
    end

    test "returns :ok even when cache keys do not exist" do
      Cachex.clear(:portfolio_cache)

      assert :ok = AlbumCacheService.invalidate_cache()
    end
  end

  describe "edge cases" do
    test "handles albums with same date correctly" do
      album1 = create_album(published: true, date_prise_vue: ~D[2024-06-15], title: "Album A")
      album2 = create_album(published: true, date_prise_vue: ~D[2024-06-15], title: "Album B")

      result = AlbumCacheService.list_published_albums_by_year()

      albums_2024 = result[2024]
      assert length(albums_2024) == 2

      album_ids = Enum.map(albums_2024, & &1.id)
      assert album1.id in album_ids
      assert album2.id in album_ids
    end

    test "handles albums on year boundaries" do
      album_2024_start = create_album(published: true, date_prise_vue: ~D[2024-01-01])
      album_2023_end = create_album(published: true, date_prise_vue: ~D[2023-12-31])

      result = AlbumCacheService.list_published_albums_by_year()

      assert map_size(result) == 2
      assert length(result[2024]) == 1
      assert length(result[2023]) == 1

      assert List.first(result[2024]).id == album_2024_start.id
      assert List.first(result[2023]).id == album_2023_end.id
    end

    test "handles empty preload list option" do
      _album = create_album(published: true, date_prise_vue: ~D[2024-06-15])

      result = AlbumCacheService.list_published_albums_by_year(preload: [])

      assert map_size(result) == 1
      assert length(result[2024]) == 1
    end

    test "handles albums with all types" do
      types = [:wedding, :couples, :motherhood, :landscape, :music]

      albums =
        for type <- types do
          create_album(published: true, type: type, date_prise_vue: ~D[2024-06-15])
        end

      result = AlbumCacheService.list_published_albums_by_year()

      albums_2024 = result[2024]
      assert length(albums_2024) == 5

      album_ids = Enum.map(albums_2024, & &1.id)

      for album <- albums do
        assert album.id in album_ids
      end
    end
  end

  describe "cache key generation" do
    test "generates different cache keys for different preload options" do
      key_no_preload = CacheConfig.published_albums_key()
      key_with_photos = CacheConfig.published_albums_key(preloads: [:photos])

      assert key_no_preload != key_with_photos
      assert key_no_preload == {:published_albums_by_year, []}
      assert key_with_photos == {:published_albums_by_year, [:photos]}
    end

    test "generates same cache key for empty preload list and no preload" do
      key_no_preload = CacheConfig.published_albums_key()
      key_empty_preload = CacheConfig.published_albums_key(preloads: [])

      assert key_no_preload == key_empty_preload
    end
  end
end
