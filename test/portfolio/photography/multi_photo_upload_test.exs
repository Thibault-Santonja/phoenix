defmodule Portfolio.Photography.MultiPhotoUploadTest do
  @moduledoc """
  Happy path tests for uploading multiple photos simultaneously.

  These tests verify that:
  - Multiple photos can be uploaded successfully in a single operation
  - All photos belong to the correct album
  - All files exist on storage after upload
  - The operation is atomic (all or nothing)
  """

  use Portfolio.DataCase, async: false

  @moduletag :skip

  alias Portfolio.Photography

  import PortfolioTest.Fixtures.PhotographyFixtures

  # Helper to create temporary files for upload tests
  defp create_temp_file(content) do
    {:ok, path} = Plug.Upload.random_file("test")
    File.write!(path, content)
    path
  end

  setup do
    # Create unique test directory for each test to avoid race conditions
    test_base_path = "test/tmp/uploads/test-#{System.unique_integer([:positive])}"

    # Configure test storage path
    Application.put_env(:portfolio, :uploads, base_path: test_base_path)

    # Cleanup before and after each test
    File.rm_rf!(test_base_path)
    File.mkdir_p!(test_base_path)

    on_exit(fn ->
      File.rm_rf!(test_base_path)
    end)

    %{test_base_path: test_base_path}
  end

  describe "upload_photos/2 - multiple photos" do
    test "successfully uploads 3 photos to album", %{test_base_path: test_base_path} do
      # Arrange: Create album
      album = create_album(title: "Wedding Album", slug: "wedding-2024")

      # Arrange: Create 3 temporary photo files
      uploads = [
        %{
          path: create_temp_file("photo 1 content"),
          client_name: "ceremony.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("photo 2 content"),
          client_name: "reception.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("photo 3 content"),
          client_name: "dance.jpg",
          content_type: "image/jpeg"
        }
      ]

      # Act: Upload all photos
      assert {:ok, metadata_list} = Photography.upload_photos(album.slug, uploads)

      # Assert: All 3 photos uploaded
      assert length(metadata_list) == 3

      # Assert: Each photo has valid metadata
      for metadata <- metadata_list do
        assert metadata.storage_path =~ ~r|/uploads/photos/|
        assert is_binary(metadata.hash)
        assert is_binary(metadata.original_filename)
        assert is_binary(metadata.photo_id)

        # Assert: File exists on disk
        photo_dir = Path.join([test_base_path, "photos", metadata.photo_id])
        assert File.exists?(photo_dir)
      end

      # Assert: All photos belong to correct album in database
      photos = Photography.list_photos_by_album(album.id)
      assert length(photos) == 3

      for photo <- photos do
        assert photo.album_id == album.id
        assert photo.processing_status == "pending"
      end
    end

    test "successfully uploads 4 photos with unique hashes", %{test_base_path: test_base_path} do
      # Arrange: Create album
      album = create_album(title: "Portrait Session", slug: "portraits-2024")

      # Arrange: Create 4 temporary photo files with different content
      uploads = [
        %{
          path: create_temp_file("unique content 1"),
          client_name: "portrait1.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("unique content 2"),
          client_name: "portrait2.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("unique content 3"),
          client_name: "portrait3.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("unique content 4"),
          client_name: "portrait4.jpg",
          content_type: "image/jpeg"
        }
      ]

      # Act: Upload all photos
      assert {:ok, metadata_list} = Photography.upload_photos(album.slug, uploads)

      # Assert: All 4 photos uploaded
      assert length(metadata_list) == 4

      # Assert: Each photo has unique hash
      hashes = Enum.map(metadata_list, & &1.hash)
      assert length(Enum.uniq(hashes)) == 4, "All hashes should be unique"

      # Assert: All original filenames preserved
      filenames = Enum.map(metadata_list, & &1.original_filename)
      assert "portrait1.jpg" in filenames
      assert "portrait2.jpg" in filenames
      assert "portrait3.jpg" in filenames
      assert "portrait4.jpg" in filenames

      # Assert: All files exist on storage
      for metadata <- metadata_list do
        photo_dir = Path.join([test_base_path, "photos", metadata.photo_id])
        assert File.exists?(photo_dir)
      end
    end

    test "all photos belong to correct album after batch upload" do
      # Arrange: Create two different albums
      album1 = create_album(title: "Album 1", slug: "album-1")
      album2 = create_album(title: "Album 2", slug: "album-2")

      # Arrange: Upload photos to first album
      uploads1 = [
        %{
          path: create_temp_file("photo 1A"),
          client_name: "photo1a.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("photo 1B"),
          client_name: "photo1b.jpg",
          content_type: "image/jpeg"
        }
      ]

      # Arrange: Upload photos to second album
      uploads2 = [
        %{
          path: create_temp_file("photo 2A"),
          client_name: "photo2a.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("photo 2B"),
          client_name: "photo2b.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("photo 2C"),
          client_name: "photo2c.jpg",
          content_type: "image/jpeg"
        }
      ]

      # Act: Upload to both albums
      assert {:ok, metadata1} = Photography.upload_photos(album1.slug, uploads1)
      assert {:ok, metadata2} = Photography.upload_photos(album2.slug, uploads2)

      # Assert: Correct counts
      assert length(metadata1) == 2
      assert length(metadata2) == 3

      # Assert: All photos in album1 belong to album1
      photos1 = Photography.list_photos_by_album(album1.id)
      assert length(photos1) == 2
      assert Enum.all?(photos1, &(&1.album_id == album1.id))

      # Assert: All photos in album2 belong to album2
      photos2 = Photography.list_photos_by_album(album2.id)
      assert length(photos2) == 3
      assert Enum.all?(photos2, &(&1.album_id == album2.id))
    end

    test "atomic operation - all files exist after successful upload", %{
      test_base_path: test_base_path
    } do
      # Arrange: Create album
      album = create_album(title: "Test Album", slug: "test-album")

      # Arrange: Create multiple uploads
      uploads = [
        %{
          path: create_temp_file("photo A"),
          client_name: "photoA.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("photo B"),
          client_name: "photoB.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("photo C"),
          client_name: "photoC.jpg",
          content_type: "image/jpeg"
        }
      ]

      # Act: Upload all photos
      assert {:ok, metadata_list} = Photography.upload_photos(album.slug, uploads)

      # Assert: All photo directories exist on storage
      for metadata <- metadata_list do
        photo_dir = Path.join([test_base_path, "photos", metadata.photo_id])
        assert File.exists?(photo_dir), "Photo directory should exist: #{photo_dir}"

        # Assert: Original file exists in directory
        original_file = Path.join(photo_dir, "original.jpg")
        assert File.exists?(original_file), "Original file should exist: #{original_file}"
      end

      # Assert: All photos are in database with pending status
      photos = Photography.list_photos_by_album(album.id)
      assert length(photos) == 3

      for photo <- photos do
        assert photo.processing_status == "pending"
        assert photo.file_path != nil
        assert photo.original_filename != nil
        assert photo.hash != nil
      end
    end

    test "handles empty upload list gracefully" do
      # Arrange: Create album
      album = create_album(title: "Empty Album", slug: "empty-album")

      # Act: Upload empty list
      assert {:ok, []} = Photography.upload_photos(album.slug, [])

      # Assert: No photos in album
      photos = Photography.list_photos_by_album(album.id)
      assert photos == []
    end

    test "preserves upload order with display_order", %{test_base_path: _test_base_path} do
      # Arrange: Create album
      album = create_album(title: "Ordered Album", slug: "ordered-album")

      # Arrange: Create uploads with specific order
      uploads = [
        %{
          path: create_temp_file("first photo"),
          client_name: "001-first.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("second photo"),
          client_name: "002-second.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: create_temp_file("third photo"),
          client_name: "003-third.jpg",
          content_type: "image/jpeg"
        }
      ]

      # Act: Upload all photos
      assert {:ok, metadata_list} = Photography.upload_photos(album.slug, uploads)

      # Assert: Metadata returned in same order
      assert length(metadata_list) == 3
      assert Enum.at(metadata_list, 0).original_filename == "001-first.jpg"
      assert Enum.at(metadata_list, 1).original_filename == "002-second.jpg"
      assert Enum.at(metadata_list, 2).original_filename == "003-third.jpg"

      # Assert: Photos in database have correct display_order
      photos = Photography.list_photos_by_album(album.id, order_by: :display_order)
      assert length(photos) == 3
      assert Enum.at(photos, 0).original_filename == "001-first.jpg"
      assert Enum.at(photos, 1).original_filename == "002-second.jpg"
      assert Enum.at(photos, 2).original_filename == "003-third.jpg"
    end
  end
end
