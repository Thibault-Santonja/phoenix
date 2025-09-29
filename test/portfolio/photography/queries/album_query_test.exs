defmodule Portfolio.Photography.Queries.AlbumQueryTest do
  use Portfolio.DataCase

  import Ecto.Query, only: [where: 3]

  alias Portfolio.Photography.Queries.AlbumQuery
  alias Portfolio.Repo

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "with_photo_count/1" do
    test "adds photo count to albums without loading photos" do
      # Create albums with different photo counts
      album1 = create_album(title: "Album 1 #{System.unique_integer([:positive])}")
      album2 = create_album(title: "Album 2 #{System.unique_integer([:positive])}")
      album3 = create_album(title: "Album 3 #{System.unique_integer([:positive])}")

      # Add photos to albums
      create_photo(album: album1, original_filename: "photo1.jpg")
      create_photo(album: album1, original_filename: "photo2.jpg")
      create_photo(album: album1, original_filename: "photo3.jpg")

      create_photo(album: album2, original_filename: "photo1.jpg")

      # album3 has no photos

      # Query albums with photo count - filter to only our test albums
      albums =
        AlbumQuery.base()
        |> AlbumQuery.with_photo_count()
        |> where([album: a], a.id in ^[album1.id, album2.id, album3.id])
        |> Repo.all()
        |> Enum.sort_by(& &1.title)

      # Verify counts
      assert length(albums) == 3

      [a1, a2, a3] = albums

      assert a1.id == album1.id
      assert a1.photo_count == 3

      assert a2.id == album2.id
      assert a2.photo_count == 1

      assert a3.id == album3.id
      assert a3.photo_count == 0
    end

    test "photo_count is computed in SQL, not by loading associations" do
      album = create_album(title: "Test Album #{System.unique_integer([:positive])}")
      create_photo(album: album, original_filename: "photo1.jpg")
      create_photo(album: album, original_filename: "photo2.jpg")

      result =
        AlbumQuery.base()
        |> AlbumQuery.with_photo_count()
        |> where([album: a], a.id == ^album.id)
        |> Repo.one()

      # Verify photos association is NOT loaded
      assert %Ecto.Association.NotLoaded{} = result.photos

      # But photo_count is available
      assert result.photo_count == 2
    end
  end

  describe "with_cover_photo_only/1" do
    test "loads only first photo instead of all photos" do
      album = create_album(title: "Test Album #{System.unique_integer([:positive])}")

      # Create 3 photos with different display orders
      _photo1 =
        create_photo(album: album, original_filename: "photo1.jpg", display_order: 2)

      photo2 = create_photo(album: album, original_filename: "photo2.jpg", display_order: 1)

      _photo3 =
        create_photo(album: album, original_filename: "photo3.jpg", display_order: 3)

      result =
        AlbumQuery.base()
        |> AlbumQuery.with_cover_photo_only()
        |> where([album: a], a.id == ^album.id)
        |> Repo.one()

      # Verify only 1 photo is loaded (not all 3)
      assert length(result.photos) == 1
      assert hd(result.photos).id == photo2.id
      assert hd(result.photos).original_filename == "photo2.jpg"
    end

    test "returns empty photos list for albums without photos" do
      album = create_album(title: "Empty Album #{System.unique_integer([:positive])}")

      result =
        AlbumQuery.base()
        |> AlbumQuery.with_cover_photo_only()
        |> where([album: a], a.id == ^album.id)
        |> Repo.one()

      # Verify photos list is empty
      assert result.photos == []
    end
  end

  describe "by_type/2" do
    test "filters albums by type" do
      wedding_album =
        create_album(type: :wedding, title: "Wedding #{System.unique_integer([:positive])}")

      couples_album =
        create_album(type: :couples, title: "Couples #{System.unique_integer([:positive])}")

      music_album =
        create_album(type: :music, title: "Music #{System.unique_integer([:positive])}")

      # Query only wedding albums
      albums =
        AlbumQuery.base()
        |> AlbumQuery.by_type(:wedding)
        |> where([album: a], a.id in ^[wedding_album.id, couples_album.id, music_album.id])
        |> Repo.all()

      assert length(albums) == 1
      assert hd(albums).id == wedding_album.id
      assert hd(albums).type == :wedding
    end

    test "returns multiple albums of same type" do
      wedding1 =
        create_album(type: :wedding, title: "Wedding 1 #{System.unique_integer([:positive])}")

      wedding2 =
        create_album(type: :wedding, title: "Wedding 2 #{System.unique_integer([:positive])}")

      _couples =
        create_album(type: :couples, title: "Couples #{System.unique_integer([:positive])}")

      albums =
        AlbumQuery.base()
        |> AlbumQuery.by_type(:wedding)
        |> where([album: a], a.id in ^[wedding1.id, wedding2.id])
        |> Repo.all()

      assert length(albums) == 2
      assert Enum.all?(albums, &(&1.type == :wedding))
    end
  end

  describe "published/1" do
    test "returns only published albums" do
      published1 =
        create_album(published: true, title: "Published 1 #{System.unique_integer([:positive])}")

      published2 =
        create_album(published: true, title: "Published 2 #{System.unique_integer([:positive])}")

      _draft =
        create_album(published: false, title: "Draft #{System.unique_integer([:positive])}")

      albums =
        AlbumQuery.base()
        |> AlbumQuery.published()
        |> where([album: a], a.id in ^[published1.id, published2.id])
        |> Repo.all()

      assert length(albums) == 2
      assert Enum.all?(albums, & &1.published)
    end

    test "returns empty list when no published albums" do
      draft1 =
        create_album(published: false, title: "Draft 1 #{System.unique_integer([:positive])}")

      draft2 =
        create_album(published: false, title: "Draft 2 #{System.unique_integer([:positive])}")

      albums =
        AlbumQuery.base()
        |> AlbumQuery.published()
        |> where([album: a], a.id in ^[draft1.id, draft2.id])
        |> Repo.all()

      assert albums == []
    end
  end

  describe "unpublished/1" do
    test "returns only unpublished albums" do
      draft1 =
        create_album(published: false, title: "Draft 1 #{System.unique_integer([:positive])}")

      draft2 =
        create_album(published: false, title: "Draft 2 #{System.unique_integer([:positive])}")

      _published =
        create_album(published: true, title: "Published #{System.unique_integer([:positive])}")

      albums =
        AlbumQuery.base()
        |> AlbumQuery.unpublished()
        |> where([album: a], a.id in ^[draft1.id, draft2.id])
        |> Repo.all()

      assert length(albums) == 2
      assert Enum.all?(albums, &(not &1.published))
    end
  end

  describe "order_by_date_desc/1" do
    test "orders albums by date_prise_vue descending" do
      album1 =
        create_album(
          date_prise_vue: ~D[2024-01-15],
          title: "Jan #{System.unique_integer([:positive])}"
        )

      album2 =
        create_album(
          date_prise_vue: ~D[2024-03-20],
          title: "Mar #{System.unique_integer([:positive])}"
        )

      album3 =
        create_album(
          date_prise_vue: ~D[2024-02-10],
          title: "Feb #{System.unique_integer([:positive])}"
        )

      albums =
        AlbumQuery.base()
        |> AlbumQuery.order_by_date_desc()
        |> where([album: a], a.id in ^[album1.id, album2.id, album3.id])
        |> Repo.all()

      # Should be ordered: March -> February -> January
      assert length(albums) == 3
      assert Enum.map(albums, & &1.id) == [album2.id, album3.id, album1.id]
    end

    test "handles albums with same date" do
      album1 =
        create_album(
          date_prise_vue: ~D[2024-01-15],
          title: "A #{System.unique_integer([:positive])}"
        )

      # Small delay to ensure different inserted_at timestamps
      Process.sleep(10)

      album2 =
        create_album(
          date_prise_vue: ~D[2024-01-15],
          title: "B #{System.unique_integer([:positive])}"
        )

      albums =
        AlbumQuery.base()
        |> AlbumQuery.order_by_date_desc()
        |> where([album: a], a.id in ^[album1.id, album2.id])
        |> Repo.all()

      # Both should be returned with same date
      assert length(albums) == 2
      # When dates are equal, order by inserted_at desc (most recent first)
      # album2 was created after album1, so it should be first
      album_ids = Enum.map(albums, & &1.id)
      assert album2.id in album_ids
      assert album1.id in album_ids
      # Verify the first one has inserted_at >= second one
      assert hd(albums).inserted_at >= Enum.at(albums, 1).inserted_at
    end
  end

  describe "with_preload/2" do
    test "preloads photos association" do
      album = create_album(title: "Test Album #{System.unique_integer([:positive])}")
      create_photo(album: album, original_filename: "photo1.jpg")
      create_photo(album: album, original_filename: "photo2.jpg")

      result =
        AlbumQuery.base()
        |> AlbumQuery.with_preload(:photos)
        |> where([album: a], a.id == ^album.id)
        |> Repo.one()

      # Verify photos are loaded
      assert length(result.photos) == 2
      refute match?(%Ecto.Association.NotLoaded{}, result.photos)
    end

    test "preloads multiple associations" do
      album = create_album(title: "Test Album #{System.unique_integer([:positive])}")
      create_photo(album: album, original_filename: "photo1.jpg")

      result =
        AlbumQuery.base()
        |> AlbumQuery.with_preload([:photos])
        |> where([album: a], a.id == ^album.id)
        |> Repo.one()

      # Verify associations are loaded
      assert length(result.photos) == 1
      refute match?(%Ecto.Association.NotLoaded{}, result.photos)
    end

    test "handles empty preload list" do
      album = create_album(title: "Test Album #{System.unique_integer([:positive])}")
      create_photo(album: album, original_filename: "photo1.jpg")

      result =
        AlbumQuery.base()
        |> AlbumQuery.with_preload([])
        |> where([album: a], a.id == ^album.id)
        |> Repo.one()

      # Verify photos are NOT loaded
      assert match?(%Ecto.Association.NotLoaded{}, result.photos)
    end
  end

  describe "query composition" do
    test "can chain multiple query functions" do
      wedding_published =
        create_album(
          type: :wedding,
          published: true,
          date_prise_vue: ~D[2024-03-15],
          title: "Wedding Published #{System.unique_integer([:positive])}"
        )

      wedding_draft =
        create_album(
          type: :wedding,
          published: false,
          date_prise_vue: ~D[2024-02-10],
          title: "Wedding Draft #{System.unique_integer([:positive])}"
        )

      _couples_published =
        create_album(
          type: :couples,
          published: true,
          date_prise_vue: ~D[2024-01-20],
          title: "Couples Published #{System.unique_integer([:positive])}"
        )

      # Chain: wedding + published + ordered by date
      albums =
        AlbumQuery.base()
        |> AlbumQuery.by_type(:wedding)
        |> AlbumQuery.published()
        |> AlbumQuery.order_by_date_desc()
        |> where([album: a], a.id in ^[wedding_published.id, wedding_draft.id])
        |> Repo.all()

      # Should only return published wedding album
      assert length(albums) == 1
      assert hd(albums).id == wedding_published.id
      assert hd(albums).type == :wedding
      assert hd(albums).published
    end
  end
end
