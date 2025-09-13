defmodule Portfolio.Photography.Storage.LocalStorageTest do
  use ExUnit.Case, async: false

  alias Portfolio.Photography.Storage.LocalStorage

  setup do
    # Create unique test directory for each test to avoid race conditions in parallel execution
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

  describe "store_photo/2" do
    test "stores a photo with correct filename format", %{test_base_path: test_base_path} do
      # Create a temporary test file
      test_content = "test image content"
      temp_path = create_temp_file(test_content)

      upload = %{
        path: temp_path,
        client_name: "Wedding Photo.jpg",
        client_type: "image/jpeg"
      }

      assert {:ok, metadata} = LocalStorage.store_photo("mariage-2024", upload)

      assert metadata.file_path =~
               ~r|/uploads/albums/mariage-2024/original/wedding-photo-[a-f0-9]{8}\.jpg|

      assert metadata.hash =~ ~r/^[a-f0-9]{8}$/
      assert metadata.original_filename == "Wedding Photo.jpg"

      # Verify file exists on disk
      full_path = Path.join([test_base_path, "albums", "mariage-2024", "original"])
      assert File.exists?(full_path)
      assert [filename] = File.ls!(full_path)
      assert filename =~ ~r/wedding-photo-[a-f0-9]{8}\.jpg/
    end

    test "creates directory structure if it doesn't exist", %{test_base_path: test_base_path} do
      temp_path = create_temp_file("content")

      upload = %{
        path: temp_path,
        client_name: "test.jpg",
        client_type: "image/jpeg"
      }

      assert {:ok, _metadata} = LocalStorage.store_photo("new-album", upload)

      expected_dir = Path.join([test_base_path, "albums", "new-album", "original"])
      assert File.exists?(expected_dir)
      assert File.dir?(expected_dir)
    end

    test "computes correct hash for file" do
      content = "test content for hash"
      temp_path = create_temp_file(content)

      upload = %{
        path: temp_path,
        client_name: "test.jpg",
        client_type: "image/jpeg"
      }

      assert {:ok, metadata1} = LocalStorage.store_photo("album1", upload)
      assert {:ok, metadata2} = LocalStorage.store_photo("album2", upload)

      # Same content should produce same hash
      assert metadata1.hash == metadata2.hash
    end

    test "handles different file types" do
      test_cases = [
        {"image/jpeg", "jpg"},
        {"image/png", "png"},
        {"image/webp", "webp"}
      ]

      for {mime_type, expected_ext} <- test_cases do
        temp_path = create_temp_file("content")

        upload = %{
          path: temp_path,
          client_name: "photo.#{expected_ext}",
          client_type: mime_type
        }

        assert {:ok, metadata} = LocalStorage.store_photo("album", upload)
        assert metadata.file_path =~ ~r/\.#{expected_ext}$/
      end
    end

    test "sanitizes filename with special characters" do
      temp_path = create_temp_file("content")

      upload = %{
        path: temp_path,
        client_name: "Café à Paris & Château!.jpg",
        client_type: "image/jpeg"
      }

      assert {:ok, metadata} = LocalStorage.store_photo("album", upload)
      assert metadata.file_path =~ ~r/caf-paris-ch-teau-[a-f0-9]{8}\.jpg/
    end

    test "truncates long filenames" do
      temp_path = create_temp_file("content")
      long_name = String.duplicate("a", 100) <> ".jpg"

      upload = %{
        path: temp_path,
        client_name: long_name,
        client_type: "image/jpeg"
      }

      assert {:ok, metadata} = LocalStorage.store_photo("album", upload)

      # Extract filename from path
      filename = Path.basename(metadata.file_path)

      # Filename should be: sanitized_name-hash.ext (max 50 for name + 1 dash + 8 hash + 1 dot + 3 ext = 63 total)
      assert String.length(filename) <= 63
    end

    test "uses fallback 'photo' if filename is empty after sanitization" do
      temp_path = create_temp_file("content")

      upload = %{
        path: temp_path,
        client_name: "@@@@.jpg",
        client_type: "image/jpeg"
      }

      assert {:ok, metadata} = LocalStorage.store_photo("album", upload)
      assert metadata.file_path =~ ~r/photo-[a-f0-9]{8}\.jpg/
    end

    test "returns error if source file doesn't exist" do
      upload = %{
        path: "/nonexistent/file.jpg",
        client_name: "test.jpg",
        client_type: "image/jpeg"
      }

      assert {:error, _reason} = LocalStorage.store_photo("album", upload)
    end
  end

  describe "delete_photo/1" do
    test "deletes existing photo file" do
      # First store a photo
      temp_path = create_temp_file("content")

      upload = %{
        path: temp_path,
        client_name: "test.jpg",
        client_type: "image/jpeg"
      }

      {:ok, metadata} = LocalStorage.store_photo("album", upload)

      # Verify file exists
      assert LocalStorage.photo_exists?(metadata.file_path)

      # Delete the photo
      assert :ok = LocalStorage.delete_photo(metadata.file_path)

      # Verify file is gone
      refute LocalStorage.photo_exists?(metadata.file_path)
    end

    test "returns error for non-existent file" do
      assert {:error, :not_found} = LocalStorage.delete_photo("/uploads/nonexistent.jpg")
    end

    test "handles invalid path gracefully" do
      assert {:error, :not_found} = LocalStorage.delete_photo("/invalid/path/photo.jpg")
    end
  end

  describe "photo_exists?/1" do
    test "returns true for existing photo" do
      temp_path = create_temp_file("content")

      upload = %{
        path: temp_path,
        client_name: "test.jpg",
        client_type: "image/jpeg"
      }

      {:ok, metadata} = LocalStorage.store_photo("album", upload)

      assert LocalStorage.photo_exists?(metadata.file_path) == true
    end

    test "returns false for non-existent photo" do
      assert LocalStorage.photo_exists?("/uploads/nonexistent.jpg") == false
    end

    test "returns false for invalid path" do
      assert LocalStorage.photo_exists?("/invalid/path.jpg") == false
    end
  end

  describe "get_photo_path/1" do
    test "returns full path for existing photo", %{test_base_path: test_base_path} do
      temp_path = create_temp_file("content")

      upload = %{
        path: temp_path,
        client_name: "test.jpg",
        client_type: "image/jpeg"
      }

      {:ok, metadata} = LocalStorage.store_photo("album", upload)

      assert {:ok, full_path} = LocalStorage.get_photo_path(metadata.file_path)
      assert String.starts_with?(full_path, test_base_path)
      assert File.exists?(full_path)
    end

    test "returns error for non-existent photo" do
      assert {:error, :not_found} = LocalStorage.get_photo_path("/uploads/nonexistent.jpg")
    end
  end

  # Helper functions

  defp create_temp_file(content) do
    temp_path = Path.join([System.tmp_dir!(), "test-#{:rand.uniform(1_000_000)}.tmp"])
    File.write!(temp_path, content)
    temp_path
  end
end
