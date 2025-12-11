defmodule Portfolio.Photography.AlbumVisibilityTest do
  @moduledoc """
  Happy path tests for album visibility and publication.

  These tests verify that:
  - Published albums appear on public timeline
  - Draft albums are hidden from public views
  - Publication triggers cache invalidation
  """

  use Portfolio.DataCase, async: true

  @moduletag :skip

  alias Portfolio.Photography

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "album publication and visibility" do
    test "published album appears in public timeline" do
      # Arrange: Create published album
      album = create_album(title: "Public Wedding", published: true)

      # Act: Get published albums
      published_albums = Photography.list_published_albums()

      # Assert: Album appears in timeline
      album_ids = Enum.map(published_albums, & &1.id)
      assert album.id in album_ids
    end

    test "draft album is hidden from public timeline" do
      # Arrange: Create draft album
      draft_album = create_album(title: "Draft Album", published: false)

      # Act: Get published albums
      published_albums = Photography.list_published_albums()

      # Assert: Draft album not in timeline
      album_ids = Enum.map(published_albums, & &1.id)
      refute draft_album.id in album_ids
    end

    test "publishing album makes it visible" do
      # Arrange: Create draft album
      album = create_album(title: "Wedding Album", published: false)

      # Assert: Not visible before publication
      published_before = Photography.list_published_albums()
      refute album.id in Enum.map(published_before, & &1.id)

      # Act: Publish album
      assert {:ok, updated_album} = Photography.publish_album(album)

      # Assert: Album is published
      assert updated_album.published == true

      # Assert: Now visible in public timeline
      published_after = Photography.list_published_albums(skip_cache: true)
      assert updated_album.id in Enum.map(published_after, & &1.id)
    end

    test "published albums grouped by year" do
      # Arrange: Create albums in different years
      album_2023 =
        create_album(
          title: "Album 2023",
          published: true,
          date_prise_vue: ~D[2023-06-15]
        )

      album_2024 =
        create_album(
          title: "Album 2024",
          published: true,
          date_prise_vue: ~D[2024-08-20]
        )

      # Act: Get published albums grouped by year
      albums_by_year = Photography.list_published_albums_by_year(skip_cache: true)

      # Assert: Albums grouped correctly
      assert Map.has_key?(albums_by_year, 2023)
      assert Map.has_key?(albums_by_year, 2024)

      albums_2023 = Map.get(albums_by_year, 2023)
      albums_2024 = Map.get(albums_by_year, 2024)

      assert album_2023.id in Enum.map(albums_2023, & &1.id)
      assert album_2024.id in Enum.map(albums_2024, & &1.id)
    end

    test "list_published_for_year returns correct albums" do
      # Arrange: Create albums in specific year
      album1 =
        create_album(
          title: "Summer 2024",
          published: true,
          date_prise_vue: ~D[2024-06-01]
        )

      album2 =
        create_album(
          title: "Winter 2024",
          published: true,
          date_prise_vue: ~D[2024-12-01]
        )

      _album_2023 =
        create_album(
          title: "Album 2023",
          published: true,
          date_prise_vue: ~D[2023-06-01]
        )

      # Act: Get albums for 2024
      albums_2024 = Photography.list_published_for_year(2024)

      # Assert: Only 2024 albums returned
      assert length(albums_2024) == 2
      album_ids = Enum.map(albums_2024, & &1.id)
      assert album1.id in album_ids
      assert album2.id in album_ids
    end

    test "list_published_years returns all years with published albums" do
      # Arrange: Create albums in multiple years
      create_album(title: "2022", published: true, date_prise_vue: ~D[2022-01-01])
      create_album(title: "2023", published: true, date_prise_vue: ~D[2023-01-01])
      create_album(title: "2024", published: true, date_prise_vue: ~D[2024-01-01])

      # Act: Get published years
      years = Photography.list_published_years()

      # Assert: All years present
      assert 2022 in years
      assert 2023 in years
      assert 2024 in years
    end

    test "cache invalidation after publication" do
      # Arrange: Create draft album
      album = create_album(title: "Test Album", published: false)

      # Act: First call to populate cache
      before_publish = Photography.list_published_albums()
      refute album.id in Enum.map(before_publish, & &1.id)

      # Act: Publish album (should invalidate cache)
      assert {:ok, _updated} = Photography.publish_album(album)

      # Act: Get published albums again (should use fresh data)
      after_publish = Photography.list_published_albums()

      # Assert: Published album appears (cache was invalidated)
      assert album.id in Enum.map(after_publish, & &1.id)
    end

    test "multiple published albums appear in timeline" do
      # Arrange: Create multiple published albums
      album1 = create_album(title: "Wedding 1", published: true)
      album2 = create_album(title: "Wedding 2", published: true)
      album3 = create_album(title: "Wedding 3", published: true)

      # Act: Get published albums
      published = Photography.list_published_albums(skip_cache: true)

      # Assert: All published albums appear
      published_ids = Enum.map(published, & &1.id)
      assert album1.id in published_ids
      assert album2.id in published_ids
      assert album3.id in published_ids
    end

    test "draft albums remain hidden even with published albums" do
      # Arrange: Create mix of published and draft albums
      published1 = create_album(title: "Published 1", published: true)
      _draft1 = create_album(title: "Draft 1", published: false)
      published2 = create_album(title: "Published 2", published: true)
      _draft2 = create_album(title: "Draft 2", published: false)

      # Act: Get published albums
      published = Photography.list_published_albums(skip_cache: true)

      # Assert: Only published albums appear
      assert length(published) == 2
      published_ids = Enum.map(published, & &1.id)
      assert published1.id in published_ids
      assert published2.id in published_ids
    end

    test "album with photos can be published" do
      # Arrange: Create album with photos
      album = create_album_with_photos(3, title: "Album with Photos", published: false)

      # Act: Publish album
      assert {:ok, published_album} = Photography.publish_album(album)

      # Assert: Album published with photos intact
      assert published_album.published == true

      # Assert: Photos still belong to album
      photos = Photography.list_photos_by_album(published_album.id)
      assert length(photos) == 3
    end
  end
end
