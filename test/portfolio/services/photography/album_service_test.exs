defmodule Portfolio.Services.Photography.AlbumServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Services.Photography.AlbumService

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "list_albums/1" do
    test "returns empty list when no albums exist" do
      assert AlbumService.list_albums() == []
    end

    test "returns all albums" do
      album1 = create_album(title: "Album 1")
      album2 = create_album(title: "Album 2")

      albums = AlbumService.list_albums()

      assert length(albums) == 2
      album_ids = Enum.map(albums, & &1.id)
      assert album1.id in album_ids
      assert album2.id in album_ids
    end

    test "filters by type" do
      _wedding = create_album(type: :wedding)
      couples = create_album(type: :couples)

      albums = AlbumService.list_albums(type: :couples)

      assert length(albums) == 1
      assert hd(albums).id == couples.id
    end

    test "filters by published status" do
      _draft = create_album(published: false)
      published = create_album(published: true)

      albums = AlbumService.list_albums(published: true)

      assert length(albums) == 1
      assert hd(albums).id == published.id
    end

    test "preloads associations" do
      album = create_album_with_photos(3)

      [fetched] = AlbumService.list_albums(preload: [:photos])

      assert fetched.id == album.id
      assert Ecto.assoc_loaded?(fetched.photos)
      assert length(fetched.photos) == 3
    end
  end

  describe "get_album/2" do
    test "returns album by id" do
      album = create_album()

      assert {:ok, fetched} = AlbumService.get_album(album.id)
      assert fetched.id == album.id
    end

    test "returns error for non-existent album" do
      assert {:error, :not_found} = AlbumService.get_album(Ecto.UUID.generate())
    end

    test "preloads associations" do
      album = create_album_with_photos(2)

      assert {:ok, fetched} = AlbumService.get_album(album.id, preload: [:photos])
      assert Ecto.assoc_loaded?(fetched.photos)
      assert length(fetched.photos) == 2
    end
  end

  describe "get_album_by_slug/2" do
    test "returns album by slug" do
      album = create_album(title: "My Wedding Album")

      assert {:ok, fetched} = AlbumService.get_album_by_slug(album.slug)
      assert fetched.id == album.id
    end

    test "returns error for non-existent slug" do
      assert {:error, :not_found} = AlbumService.get_album_by_slug("non-existent-slug")
    end
  end

  describe "get_album!/2" do
    test "returns album by id" do
      album = create_album()

      fetched = AlbumService.get_album!(album.id)
      assert fetched.id == album.id
    end

    test "raises for non-existent album" do
      assert_raise Ecto.NoResultsError, fn ->
        AlbumService.get_album!(Ecto.UUID.generate())
      end
    end
  end

  describe "create_album/1" do
    test "creates album with valid attributes" do
      attrs = %{
        title: "New Album",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15]
      }

      assert {:ok, album} = AlbumService.create_album(attrs)
      assert album.title == "New Album"
      assert album.type == :wedding
      assert album.date_prise_vue == ~D[2024-06-15]
      assert album.slug != nil
    end

    test "returns error with invalid attributes" do
      attrs = %{title: nil, type: :invalid_type}

      assert {:error, changeset} = AlbumService.create_album(attrs)
      assert changeset.valid? == false
    end

    test "returns error when slug already exists" do
      {:ok, _album1} =
        AlbumService.create_album(%{
          title: "Same Title",
          type: :wedding,
          date_prise_vue: ~D[2024-01-01]
        })

      # Second album with same title should fail due to slug uniqueness
      assert {:error, changeset} =
               AlbumService.create_album(%{
                 title: "Same Title",
                 type: :wedding,
                 date_prise_vue: ~D[2024-01-01]
               })

      assert {"has already been taken", _} = changeset.errors[:slug]
    end

    test "allows different titles to create albums" do
      {:ok, album1} =
        AlbumService.create_album(%{
          title: "First Album",
          type: :wedding,
          date_prise_vue: ~D[2024-01-01]
        })

      {:ok, album2} =
        AlbumService.create_album(%{
          title: "Second Album",
          type: :wedding,
          date_prise_vue: ~D[2024-01-01]
        })

      assert album1.slug != album2.slug
    end
  end

  describe "update_album/2" do
    test "updates album with valid attributes" do
      album = create_album(title: "Old Title")

      assert {:ok, updated} = AlbumService.update_album(album, %{title: "New Title"})
      assert updated.title == "New Title"
    end

    test "returns error with invalid attributes" do
      album = create_album()

      assert {:error, changeset} = AlbumService.update_album(album, %{type: :invalid})
      assert changeset.valid? == false
    end
  end

  describe "count functions" do
    setup do
      _draft1 = create_album(published: false)
      _draft2 = create_album(published: false)
      _published1 = create_album(published: true)
      :ok
    end

    test "count_all_albums/0 returns total count" do
      assert AlbumService.count_all_albums() == 3
    end

    test "count_published_albums/0 returns published count" do
      assert AlbumService.count_published_albums() == 1
    end

    test "count_draft_albums/0 returns draft count" do
      assert AlbumService.count_draft_albums() == 2
    end

    test "get_album_stats/0 returns all stats" do
      stats = AlbumService.get_album_stats()

      assert stats.total == 3
      assert stats.published == 1
      assert stats.draft == 2
    end
  end

  describe "list_published_years/0" do
    test "returns empty list when no published albums" do
      _draft = create_album(published: false)

      assert AlbumService.list_published_years() == []
    end

    test "returns years in descending order" do
      create_album(published: true, date_prise_vue: ~D[2024-06-15])
      create_album(published: true, date_prise_vue: ~D[2022-03-10])
      create_album(published: true, date_prise_vue: ~D[2023-09-01])

      years = AlbumService.list_published_years()

      assert years == [2024, 2023, 2022]
    end

    test "returns unique years" do
      create_album(published: true, date_prise_vue: ~D[2024-01-15])
      create_album(published: true, date_prise_vue: ~D[2024-06-20])

      years = AlbumService.list_published_years()

      assert years == [2024]
    end
  end

  describe "list_published_for_year/2" do
    test "returns albums for specific year" do
      album_2024 = create_album(published: true, date_prise_vue: ~D[2024-06-15])
      _album_2023 = create_album(published: true, date_prise_vue: ~D[2023-03-10])

      albums = AlbumService.list_published_for_year(2024)

      assert length(albums) == 1
      assert hd(albums).id == album_2024.id
    end

    test "returns empty list for year with no albums" do
      _album = create_album(published: true, date_prise_vue: ~D[2024-06-15])

      albums = AlbumService.list_published_for_year(2020)

      assert albums == []
    end

    test "excludes unpublished albums" do
      _draft = create_album(published: false, date_prise_vue: ~D[2024-06-15])
      published = create_album(published: true, date_prise_vue: ~D[2024-03-10])

      albums = AlbumService.list_published_for_year(2024)

      assert length(albums) == 1
      assert hd(albums).id == published.id
    end

    test "preloads associations" do
      album = create_album_with_photos(3, published: true, date_prise_vue: ~D[2024-06-15])

      [fetched] = AlbumService.list_published_for_year(2024, preload: [:photos])

      assert fetched.id == album.id
      assert Ecto.assoc_loaded?(fetched.photos)
      assert length(fetched.photos) == 3
    end
  end

  describe "fetch_published_albums_by_year/1" do
    test "returns empty map when no published albums" do
      _draft = create_album(published: false)

      result = AlbumService.fetch_published_albums_by_year()

      assert result == %{}
    end

    test "returns albums grouped by year" do
      album_2024 = create_album(published: true, date_prise_vue: ~D[2024-06-15])
      album_2023 = create_album(published: true, date_prise_vue: ~D[2023-03-10])

      result = AlbumService.fetch_published_albums_by_year()

      assert map_size(result) == 2
      assert length(result[2024]) == 1
      assert length(result[2023]) == 1
      assert hd(result[2024]).id == album_2024.id
      assert hd(result[2023]).id == album_2023.id
    end

    test "preloads associations" do
      album = create_album_with_photos(2, published: true, date_prise_vue: ~D[2024-06-15])

      result = AlbumService.fetch_published_albums_by_year(preload: [:photos])

      fetched = hd(result[2024])
      assert fetched.id == album.id
      assert Ecto.assoc_loaded?(fetched.photos)
      assert length(fetched.photos) == 2
    end
  end

  describe "list_album_types/0" do
    test "returns all album types" do
      types = AlbumService.list_album_types()

      assert :wedding in types
      assert :couples in types
      assert :motherhood in types
      assert :landscape in types
      assert :music in types
      assert length(types) == 12
    end
  end

  describe "count_photos_in_album/1" do
    test "returns 0 for album with no photos" do
      album = create_album()

      assert AlbumService.count_photos_in_album(album.id) == 0
    end

    test "returns correct count" do
      album = create_album_with_photos(5)

      assert AlbumService.count_photos_in_album(album.id) == 5
    end
  end
end
