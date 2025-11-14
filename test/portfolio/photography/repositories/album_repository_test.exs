defmodule Portfolio.Photography.Repositories.AlbumRepositoryTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography.{Album, Photo}
  alias Portfolio.Photography.Repositories.AlbumRepository

  describe "list/0" do
    test "returns all albums" do
      album1 = insert_album(%{title: "Album 1", type: :wedding})
      album2 = insert_album(%{title: "Album 2", type: :couples})

      albums = AlbumRepository.list()

      assert length(albums) == 2
      assert Enum.find(albums, &(&1.id == album1.id))
      assert Enum.find(albums, &(&1.id == album2.id))
    end

    test "returns empty list when no albums" do
      assert AlbumRepository.list() == []
    end
  end

  describe "list/1 with filters" do
    setup do
      wedding1 = insert_album(%{title: "Wedding 1", type: :wedding, published: true})
      wedding2 = insert_album(%{title: "Wedding 2", type: :wedding, published: false})
      couples = insert_album(%{title: "Couples 1", type: :couples, published: true})

      %{wedding1: wedding1, wedding2: wedding2, couples: couples}
    end

    test "filters by type", %{wedding1: wedding1, wedding2: wedding2} do
      albums = AlbumRepository.list(type: :wedding)

      assert length(albums) == 2
      album_ids = Enum.map(albums, & &1.id)
      assert wedding1.id in album_ids
      assert wedding2.id in album_ids
    end

    test "filters by published", %{wedding1: wedding1, couples: couples} do
      albums = AlbumRepository.list(published: true)

      assert length(albums) == 2
      album_ids = Enum.map(albums, & &1.id)
      assert wedding1.id in album_ids
      assert couples.id in album_ids
    end

    test "filters by type and published", %{wedding1: wedding1} do
      albums = AlbumRepository.list(type: :wedding, published: true)

      assert length(albums) == 1
      assert hd(albums).id == wedding1.id
    end

    test "returns empty list when no match" do
      albums = AlbumRepository.list(type: :landscape)

      assert albums == []
    end

    test "orders published albums by date descending automatically" do
      # Create albums with different dates
      album_oldest =
        insert_album(%{
          title: "Oldest Album",
          type: :wedding,
          published: true,
          date_prise_vue: ~D[2022-01-15]
        })

      album_newest =
        insert_album(%{
          title: "Newest Album",
          type: :couples,
          published: true,
          date_prise_vue: ~D[2024-06-20]
        })

      album_middle =
        insert_album(%{
          title: "Middle Album",
          type: :landscape,
          published: true,
          date_prise_vue: ~D[2023-03-10]
        })

      # Unpublished album should not be included
      _unpublished =
        insert_album(%{
          title: "Unpublished",
          type: :wedding,
          published: false,
          date_prise_vue: ~D[2025-01-01]
        })

      # List published albums
      albums = AlbumRepository.list(published: true)

      # Should return 3 albums (unpublished excluded)
      assert length(albums) == 3

      # Should be ordered by date descending (newest first)
      assert Enum.at(albums, 0).id == album_newest.id
      assert Enum.at(albums, 1).id == album_middle.id
      assert Enum.at(albums, 2).id == album_oldest.id

      # Verify dates are in descending order
      dates = Enum.map(albums, & &1.date_prise_vue)
      assert dates == [~D[2024-06-20], ~D[2023-03-10], ~D[2022-01-15]]
    end
  end

  describe "list/1 with order_by" do
    setup do
      album_c =
        insert_album(%{title: "Charlie Album", type: :wedding, date_prise_vue: ~D[2024-03-15]})

      album_a =
        insert_album(%{title: "Alpha Album", type: :couples, date_prise_vue: ~D[2024-01-10]})

      album_b =
        insert_album(%{title: "Bravo Album", type: :landscape, date_prise_vue: ~D[2024-02-20]})

      %{album_a: album_a, album_b: album_b, album_c: album_c}
    end

    test "orders by title ascending", %{album_a: album_a, album_b: album_b, album_c: album_c} do
      albums = AlbumRepository.list(order_by: [asc: :title])

      assert length(albums) == 3
      assert Enum.at(albums, 0).id == album_a.id
      assert Enum.at(albums, 1).id == album_b.id
      assert Enum.at(albums, 2).id == album_c.id
    end

    test "orders by title descending", %{album_a: album_a, album_b: album_b, album_c: album_c} do
      albums = AlbumRepository.list(order_by: [desc: :title])

      assert length(albums) == 3
      assert Enum.at(albums, 0).id == album_c.id
      assert Enum.at(albums, 1).id == album_b.id
      assert Enum.at(albums, 2).id == album_a.id
    end

    test "orders by date ascending", %{album_a: album_a, album_b: album_b, album_c: album_c} do
      albums = AlbumRepository.list(order_by: [asc: :date_prise_vue])

      assert length(albums) == 3
      assert Enum.at(albums, 0).id == album_a.id
      assert Enum.at(albums, 1).id == album_b.id
      assert Enum.at(albums, 2).id == album_c.id
    end

    test "orders by date descending", %{album_a: album_a, album_b: album_b, album_c: album_c} do
      albums = AlbumRepository.list(order_by: [desc: :date_prise_vue])

      assert length(albums) == 3
      assert Enum.at(albums, 0).id == album_c.id
      assert Enum.at(albums, 1).id == album_b.id
      assert Enum.at(albums, 2).id == album_a.id
    end

    test "combines order_by with filters", %{album_a: album_a} do
      insert_album(%{title: "Zulu Wedding", type: :wedding, date_prise_vue: ~D[2024-04-01]})

      albums = AlbumRepository.list(type: :couples, order_by: [asc: :title])

      assert length(albums) == 1
      assert hd(albums).id == album_a.id
    end
  end

  describe "list/1 with preload" do
    test "preloads photos association" do
      album = insert_album(%{title: "Album with photos", type: :wedding})
      insert_photo(album, %{title: "Photo 1"})
      insert_photo(album, %{title: "Photo 2"})

      [loaded_album] = AlbumRepository.list(preload: [:photos])

      assert loaded_album.id == album.id
      assert length(loaded_album.photos) == 2
      refute match?(%Ecto.Association.NotLoaded{}, loaded_album.photos)
    end

    test "preloads multiple associations" do
      album = insert_album(%{title: "Album", type: :wedding})
      insert_photo(album, %{title: "Photo 1"})

      [loaded_album] = AlbumRepository.list(preload: [:photos])

      refute match?(%Ecto.Association.NotLoaded{}, loaded_album.photos)
    end
  end

  describe "get/1" do
    test "returns {:ok, album} when album exists" do
      album = insert_album(%{title: "Test Album", type: :wedding})

      assert {:ok, found_album} = AlbumRepository.get(album.id)
      assert found_album.id == album.id
      assert found_album.title == "Test Album"
    end

    test "returns {:error, :not_found} when album does not exist" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = AlbumRepository.get(fake_id)
    end

    test "preloads associations when specified" do
      album = insert_album(%{title: "Album", type: :wedding})
      insert_photo(album, %{title: "Photo 1"})

      assert {:ok, loaded_album} = AlbumRepository.get(album.id, preload: [:photos])

      assert length(loaded_album.photos) == 1
      refute match?(%Ecto.Association.NotLoaded{}, loaded_album.photos)
    end
  end

  describe "get!/1" do
    test "returns album when exists" do
      album = insert_album(%{title: "Test Album", type: :wedding})

      found_album = AlbumRepository.get!(album.id)

      assert found_album.id == album.id
      assert found_album.title == "Test Album"
    end

    test "raises Ecto.NoResultsError when album does not exist" do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        AlbumRepository.get!(fake_id)
      end
    end

    test "preloads associations when specified" do
      album = insert_album(%{title: "Album", type: :wedding})
      insert_photo(album, %{title: "Photo 1"})

      loaded_album = AlbumRepository.get!(album.id, preload: [:photos])

      assert length(loaded_album.photos) == 1
    end
  end

  describe "insert/1" do
    test "creates album with valid attributes" do
      attrs = %{
        title: "New Album",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        description: "A beautiful wedding",
        location: "Paris"
      }

      assert {:ok, album} = AlbumRepository.insert(attrs)
      assert album.title == "New Album"
      assert album.type == :wedding
      assert album.slug == "new-album"
      assert album.published == false
    end

    test "returns error with invalid attributes" do
      attrs = %{title: ""}

      assert {:error, changeset} = AlbumRepository.insert(attrs)
      refute changeset.valid?
    end

    test "generates slug automatically" do
      attrs = %{
        title: "Mon Album 2024",
        type: :couples,
        date_prise_vue: ~D[2024-01-01]
      }

      assert {:ok, album} = AlbumRepository.insert(attrs)
      assert album.slug == "mon-album-2024"
    end
  end

  describe "update/2" do
    test "updates album with valid attributes" do
      album = insert_album(%{title: "Original", type: :wedding})

      assert {:ok, updated} = AlbumRepository.update(album, %{title: "Updated"})
      assert updated.title == "Updated"
      assert updated.slug == "updated"
    end

    test "returns error with invalid attributes" do
      album = insert_album(%{title: "Original", type: :wedding})

      assert {:error, changeset} = AlbumRepository.update(album, %{title: ""})
      refute changeset.valid?
    end

    test "updates published status" do
      album = insert_album(%{title: "Album", type: :wedding, published: false})

      assert {:ok, updated} = AlbumRepository.update(album, %{published: true})
      assert updated.published == true
    end
  end

  describe "delete/1" do
    test "deletes album" do
      album = insert_album(%{title: "To Delete", type: :wedding})

      assert {:ok, deleted} = AlbumRepository.delete(album)
      assert deleted.id == album.id
      assert {:error, :not_found} = AlbumRepository.get(album.id)
    end

    test "deletes album with photos (CASCADE)" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo"})

      assert {:ok, _deleted} = AlbumRepository.delete(album)

      # Verify photo is also deleted
      assert is_nil(Repo.get(Photo, photo.id))
    end
  end

  describe "list_published_years/0" do
    test "returns distinct years with published albums in descending order" do
      insert_album(%{
        title: "Album 2024",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: true
      })

      insert_album(%{
        title: "Album 2023",
        type: :couples,
        date_prise_vue: ~D[2023-09-10],
        published: true
      })

      insert_album(%{
        title: "Album 2022",
        type: :events,
        date_prise_vue: ~D[2022-12-01],
        published: true
      })

      result = AlbumRepository.list_published_years()

      assert result == [2024, 2023, 2022]
    end

    test "excludes unpublished albums" do
      insert_album(%{
        title: "Published 2024",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: true
      })

      insert_album(%{
        title: "Draft 2023",
        type: :wedding,
        date_prise_vue: ~D[2023-06-15],
        published: false
      })

      result = AlbumRepository.list_published_years()

      assert result == [2024]
      refute 2023 in result
    end

    test "returns empty list when no published albums" do
      insert_album(%{
        title: "Draft",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: false
      })

      result = AlbumRepository.list_published_years()

      assert result == []
    end

    test "handles multiple albums in same year" do
      insert_album(%{
        title: "Album 2024-1",
        type: :wedding,
        date_prise_vue: ~D[2024-01-15],
        published: true
      })

      insert_album(%{
        title: "Album 2024-2",
        type: :couples,
        date_prise_vue: ~D[2024-12-31],
        published: true
      })

      result = AlbumRepository.list_published_years()

      # Should return year 2024 only once despite multiple albums
      assert result == [2024]
    end
  end

  describe "list_published_for_year/2" do
    test "returns albums for specific year only" do
      album_2024_1 =
        insert_album(%{
          title: "Album 2024-1",
          type: :wedding,
          date_prise_vue: ~D[2024-01-15],
          published: true
        })

      album_2024_2 =
        insert_album(%{
          title: "Album 2024-2",
          type: :couples,
          date_prise_vue: ~D[2024-12-31],
          published: true
        })

      _album_2023 =
        insert_album(%{
          title: "Album 2023",
          type: :events,
          date_prise_vue: ~D[2023-06-15],
          published: true
        })

      result = AlbumRepository.list_published_for_year(2024)

      assert length(result) == 2
      album_ids = Enum.map(result, & &1.id)
      assert album_2024_1.id in album_ids
      assert album_2024_2.id in album_ids
    end

    test "excludes unpublished albums for the year" do
      insert_album(%{
        title: "Published 2024",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: true
      })

      insert_album(%{
        title: "Draft 2024",
        type: :couples,
        date_prise_vue: ~D[2024-09-20],
        published: false
      })

      result = AlbumRepository.list_published_for_year(2024)

      assert length(result) == 1
      assert hd(result).title == "Published 2024"
    end

    test "returns empty list for year with no albums" do
      insert_album(%{
        title: "Album 2024",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: true
      })

      result = AlbumRepository.list_published_for_year(2023)

      assert result == []
    end

    test "orders albums by date descending within the year" do
      album_dec =
        insert_album(%{
          title: "December",
          type: :wedding,
          date_prise_vue: ~D[2024-12-25],
          published: true
        })

      album_jan =
        insert_album(%{
          title: "January",
          type: :couples,
          date_prise_vue: ~D[2024-01-10],
          published: true
        })

      album_jun =
        insert_album(%{
          title: "June",
          type: :events,
          date_prise_vue: ~D[2024-06-15],
          published: true
        })

      result = AlbumRepository.list_published_for_year(2024)

      # Should be ordered: December, June, January
      assert [album_dec.id, album_jun.id, album_jan.id] == Enum.map(result, & &1.id)
    end

    test "supports preload option" do
      album =
        insert_album(%{
          title: "Album 2024",
          type: :wedding,
          date_prise_vue: ~D[2024-06-15],
          published: true
        })

      insert_photo(album, %{title: "Photo 1"})
      insert_photo(album, %{title: "Photo 2"})

      result = AlbumRepository.list_published_for_year(2024, preload: [:photos])

      assert length(result) == 1
      album_with_photos = hd(result)
      assert Ecto.assoc_loaded?(album_with_photos.photos)
      assert length(album_with_photos.photos) == 2
    end
  end

  describe "list_published_by_year/0" do
    test "groups published albums by year" do
      insert_album(%{
        title: "Album 2024-1",
        type: :wedding,
        date_prise_vue: ~D[2024-12-25],
        published: true
      })

      insert_album(%{
        title: "Album 2024-2",
        type: :couples,
        date_prise_vue: ~D[2024-06-15],
        published: true
      })

      insert_album(%{
        title: "Album 2023",
        type: :events,
        date_prise_vue: ~D[2023-09-10],
        published: true
      })

      result = AlbumRepository.list_published_by_year()

      assert Map.has_key?(result, 2024)
      assert Map.has_key?(result, 2023)
      assert length(result[2024]) == 2
      assert length(result[2023]) == 1
    end

    test "excludes unpublished albums" do
      insert_album(%{
        title: "Published",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: true
      })

      insert_album(%{
        title: "Draft",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: false
      })

      result = AlbumRepository.list_published_by_year()

      assert length(result[2024]) == 1
      assert hd(result[2024]).title == "Published"
    end

    test "sorts albums by date descending within year" do
      insert_album(%{
        title: "June",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: true
      })

      insert_album(%{
        title: "December",
        type: :wedding,
        date_prise_vue: ~D[2024-12-25],
        published: true
      })

      insert_album(%{
        title: "March",
        type: :wedding,
        date_prise_vue: ~D[2024-03-10],
        published: true
      })

      result = AlbumRepository.list_published_by_year()

      albums_2024 = result[2024]
      assert length(albums_2024) == 3
      assert Enum.at(albums_2024, 0).title == "December"
      assert Enum.at(albums_2024, 1).title == "June"
      assert Enum.at(albums_2024, 2).title == "March"
    end

    test "returns empty map when no published albums" do
      insert_album(%{
        title: "Draft",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        published: false
      })

      result = AlbumRepository.list_published_by_year()

      assert result == %{}
    end

    test "preloads associations when specified" do
      album =
        insert_album(%{
          title: "Album",
          type: :wedding,
          date_prise_vue: ~D[2024-06-15],
          published: true
        })

      insert_photo(album, %{title: "Photo 1"})

      result = AlbumRepository.list_published_by_year(preload: [:photos])

      albums_2024 = result[2024]
      loaded_album = hd(albums_2024)
      assert length(loaded_album.photos) == 1
      refute match?(%Ecto.Association.NotLoaded{}, loaded_album.photos)
    end
  end

  # Helper functions

  defp insert_album(attrs) do
    default_attrs = %{
      title: "Test Album",
      type: :wedding,
      date_prise_vue: ~D[2024-01-15],
      published: false
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    %Album{}
    |> Album.changeset(merged_attrs)
    |> Repo.insert!()
  end

  defp insert_photo(album, attrs) do
    default_attrs = %{
      album_id: album.id,
      original_filename: "test.jpg",
      file_path: "/test.jpg",
      title: "Test Photo"
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    %Photo{}
    |> Photo.changeset(merged_attrs)
    |> Repo.insert!()
  end
end
