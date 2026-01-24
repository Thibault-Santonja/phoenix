defmodule Portfolio.Photography.FileStorageHelperTest do
  use Portfolio.DataCase, async: false

  import Mox

  alias Portfolio.Photography.FileStorageHelper
  alias Portfolio.Photography.Storage.MockStorage

  setup :verify_on_exit!

  setup do
    original_config = Application.get_env(:portfolio, :file_storage)
    Application.put_env(:portfolio, :file_storage, backend: MockStorage)

    on_exit(fn ->
      if original_config do
        Application.put_env(:portfolio, :file_storage, original_config)
      else
        Application.delete_env(:portfolio, :file_storage)
      end
    end)

    :ok
  end

  describe "delete_file/1" do
    test "returns {:ok, :ok} when file is successfully deleted" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/test.jpg" -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_file("/photos/test.jpg")
    end

    test "returns {:ok, :ok} when file is not found (orphan-tolerant)" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/missing.jpg" -> {:error, :not_found} end)

      assert {:ok, :ok} = FileStorageHelper.delete_file("/photos/missing.jpg")
    end

    test "returns {:error, reason} when deletion fails with access error" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/no_access.jpg" -> {:error, :eacces} end)

      assert {:error, :eacces} = FileStorageHelper.delete_file("/photos/no_access.jpg")
    end

    test "returns {:error, reason} when deletion fails with permission denied" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/denied.jpg" -> {:error, :permission_denied} end)

      assert {:error, :permission_denied} = FileStorageHelper.delete_file("/photos/denied.jpg")
    end

    test "returns {:error, reason} when deletion fails with IO error" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/io_error.jpg" -> {:error, :io_error} end)

      assert {:error, :io_error} = FileStorageHelper.delete_file("/photos/io_error.jpg")
    end

    test "handles various file path formats" do
      MockStorage
      |> expect(:delete_photo, fn "/uploads/albums/123/photos/456.webp" -> :ok end)

      assert {:ok, :ok} =
               FileStorageHelper.delete_file("/uploads/albums/123/photos/456.webp")
    end
  end

  describe "delete_files/1" do
    test "returns {:ok, :ok} when list is empty" do
      # No mock expectations needed - empty list returns immediately
      assert {:ok, :ok} = FileStorageHelper.delete_files([])
    end

    test "returns {:ok, :ok} when single file is deleted successfully" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/1.jpg" -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_files(["/photos/1.jpg"])
    end

    test "returns {:ok, :ok} when all files are deleted successfully" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/1.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/2.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/3.jpg" -> :ok end)

      result = FileStorageHelper.delete_files(["/photos/1.jpg", "/photos/2.jpg", "/photos/3.jpg"])

      assert {:ok, :ok} = result
    end

    test "returns {:ok, :ok} when some files are not found (orphan-tolerant)" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/1.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/missing.jpg" -> {:error, :not_found} end)
      |> expect(:delete_photo, fn "/photos/3.jpg" -> :ok end)

      result =
        FileStorageHelper.delete_files([
          "/photos/1.jpg",
          "/photos/missing.jpg",
          "/photos/3.jpg"
        ])

      assert {:ok, :ok} = result
    end

    test "returns {:ok, :ok} when all files are not found" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/a.jpg" -> {:error, :not_found} end)
      |> expect(:delete_photo, fn "/photos/b.jpg" -> {:error, :not_found} end)

      assert {:ok, :ok} = FileStorageHelper.delete_files(["/photos/a.jpg", "/photos/b.jpg"])
    end

    test "returns {:error, reason} when one file fails with access error" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/1.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/no_access.jpg" -> {:error, :eacces} end)
      |> expect(:delete_photo, fn "/photos/3.jpg" -> :ok end)

      result =
        FileStorageHelper.delete_files([
          "/photos/1.jpg",
          "/photos/no_access.jpg",
          "/photos/3.jpg"
        ])

      assert {:error, :eacces} = result
    end

    test "returns first error when multiple files fail" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/1.jpg" -> {:error, :eacces} end)
      |> expect(:delete_photo, fn "/photos/2.jpg" -> {:error, :permission_denied} end)

      # Should return the first error encountered (eacces)
      result = FileStorageHelper.delete_files(["/photos/1.jpg", "/photos/2.jpg"])

      assert {:error, :eacces} = result
    end

    test "handles large lists of files" do
      file_paths = Enum.map(1..50, fn i -> "/photos/#{i}.jpg" end)

      MockStorage
      |> expect(:delete_photo, 50, fn _path -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_files(file_paths)
    end
  end

  describe "delete_photo_files/1" do
    test "returns {:ok, :ok} when list is empty" do
      assert {:ok, :ok} = FileStorageHelper.delete_photo_files([])
    end

    test "deletes files from photo structs with file_path field" do
      photos = [
        %{file_path: "/photos/photo1.jpg", id: "1"},
        %{file_path: "/photos/photo2.jpg", id: "2"}
      ]

      MockStorage
      |> expect(:delete_photo, fn "/photos/photo1.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/photo2.jpg" -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_photo_files(photos)
    end

    test "returns {:ok, :ok} when some photos files are missing (orphan-tolerant)" do
      photos = [
        %{file_path: "/photos/exists.jpg", id: "1"},
        %{file_path: "/photos/missing.jpg", id: "2"}
      ]

      MockStorage
      |> expect(:delete_photo, fn "/photos/exists.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/missing.jpg" -> {:error, :not_found} end)

      assert {:ok, :ok} = FileStorageHelper.delete_photo_files(photos)
    end

    test "returns {:error, reason} when file deletion fails" do
      photos = [
        %{file_path: "/photos/ok.jpg", id: "1"},
        %{file_path: "/photos/fail.jpg", id: "2"}
      ]

      MockStorage
      |> expect(:delete_photo, fn "/photos/ok.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/fail.jpg" -> {:error, :permission_denied} end)

      assert {:error, :permission_denied} = FileStorageHelper.delete_photo_files(photos)
    end

    test "handles structs with only file_path field" do
      photos = [
        %{file_path: "/photos/minimal.jpg"}
      ]

      MockStorage
      |> expect(:delete_photo, fn "/photos/minimal.jpg" -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_photo_files(photos)
    end

    test "handles multiple photos with various additional fields" do
      photos = [
        %{file_path: "/photos/1.jpg", id: "uuid-1", title: "Photo 1", order: 1},
        %{file_path: "/photos/2.jpg", id: "uuid-2", title: "Photo 2", order: 2},
        %{file_path: "/photos/3.jpg", id: "uuid-3", title: "Photo 3", order: 3}
      ]

      MockStorage
      |> expect(:delete_photo, fn "/photos/1.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/2.jpg" -> :ok end)
      |> expect(:delete_photo, fn "/photos/3.jpg" -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_photo_files(photos)
    end
  end

  describe "edge cases" do
    test "delete_file handles path with special characters" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/file with spaces.jpg" -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_file("/photos/file with spaces.jpg")
    end

    test "delete_file handles unicode file paths" do
      MockStorage
      |> expect(:delete_photo, fn "/photos/été_2024.jpg" -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_file("/photos/été_2024.jpg")
    end

    test "delete_file handles deeply nested paths" do
      path = "/uploads/albums/user-123/album-456/photos/variants/thumbnail/photo.webp"

      MockStorage
      |> expect(:delete_photo, fn ^path -> :ok end)

      assert {:ok, :ok} = FileStorageHelper.delete_file(path)
    end
  end
end
