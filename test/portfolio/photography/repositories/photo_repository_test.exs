defmodule Portfolio.Photography.Repositories.PhotoRepositoryTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography.{Album, Photo}
  alias Portfolio.Photography.Repositories.PhotoRepository

  describe "list_by_album/1" do
    test "returns all photos for an album sorted by display_order" do
      album = insert_album(%{title: "Test Album", type: :wedding})

      photo1 = insert_photo(album, %{title: "Photo 1", display_order: 2})
      photo2 = insert_photo(album, %{title: "Photo 2", display_order: 0})
      photo3 = insert_photo(album, %{title: "Photo 3", display_order: 1})

      photos = PhotoRepository.list_by_album(album.id)

      assert length(photos) == 3
      assert Enum.at(photos, 0).id == photo2.id
      assert Enum.at(photos, 1).id == photo3.id
      assert Enum.at(photos, 2).id == photo1.id
    end

    test "returns empty list when album has no photos" do
      album = insert_album(%{title: "Empty Album", type: :wedding})

      photos = PhotoRepository.list_by_album(album.id)

      assert photos == []
    end

    test "returns empty list for non-existent album" do
      fake_id = Ecto.UUID.generate()

      photos = PhotoRepository.list_by_album(fake_id)

      assert photos == []
    end

    test "preloads associations when specified" do
      album = insert_album(%{title: "Album", type: :wedding})
      insert_photo(album, %{title: "Photo 1"})

      [photo] = PhotoRepository.list_by_album(album.id, preload: [:album])

      assert photo.album.id == album.id
      refute match?(%Ecto.Association.NotLoaded{}, photo.album)
    end

    test "does not return photos from other albums" do
      album1 = insert_album(%{title: "Album 1", type: :wedding})
      album2 = insert_album(%{title: "Album 2", type: :couples})

      photo1 = insert_photo(album1, %{title: "Photo Album 1"})
      _photo2 = insert_photo(album2, %{title: "Photo Album 2"})

      photos = PhotoRepository.list_by_album(album1.id)

      assert length(photos) == 1
      assert hd(photos).id == photo1.id
    end
  end

  describe "get/1" do
    test "returns {:ok, photo} when photo exists" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Test Photo"})

      assert {:ok, found_photo} = PhotoRepository.get(photo.id)
      assert found_photo.id == photo.id
      assert found_photo.title == "Test Photo"
    end

    test "returns {:error, :not_found} when photo does not exist" do
      fake_id = Ecto.UUID.generate()

      assert {:error, :not_found} = PhotoRepository.get(fake_id)
    end

    test "preloads associations when specified" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo"})

      assert {:ok, loaded_photo} = PhotoRepository.get(photo.id, preload: [:album])

      assert loaded_photo.album.id == album.id
      refute match?(%Ecto.Association.NotLoaded{}, loaded_photo.album)
    end
  end

  describe "get!/1" do
    test "returns photo when exists" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Test Photo"})

      found_photo = PhotoRepository.get!(photo.id)

      assert found_photo.id == photo.id
      assert found_photo.title == "Test Photo"
    end

    test "raises Ecto.NoResultsError when photo does not exist" do
      fake_id = Ecto.UUID.generate()

      assert_raise Ecto.NoResultsError, fn ->
        PhotoRepository.get!(fake_id)
      end
    end

    test "preloads associations when specified" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo"})

      loaded_photo = PhotoRepository.get!(photo.id, preload: [:album])

      assert loaded_photo.album.id == album.id
    end
  end

  describe "insert/1" do
    test "creates photo with valid attributes" do
      album = insert_album(%{title: "Album", type: :wedding})

      attrs = %{
        album_id: album.id,
        original_filename: "sunset.jpg",
        file_path: "/uploads/photos/sunset.jpg",
        title: "Beautiful Sunset",
        description: "A stunning sunset over the ocean",
        display_order: 5,
        hash: "abc123"
      }

      assert {:ok, photo} = PhotoRepository.insert(attrs)
      assert photo.title == "Beautiful Sunset"
      assert photo.original_filename == "sunset.jpg"
      assert photo.display_order == 5
      assert photo.slug == "beautiful-sunset"
    end

    test "returns error with invalid attributes" do
      attrs = %{album_id: nil}

      assert {:error, changeset} = PhotoRepository.insert(attrs)
      refute changeset.valid?
    end

    test "generates slug automatically from title" do
      album = insert_album(%{title: "Album", type: :wedding})

      attrs = %{
        album_id: album.id,
        original_filename: "test.jpg",
        file_path: "/test.jpg",
        title: "Mon Beau Coucher de Soleil"
      }

      assert {:ok, photo} = PhotoRepository.insert(attrs)
      assert photo.slug == "mon-beau-coucher-de-soleil"
    end

    test "sets default values correctly" do
      album = insert_album(%{title: "Album", type: :wedding})

      attrs = %{
        album_id: album.id,
        original_filename: "test.jpg",
        file_path: "/test.jpg"
      }

      assert {:ok, photo} = PhotoRepository.insert(attrs)
      assert photo.published == true
      assert photo.display_order == 0
      assert photo.exif_data == %{}
    end
  end

  describe "update/2" do
    test "updates photo with valid attributes" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Original Title"})

      assert {:ok, updated} = PhotoRepository.update(photo, %{title: "Updated Title"})
      assert updated.title == "Updated Title"
      assert updated.slug == "updated-title"
    end

    test "returns error with invalid attributes" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo"})

      assert {:error, changeset} = PhotoRepository.update(photo, %{display_order: -1})
      refute changeset.valid?
    end

    test "updates published status" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo", published: true})

      assert {:ok, updated} = PhotoRepository.update(photo, %{published: false})
      assert updated.published == false
    end

    test "updates display_order" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo", display_order: 0})

      assert {:ok, updated} = PhotoRepository.update(photo, %{display_order: 10})
      assert updated.display_order == 10
    end
  end

  describe "delete/1" do
    test "deletes photo" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "To Delete"})

      assert {:ok, deleted} = PhotoRepository.delete(photo)
      assert deleted.id == photo.id
      assert {:error, :not_found} = PhotoRepository.get(photo.id)
    end

    test "does not affect other photos in the same album" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo1 = insert_photo(album, %{title: "Photo 1"})
      photo2 = insert_photo(album, %{title: "Photo 2"})

      assert {:ok, _deleted} = PhotoRepository.delete(photo1)

      # Photo 2 should still exist
      assert {:ok, _} = PhotoRepository.get(photo2.id)
      assert length(PhotoRepository.list_by_album(album.id)) == 1
    end
  end

  describe "reorder/2" do
    test "reorders photos correctly" do
      album = insert_album(%{title: "Album", type: :wedding})

      photo1 = insert_photo(album, %{title: "Photo 1", display_order: 0})
      photo2 = insert_photo(album, %{title: "Photo 2", display_order: 1})
      photo3 = insert_photo(album, %{title: "Photo 3", display_order: 2})

      # Reorder: photo3, photo1, photo2
      new_order = [photo3.id, photo1.id, photo2.id]
      assert :ok = PhotoRepository.reorder(album.id, new_order)

      # Verify new order
      photos = PhotoRepository.list_by_album(album.id)
      assert length(photos) == 3
      assert Enum.at(photos, 0).id == photo3.id
      assert Enum.at(photos, 0).display_order == 0
      assert Enum.at(photos, 1).id == photo1.id
      assert Enum.at(photos, 1).display_order == 1
      assert Enum.at(photos, 2).id == photo2.id
      assert Enum.at(photos, 2).display_order == 2
    end

    test "handles single photo reorder" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo", display_order: 5})

      assert :ok = PhotoRepository.reorder(album.id, [photo.id])

      [reordered_photo] = PhotoRepository.list_by_album(album.id)
      assert reordered_photo.display_order == 0
    end

    test "handles empty list" do
      album = insert_album(%{title: "Album", type: :wedding})
      insert_photo(album, %{title: "Photo"})

      assert :ok = PhotoRepository.reorder(album.id, [])
    end

    test "returns error when photo does not belong to album" do
      album1 = insert_album(%{title: "Album 1", type: :wedding})
      album2 = insert_album(%{title: "Album 2", type: :couples})

      photo1 = insert_photo(album1, %{title: "Photo 1"})
      photo2 = insert_photo(album2, %{title: "Photo 2"})

      # Try to reorder album1 with a photo from album2
      assert {:error, :invalid_photos} =
               PhotoRepository.reorder(album1.id, [photo1.id, photo2.id])
    end

    test "returns error when photo ID does not exist" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo"})
      fake_id = Ecto.UUID.generate()

      assert {:error, :invalid_photos} = PhotoRepository.reorder(album.id, [photo.id, fake_id])
    end

    test "does not modify display_order if validation fails" do
      album = insert_album(%{title: "Album", type: :wedding})
      photo = insert_photo(album, %{title: "Photo", display_order: 5})
      fake_id = Ecto.UUID.generate()

      assert {:error, :invalid_photos} = PhotoRepository.reorder(album.id, [photo.id, fake_id])

      # Original display_order should be unchanged
      {:ok, unchanged_photo} = PhotoRepository.get(photo.id)
      assert unchanged_photo.display_order == 5
    end

    test "reorder updates all photos atomically" do
      album = insert_album(%{title: "Album", type: :wedding})

      photos =
        Enum.map(1..5, fn i ->
          insert_photo(album, %{title: "Photo #{i}", display_order: i - 1})
        end)

      # Reverse the order
      reversed_ids = Enum.reverse(Enum.map(photos, & &1.id))

      assert :ok = PhotoRepository.reorder(album.id, reversed_ids)

      # Verify all photos were reordered
      reordered_photos = PhotoRepository.list_by_album(album.id)

      Enum.with_index(reversed_ids)
      |> Enum.each(fn {expected_id, index} ->
        actual_photo = Enum.at(reordered_photos, index)
        assert actual_photo.id == expected_id
        assert actual_photo.display_order == index
      end)
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
      display_order: 0
    }

    merged_attrs = Map.merge(default_attrs, attrs)

    %Photo{}
    |> Photo.changeset(merged_attrs)
    |> Repo.insert!()
  end
end
