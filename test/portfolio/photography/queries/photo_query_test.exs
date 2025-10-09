defmodule Portfolio.Photography.Queries.PhotoQueryTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography.Queries.PhotoQuery
  alias Portfolio.Repo

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "base/0" do
    test "returns base query" do
      query = PhotoQuery.base()
      assert %Ecto.Query{} = query
    end
  end

  describe "by_album/2" do
    test "filters photos by album" do
      album1 = create_album()
      album2 = create_album()
      photo1 = create_photo(album: album1)
      _photo2 = create_photo(album: album2)

      photos =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album1.id)
        |> Repo.all()

      assert length(photos) == 1
      assert hd(photos).id == photo1.id
    end
  end

  describe "published/1" do
    test "filters only published photos" do
      album = create_album()
      published_photo = create_photo(album: album, published: true)
      _unpublished_photo = create_photo(album: album, published: false)

      photos =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album.id)
        |> PhotoQuery.published()
        |> Repo.all()

      assert length(photos) == 1
      assert hd(photos).id == published_photo.id
    end
  end

  describe "unpublished/1" do
    test "filters only unpublished photos" do
      album = create_album()
      _published_photo = create_photo(album: album, published: true)
      unpublished_photo = create_photo(album: album, published: false)

      photos =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album.id)
        |> PhotoQuery.unpublished()
        |> Repo.all()

      assert length(photos) == 1
      assert hd(photos).id == unpublished_photo.id
    end
  end

  describe "order_by_display_order/1" do
    test "orders photos by display_order ascending" do
      album = create_album()
      photo1 = create_photo(album: album, display_order: 2)
      photo2 = create_photo(album: album, display_order: 0)
      photo3 = create_photo(album: album, display_order: 1)

      photos =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album.id)
        |> PhotoQuery.order_by_display_order()
        |> Repo.all()

      assert [photo2.id, photo3.id, photo1.id] == Enum.map(photos, & &1.id)
    end
  end

  describe "order_by_date_desc/1" do
    test "orders photos by taken_at descending" do
      album = create_album()
      date1 = ~D[2024-01-01]
      date2 = ~D[2024-02-01]
      date3 = ~D[2024-03-01]

      photo1 = create_photo(album: album, taken_at: date1)
      photo2 = create_photo(album: album, taken_at: date3)
      photo3 = create_photo(album: album, taken_at: date2)

      photos =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album.id)
        |> PhotoQuery.order_by_date_desc()
        |> Repo.all()

      assert [photo2.id, photo3.id, photo1.id] == Enum.map(photos, & &1.id)
    end
  end

  describe "with_album/1" do
    test "preloads album association" do
      album = create_album()
      photo = create_photo(album: album)

      [loaded_photo] =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album.id)
        |> PhotoQuery.with_album()
        |> Repo.all()

      assert loaded_photo.album.id == album.id
      refute %Ecto.Association.NotLoaded{} == loaded_photo.album
    end
  end

  describe "with_preload/2" do
    test "preloads single association" do
      album = create_album()
      photo = create_photo(album: album)

      [loaded_photo] =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album.id)
        |> PhotoQuery.with_preload(:album)
        |> Repo.all()

      assert loaded_photo.album.id == album.id
    end

    test "preloads multiple associations" do
      album = create_album()
      photo = create_photo(album: album)

      [loaded_photo] =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album.id)
        |> PhotoQuery.with_preload([:album])
        |> Repo.all()

      assert loaded_photo.album.id == album.id
    end
  end

  describe "query composition" do
    test "chains multiple filters" do
      album = create_album()
      photo1 = create_photo(album: album, published: true, display_order: 1)
      photo2 = create_photo(album: album, published: true, display_order: 0)
      _photo3 = create_photo(album: album, published: false, display_order: 2)

      photos =
        PhotoQuery.base()
        |> PhotoQuery.by_album(album.id)
        |> PhotoQuery.published()
        |> PhotoQuery.order_by_display_order()
        |> Repo.all()

      assert length(photos) == 2
      assert [photo2.id, photo1.id] == Enum.map(photos, & &1.id)
    end
  end
end
