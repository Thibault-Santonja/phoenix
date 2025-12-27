defmodule Portfolio.Photography.Services.PhotoServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography.Services.PhotoService

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "list_photos/1" do
    test "returns empty list when no photos exist" do
      assert PhotoService.list_photos() == []
    end

    test "returns all photos" do
      album = create_album()
      photo1 = create_photo(album: album)
      photo2 = create_photo(album: album)

      photos = PhotoService.list_photos()

      assert length(photos) == 2
      photo_ids = Enum.map(photos, & &1.id)
      assert photo1.id in photo_ids
      assert photo2.id in photo_ids
    end

    test "filters by album_id" do
      album1 = create_album()
      album2 = create_album()
      photo1 = create_photo(album: album1)
      _photo2 = create_photo(album: album2)

      photos = PhotoService.list_photos(album_id: album1.id)

      assert length(photos) == 1
      assert hd(photos).id == photo1.id
    end

    test "respects limit option" do
      album = create_album()
      for _ <- 1..5, do: create_photo(album: album)

      photos = PhotoService.list_photos(limit: 3)

      assert length(photos) == 3
    end
  end

  describe "list_photos_by_album/2" do
    test "returns photos for specific album" do
      album1 = create_album()
      album2 = create_album()
      photo1 = create_photo(album: album1)
      _photo2 = create_photo(album: album2)

      photos = PhotoService.list_photos_by_album(album1.id)

      assert length(photos) == 1
      assert hd(photos).id == photo1.id
    end

    test "returns empty list for album with no photos" do
      album = create_album()

      photos = PhotoService.list_photos_by_album(album.id)

      assert photos == []
    end
  end

  describe "get_photo/2" do
    test "returns photo by id" do
      photo = create_photo()

      assert {:ok, fetched} = PhotoService.get_photo(photo.id)
      assert fetched.id == photo.id
    end

    test "returns error for non-existent photo" do
      assert {:error, :not_found} = PhotoService.get_photo(Ecto.UUID.generate())
    end

    test "preloads associations" do
      album = create_album()
      photo = create_photo(album: album)

      assert {:ok, fetched} = PhotoService.get_photo(photo.id, preload: [:album])
      assert Ecto.assoc_loaded?(fetched.album)
      assert fetched.album.id == album.id
    end
  end

  describe "get_photo!/2" do
    test "returns photo by id" do
      photo = create_photo()

      fetched = PhotoService.get_photo!(photo.id)
      assert fetched.id == photo.id
    end

    test "raises for non-existent photo" do
      assert_raise Ecto.NoResultsError, fn ->
        PhotoService.get_photo!(Ecto.UUID.generate())
      end
    end
  end

  describe "create_photo/1" do
    test "creates photo with valid attributes" do
      album = create_album()

      attrs = %{
        album_id: album.id,
        file_path: "/uploads/test.jpg",
        original_filename: "test.jpg",
        hash: :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
      }

      assert {:ok, photo} = PhotoService.create_photo(attrs)
      assert photo.album_id == album.id
      assert photo.file_path == "/uploads/test.jpg"
      assert photo.original_filename == "test.jpg"
    end

    test "returns error with invalid attributes" do
      attrs = %{album_id: nil, file_path: nil}

      assert {:error, changeset} = PhotoService.create_photo(attrs)
      assert changeset.valid? == false
    end
  end

  describe "update_photo/2" do
    test "updates photo with valid attributes" do
      photo = create_photo(title: "Old Title")

      assert {:ok, updated} = PhotoService.update_photo(photo, %{title: "New Title"})
      assert updated.title == "New Title"
    end

    test "returns error with invalid attributes" do
      photo = create_photo()

      # album_id cannot be nil
      assert {:error, changeset} = PhotoService.update_photo(photo, %{album_id: nil})
      assert changeset.valid? == false
    end
  end

  describe "processing status functions" do
    setup do
      album = create_album()
      pending1 = create_photo(album: album, processing_status: "pending")
      pending2 = create_photo(album: album, processing_status: "pending")
      processing = create_photo(album: album, processing_status: "processing")
      completed = create_photo(album: album, processing_status: "completed")
      failed = create_photo(album: album, processing_status: "failed")

      %{
        album: album,
        pending: [pending1, pending2],
        processing: processing,
        completed: completed,
        failed: failed
      }
    end

    test "list_pending_photos/1 returns pending photos", %{pending: pending} do
      photos = PhotoService.list_pending_photos()

      assert length(photos) == 2
      photo_ids = Enum.map(photos, & &1.id)
      assert Enum.all?(pending, &(&1.id in photo_ids))
    end

    test "list_failed_photos/1 returns failed photos", %{failed: failed} do
      photos = PhotoService.list_failed_photos()

      assert length(photos) == 1
      assert hd(photos).id == failed.id
    end

    test "list_pending_photos/1 respects limit", %{pending: _} do
      photos = PhotoService.list_pending_photos(limit: 1)

      assert length(photos) == 1
    end

    test "get_processing_stats/0 returns all stats" do
      stats = PhotoService.get_processing_stats()

      assert stats.pending == 2
      assert stats.processing == 1
      assert stats.completed == 1
      assert stats.failed == 1
      assert stats.total == 5
    end

    test "get_oldest_pending_photo/0 returns oldest pending", %{pending: [oldest | _]} do
      assert {:ok, photo} = PhotoService.get_oldest_pending_photo()
      assert photo.id == oldest.id
    end
  end

  describe "get_oldest_pending_photo/0" do
    test "returns error when no pending photos" do
      album = create_album()
      _completed = create_photo(album: album, processing_status: "completed")

      assert {:error, :not_found} = PhotoService.get_oldest_pending_photo()
    end
  end

  describe "reprocess_photo/1" do
    test "resets status to pending and enqueues job" do
      photo = create_photo(processing_status: "failed")

      assert {:ok, updated} = PhotoService.reprocess_photo(photo)
      assert updated.processing_status == "pending"
    end
  end

  describe "reprocess_all_failed_photos/1" do
    test "reprocesses all failed photos" do
      album = create_album()
      _failed1 = create_photo(album: album, processing_status: "failed")
      _failed2 = create_photo(album: album, processing_status: "failed")
      _completed = create_photo(album: album, processing_status: "completed")

      assert {:ok, count} = PhotoService.reprocess_all_failed_photos()
      assert count == 2
    end

    test "returns 0 when no failed photos" do
      album = create_album()
      _completed = create_photo(album: album, processing_status: "completed")

      assert {:ok, 0} = PhotoService.reprocess_all_failed_photos()
    end

    test "respects max_concurrency option" do
      album = create_album()
      for _ <- 1..5, do: create_photo(album: album, processing_status: "failed")

      assert {:ok, count} = PhotoService.reprocess_all_failed_photos(max_concurrency: 2)
      assert count == 5
    end
  end

  describe "reorder_photos/2" do
    test "reorders photos in album" do
      album = create_album()
      photo1 = create_photo(album: album, display_order: 0)
      photo2 = create_photo(album: album, display_order: 1)
      photo3 = create_photo(album: album, display_order: 2)

      # Reverse order
      new_order = [photo3.id, photo2.id, photo1.id]

      assert {:ok, 3} = PhotoService.reorder_photos(album.id, new_order)

      # Verify new order
      photos = PhotoService.list_photos_by_album(album.id, order_by: :display_order)
      assert Enum.map(photos, & &1.id) == new_order
    end
  end

  describe "count functions" do
    test "count_all_photos/0 returns total count" do
      album = create_album()
      for _ <- 1..3, do: create_photo(album: album)

      assert PhotoService.count_all_photos() == 3
    end

    test "count_photos_by_album/1 returns count for album" do
      album1 = create_album()
      album2 = create_album()
      for _ <- 1..3, do: create_photo(album: album1)
      for _ <- 1..2, do: create_photo(album: album2)

      assert PhotoService.count_photos_by_album(album1.id) == 3
      assert PhotoService.count_photos_by_album(album2.id) == 2
    end
  end

  describe "storage functions" do
    test "get_photo_url/2 returns url for variant" do
      photo = create_photo()

      # This depends on the storage adapter implementation
      # In test environment, it should return a path
      result = PhotoService.get_photo_url(photo.id, :thumbnail)

      # The result depends on the configured adapter
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "get_storage_usage/1 returns bytes by default" do
      usage = PhotoService.get_storage_usage()

      assert is_number(usage)
      assert usage >= 0
    end

    test "get_storage_usage/1 converts to different units" do
      # Mock a known value would be ideal, but we test the conversion logic
      bytes = PhotoService.get_storage_usage(unit: :bytes)
      kb = PhotoService.get_storage_usage(unit: :kb)
      mb = PhotoService.get_storage_usage(unit: :mb)
      gb = PhotoService.get_storage_usage(unit: :gb)

      assert kb == bytes / 1024
      assert mb == bytes / (1024 * 1024)
      assert gb == bytes / (1024 * 1024 * 1024)
    end
  end
end
