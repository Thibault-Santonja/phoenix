defmodule Portfolio.Services.Photography.PhotoUploadServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Photography
  alias Portfolio.Services.Photography.PhotoUploadService

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "execute/3" do
    setup do
      album = create_album(slug: "test-album-#{System.unique_integer([:positive])}")

      # Cleanup: Delete album directory after test
      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      %{album: album}
    end

    test "uploads single photo successfully", %{album: album} do
      uploads = [
        %{
          path: "test/fixtures/test_image.jpg",
          client_name: "photo1.jpg",
          content_type: "image/jpeg"
        }
      ]

      assert {:ok, metadata_list} = PhotoUploadService.execute(album.slug, uploads)
      assert length(metadata_list) == 1

      [metadata] = metadata_list
      assert metadata.original_filename == "photo1.jpg"
      assert metadata.hash != nil
      assert metadata.storage_path != nil
      assert String.starts_with?(metadata.storage_path, "/uploads/photos/")

      # Verify photo was created in database
      photos = Photography.list_photos_by_album(album.id)
      assert length(photos) == 1
    end

    test "returns error when album not found" do
      uploads = [
        %{
          path: "test/fixtures/test_image.jpg",
          client_name: "photo.jpg",
          content_type: "image/jpeg"
        }
      ]

      assert {:error, :not_found} = PhotoUploadService.execute("nonexistent-album", uploads)
    end

    test "handles duplicate hash by returning database error" do
      album = create_album(slug: "rollback-test-#{System.unique_integer([:positive])}")

      # Cleanup: Delete album directory after test
      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      uploads = [
        %{
          path: "test/fixtures/test_image.jpg",
          client_name: "valid.jpg",
          content_type: "image/jpeg"
        }
      ]

      # First upload should succeed
      assert {:ok, _metadata} = PhotoUploadService.execute(album.slug, uploads)

      # Second upload with same file should fail due to unique hash constraint
      # and should rollback the file upload
      assert {:error, changeset} = PhotoUploadService.execute(album.slug, uploads)
      assert changeset.errors[:hash] != nil

      # Only first photo should exist in database
      photos = Photography.list_photos_by_album(album.id)
      assert length(photos) == 1
    end

    test "handles empty upload list" do
      album = create_album(slug: "empty-test-#{System.unique_integer([:positive])}")

      # Cleanup: Delete album directory after test
      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      assert {:ok, []} = PhotoUploadService.execute(album.slug, [])
    end
  end
end
