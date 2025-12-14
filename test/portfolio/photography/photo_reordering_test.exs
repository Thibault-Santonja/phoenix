defmodule Portfolio.Photography.PhotoReorderingTest do
  @moduledoc """
  Happy path tests for reordering photos in an album.

  These tests verify that:
  - Admin can reorder photos in an album
  - New order persists in database
  - Order is reflected in queries
  """

  use Portfolio.DataCase, async: true

  alias Portfolio.Photography

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "reorder_photos/2" do
    test "successfully reorders photos in album" do
      # Arrange: Create album with 3 photos
      album = create_album(title: "Test Album")

      photo1 = create_photo(album: album, display_order: 0, original_filename: "first.jpg")
      photo2 = create_photo(album: album, display_order: 1, original_filename: "second.jpg")
      photo3 = create_photo(album: album, display_order: 2, original_filename: "third.jpg")

      # Act: Reorder photos (reverse order)
      new_order = [photo3.id, photo2.id, photo1.id]
      assert {:ok, _result} = Photography.reorder_photos(album.id, new_order)

      # Assert: Photos have new display order
      reloaded_photo1 = Photography.get_photo!(photo1.id)
      reloaded_photo2 = Photography.get_photo!(photo2.id)
      reloaded_photo3 = Photography.get_photo!(photo3.id)

      assert reloaded_photo3.display_order == 0
      assert reloaded_photo2.display_order == 1
      assert reloaded_photo1.display_order == 2
    end

    test "new order persists in database" do
      # Arrange: Create album with photos
      album = create_album(title: "Persistent Order")

      photo1 = create_photo(album: album, display_order: 0, original_filename: "a.jpg")
      photo2 = create_photo(album: album, display_order: 1, original_filename: "b.jpg")
      photo3 = create_photo(album: album, display_order: 2, original_filename: "c.jpg")
      photo4 = create_photo(album: album, display_order: 3, original_filename: "d.jpg")

      # Act: Reorder to custom order
      new_order = [photo4.id, photo1.id, photo3.id, photo2.id]
      assert {:ok, _result} = Photography.reorder_photos(album.id, new_order)

      # Assert: Order persists after reload
      photos = Photography.list_photos_by_album(album.id, order_by: :display_order)

      assert length(photos) == 4
      assert Enum.at(photos, 0).id == photo4.id
      assert Enum.at(photos, 1).id == photo1.id
      assert Enum.at(photos, 2).id == photo3.id
      assert Enum.at(photos, 3).id == photo2.id
    end

    test "order reflected in queries" do
      # Arrange: Create album with photos
      album = create_album(title: "Query Order")

      photo1 = create_photo(album: album, display_order: 0, original_filename: "photo1.jpg")
      photo2 = create_photo(album: album, display_order: 1, original_filename: "photo2.jpg")
      photo3 = create_photo(album: album, display_order: 2, original_filename: "photo3.jpg")

      # Act: Change order
      new_order = [photo2.id, photo3.id, photo1.id]
      assert {:ok, _result} = Photography.reorder_photos(album.id, new_order)

      # Assert: list_photos_by_album respects new order
      photos = Photography.list_photos_by_album(album.id, order_by: :display_order)

      assert Enum.at(photos, 0).original_filename == "photo2.jpg"
      assert Enum.at(photos, 1).original_filename == "photo3.jpg"
      assert Enum.at(photos, 2).original_filename == "photo1.jpg"
    end

    test "moving first photo to last position" do
      # Arrange: Create album with 4 photos
      album = create_album(title: "Move First to Last")

      photo1 = create_photo(album: album, display_order: 0, original_filename: "1.jpg")
      photo2 = create_photo(album: album, display_order: 1, original_filename: "2.jpg")
      photo3 = create_photo(album: album, display_order: 2, original_filename: "3.jpg")
      photo4 = create_photo(album: album, display_order: 3, original_filename: "4.jpg")

      # Act: Move first to last
      new_order = [photo2.id, photo3.id, photo4.id, photo1.id]
      assert {:ok, _result} = Photography.reorder_photos(album.id, new_order)

      # Assert: First photo is now last
      photos = Photography.list_photos_by_album(album.id, order_by: :display_order)

      assert Enum.at(photos, 0).original_filename == "2.jpg"
      assert Enum.at(photos, 1).original_filename == "3.jpg"
      assert Enum.at(photos, 2).original_filename == "4.jpg"
      assert Enum.at(photos, 3).original_filename == "1.jpg"
    end

    test "moving last photo to first position" do
      # Arrange: Create album with 4 photos
      album = create_album(title: "Move Last to First")

      photo1 = create_photo(album: album, display_order: 0, original_filename: "1.jpg")
      photo2 = create_photo(album: album, display_order: 1, original_filename: "2.jpg")
      photo3 = create_photo(album: album, display_order: 2, original_filename: "3.jpg")
      photo4 = create_photo(album: album, display_order: 3, original_filename: "4.jpg")

      # Act: Move last to first
      new_order = [photo4.id, photo1.id, photo2.id, photo3.id]
      assert {:ok, _result} = Photography.reorder_photos(album.id, new_order)

      # Assert: Last photo is now first
      photos = Photography.list_photos_by_album(album.id, order_by: :display_order)

      assert Enum.at(photos, 0).original_filename == "4.jpg"
      assert Enum.at(photos, 1).original_filename == "1.jpg"
      assert Enum.at(photos, 2).original_filename == "2.jpg"
      assert Enum.at(photos, 3).original_filename == "3.jpg"
    end

    test "swapping adjacent photos" do
      # Arrange: Create album with photos
      album = create_album(title: "Swap Adjacent")

      photo1 = create_photo(album: album, display_order: 0, original_filename: "a.jpg")
      photo2 = create_photo(album: album, display_order: 1, original_filename: "b.jpg")
      photo3 = create_photo(album: album, display_order: 2, original_filename: "c.jpg")

      # Act: Swap first two photos
      new_order = [photo2.id, photo1.id, photo3.id]
      assert {:ok, _result} = Photography.reorder_photos(album.id, new_order)

      # Assert: Photos swapped
      photos = Photography.list_photos_by_album(album.id, order_by: :display_order)

      assert Enum.at(photos, 0).original_filename == "b.jpg"
      assert Enum.at(photos, 1).original_filename == "a.jpg"
      assert Enum.at(photos, 2).original_filename == "c.jpg"
    end

    test "reordering single photo has no effect" do
      # Arrange: Create album with one photo
      album = create_album(title: "Single Photo")
      photo = create_photo(album: album, display_order: 0, original_filename: "only.jpg")

      # Act: Reorder single photo
      new_order = [photo.id]
      assert {:ok, _result} = Photography.reorder_photos(album.id, new_order)

      # Assert: Photo unchanged
      reloaded = Photography.get_photo!(photo.id)
      assert reloaded.display_order == 0
      assert reloaded.original_filename == "only.jpg"
    end

    test "maintains correct order after multiple reorder operations" do
      # Arrange: Create album with photos
      album = create_album(title: "Multiple Reorders")

      photo1 = create_photo(album: album, display_order: 0, original_filename: "1.jpg")
      photo2 = create_photo(album: album, display_order: 1, original_filename: "2.jpg")
      photo3 = create_photo(album: album, display_order: 2, original_filename: "3.jpg")

      # Act: First reorder
      assert {:ok, _} = Photography.reorder_photos(album.id, [photo3.id, photo2.id, photo1.id])

      # Act: Second reorder
      assert {:ok, _} = Photography.reorder_photos(album.id, [photo2.id, photo1.id, photo3.id])

      # Assert: Final order is correct
      photos = Photography.list_photos_by_album(album.id, order_by: :display_order)

      assert Enum.at(photos, 0).original_filename == "2.jpg"
      assert Enum.at(photos, 1).original_filename == "1.jpg"
      assert Enum.at(photos, 2).original_filename == "3.jpg"
    end
  end
end
