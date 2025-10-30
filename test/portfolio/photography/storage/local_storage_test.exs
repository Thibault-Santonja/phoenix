defmodule Portfolio.Photography.Storage.LocalStorageTest do
  @moduledoc """
  Tests for LocalStorage adapter implementing PhotoStorage behaviour.
  """
  use ExUnit.Case, async: false

  alias Portfolio.Photography.Storage.{LocalStorage, PhotoMetadata}

  setup do
    # Create unique test directory for each test
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

  describe "store_photo/2 - PhotoStorage behaviour" do
    test "stores photo and returns PhotoMetadata", %{test_base_path: test_base_path} do
      temp_path = create_test_image()

      upload = %{
        path: temp_path,
        client_name: "wedding-photo.jpg",
        content_type: "image/jpeg"
      }

      assert {:ok, %PhotoMetadata{} = metadata} = LocalStorage.store_photo(upload)

      # Verify metadata fields
      assert is_binary(metadata.photo_id)
      assert byte_size(metadata.photo_id) == 8
      assert is_binary(metadata.hash)
      assert metadata.original_filename == "wedding-photo.jpg"
      assert metadata.content_type == "image/jpeg"
      assert metadata.file_size > 0
      assert String.starts_with?(metadata.storage_path, "/uploads/photos/")
      assert is_integer(metadata.width)
      assert is_integer(metadata.height)

      # Verify file exists on disk in hash-based structure
      photo_dir = Path.join([test_base_path, "photos", metadata.photo_id])
      assert File.exists?(photo_dir)
      assert File.exists?(Path.join(photo_dir, "original.jpg"))
    end

    test "uses hash-based directory structure", %{test_base_path: test_base_path} do
      temp_path = create_test_image()

      upload = %{
        path: temp_path,
        client_name: "test.jpg",
        content_type: "image/jpeg"
      }

      assert {:ok, metadata} = LocalStorage.store_photo(upload)

      # Photo should be in photos/{hash}/ directory
      expected_dir = Path.join([test_base_path, "photos", metadata.photo_id])
      assert File.exists?(expected_dir)
      assert File.dir?(expected_dir)

      # Original should be named "original.{ext}"
      assert File.exists?(Path.join(expected_dir, "original.jpg"))
    end

    test "same content produces same photo_id (deduplication)", %{
      test_base_path: test_base_path
    } do
      content = "identical content"
      temp_path1 = create_temp_file(content)
      temp_path2 = create_temp_file(content)

      upload1 = %{path: temp_path1, client_name: "photo1.jpg", content_type: "image/jpeg"}
      upload2 = %{path: temp_path2, client_name: "photo2.jpg", content_type: "image/jpeg"}

      assert {:ok, metadata1} = LocalStorage.store_photo(upload1)
      assert {:ok, metadata2} = LocalStorage.store_photo(upload2)

      # Same hash, same photo_id
      assert metadata1.hash == metadata2.hash
      assert metadata1.photo_id == metadata2.photo_id

      # Only one directory created (deduplication)
      photo_dir = Path.join([test_base_path, "photos", metadata1.photo_id])
      photos_dir = Path.join(test_base_path, "photos")
      assert length(File.ls!(photos_dir)) == 1
    end

    test "handles different image formats" do
      test_cases = [
        {"image/jpeg", "jpg"},
        {"image/png", "png"},
        {"image/webp", "webp"}
      ]

      for {mime_type, expected_ext} <- test_cases do
        temp_path = create_test_image()

        upload = %{
          path: temp_path,
          client_name: "photo.#{expected_ext}",
          content_type: mime_type
        }

        assert {:ok, metadata} = LocalStorage.store_photo(upload)
        assert String.ends_with?(metadata.storage_path, "/original.#{expected_ext}")
      end
    end

    test "verifies file integrity after copy" do
      temp_path = create_test_image()

      upload = %{
        path: temp_path,
        client_name: "test.jpg",
        content_type: "image/jpeg"
      }

      assert {:ok, metadata} = LocalStorage.store_photo(upload)

      # Hash should be consistent (photo_id is first 8 chars, full hash is longer)
      assert is_binary(metadata.hash)
      assert byte_size(metadata.hash) >= 8
      assert byte_size(metadata.photo_id) == 8
      assert String.starts_with?(metadata.hash, metadata.photo_id)
    end
  end

  describe "delete_photo/1" do
    test "deletes photo directory and all variants", %{test_base_path: test_base_path} do
      # First store a photo
      temp_path = create_test_image()

      upload = %{
        path: temp_path,
        client_name: "test.jpg",
        content_type: "image/jpeg"
      }

      assert {:ok, metadata} = LocalStorage.store_photo(upload)

      # Create some fake variant files
      photo_dir = Path.join([test_base_path, "photos", metadata.photo_id])
      File.write!(Path.join(photo_dir, "thumbnail.webp"), "fake thumbnail")
      File.write!(Path.join(photo_dir, "small.webp"), "fake small")

      # Delete the photo
      assert :ok = LocalStorage.delete_photo(metadata.photo_id)

      # Directory should be gone
      refute File.exists?(photo_dir)
    end

    test "returns :ok for non-existent photo (idempotent)" do
      assert :ok = LocalStorage.delete_photo("nonexistent")
    end
  end

  describe "get_photo_url/2" do
    test "returns URL for existing variant", %{test_base_path: test_base_path} do
      # Store a photo
      temp_path = create_test_image()
      upload = %{path: temp_path, client_name: "test.jpg", content_type: "image/jpeg"}
      assert {:ok, metadata} = LocalStorage.store_photo(upload)

      # Create a fake variant
      photo_dir = Path.join([test_base_path, "photos", metadata.photo_id])
      File.write!(Path.join(photo_dir, "thumbnail.webp"), "fake variant")

      # Get URL
      assert {:ok, url} = LocalStorage.get_photo_url(metadata.photo_id, :thumbnail)
      assert url == "/uploads/photos/#{metadata.photo_id}/thumbnail.webp"
    end

    test "returns error for non-existent variant" do
      temp_path = create_test_image()
      upload = %{path: temp_path, client_name: "test.jpg", content_type: "image/jpeg"}
      assert {:ok, metadata} = LocalStorage.store_photo(upload)

      # Variant doesn't exist
      assert {:error, :not_found} = LocalStorage.get_photo_url(metadata.photo_id, :thumbnail)
    end
  end

  describe "generate_variants/1" do
    test "generates all configured variants", %{test_base_path: test_base_path} do
      # Store a real image
      temp_path = create_test_image()
      upload = %{path: temp_path, client_name: "test.jpg", content_type: "image/jpeg"}
      assert {:ok, metadata} = LocalStorage.store_photo(upload)

      # Generate variants
      assert {:ok, variants} = LocalStorage.generate_variants(metadata.photo_id)

      # Should have all configured variants
      assert Map.has_key?(variants, :thumbnail)
      assert Map.has_key?(variants, :small)
      assert Map.has_key?(variants, :medium)
      assert Map.has_key?(variants, :large)

      # URLs should be correct
      assert variants[:thumbnail] == "/uploads/photos/#{metadata.photo_id}/thumbnail.webp"
      assert variants[:small] == "/uploads/photos/#{metadata.photo_id}/small.webp"

      # Files should exist
      photo_dir = Path.join([test_base_path, "photos", metadata.photo_id])
      assert File.exists?(Path.join(photo_dir, "thumbnail.webp"))
      assert File.exists?(Path.join(photo_dir, "small.webp"))
      assert File.exists?(Path.join(photo_dir, "medium.webp"))
      assert File.exists?(Path.join(photo_dir, "large.webp"))
    end

    test "returns error if original file not found" do
      assert {:error, :file_not_found} = LocalStorage.generate_variants("nonexistent")
    end
  end

  # Helper functions

  defp create_temp_file(content) do
    temp_path = Path.join(System.tmp_dir!(), "test-#{:rand.uniform(100_000)}.tmp")
    File.write!(temp_path, content)
    temp_path
  end

  defp create_test_image do
    # Create a simple black image for testing
    temp_path = Path.join(System.tmp_dir!(), "test-#{:rand.uniform(100_000)}.jpg")
    {:ok, img} = Vix.Vips.Operation.black(100, 100)
    Vix.Vips.Image.write_to_file(img, temp_path)
    temp_path
  end
end
