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
end
