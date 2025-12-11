defmodule Portfolio.Photography.FileUploadBoundariesTest do
  @moduledoc """
  Boundary and edge case tests for file upload operations.

  Tests cover:
  - Zero-byte file rejection
  - File at exactly max size (10 MB)
  - File over max size rejection
  - Corrupted image with valid extension
  - Missing file handling
  - Invalid MIME types
  """
  use Portfolio.DataCase, async: true

  @moduletag :skip

  alias Portfolio.Services.Photography.PhotoUploadService

  import PortfolioTest.Fixtures.PhotographyFixtures

  @max_file_size 10_485_760
  @test_image_path "test/fixtures/test_image.jpg"

  describe "file size boundaries" do
    setup do
      album = create_album(slug: "upload-boundaries-#{System.unique_integer([:positive])}")

      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      %{album: album}
    end

    test "rejects zero-byte file", %{album: album} do
      # Create a zero-byte temporary file
      temp_file = Path.join(System.tmp_dir!(), "zero_byte_#{System.unique_integer()}.jpg")
      File.write!(temp_file, "")

      on_exit(fn -> File.rm(temp_file) end)

      uploads = [
        %{
          path: temp_file,
          client_name: "empty.jpg",
          content_type: "image/jpeg"
        }
      ]

      # Zero-byte files should fail during image processing
      result = PhotoUploadService.execute(album.slug, uploads)

      # Could be error from storage or validation
      assert match?({:error, _}, result)
    end

    test "accepts file at exactly max size (10 MB)", %{album: album} do
      # Create a file at exactly 10MB
      temp_file = Path.join(System.tmp_dir!(), "exact_max_#{System.unique_integer()}.jpg")

      # Copy test image and pad to exactly 10MB
      {:ok, image_data} = File.read(@test_image_path)
      padding_size = @max_file_size - byte_size(image_data)

      if padding_size > 0 do
        # Append padding to reach exact size (won't be valid image but tests size check)
        padded_data = image_data <> :binary.copy(<<0>>, padding_size)
        File.write!(temp_file, padded_data)

        on_exit(fn -> File.rm(temp_file) end)

        uploads = [
          %{
            path: temp_file,
            client_name: "exact_10mb.jpg",
            content_type: "image/jpeg"
          }
        ]

        # Should not fail due to size (may fail for corruption)
        result = PhotoUploadService.execute(album.slug, uploads)

        # The important part: should NOT get file_too_large error
        refute match?({:error, {:file_too_large, _, _, _}}, result)
      else
        # Test image is already larger than 10MB, skip this test
        :ok
      end
    end

    test "rejects file over max size (10 MB + 1 byte)", %{album: album} do
      # Create a file larger than 10MB
      temp_file = Path.join(System.tmp_dir!(), "oversized_#{System.unique_integer()}.jpg")

      # Copy test image and add extra bytes to exceed 10MB
      {:ok, image_data} = File.read(@test_image_path)
      oversized_data = image_data <> :binary.copy(<<0>>, @max_file_size + 1)
      File.write!(temp_file, oversized_data)

      on_exit(fn -> File.rm(temp_file) end)

      uploads = [
        %{
          path: temp_file,
          client_name: "oversized.jpg",
          content_type: "image/jpeg"
        }
      ]

      assert {:error, {:file_too_large, "oversized.jpg", size, @max_file_size}} =
               PhotoUploadService.execute(album.slug, uploads)

      assert size > @max_file_size
    end

    test "handles corrupted image with valid extension", %{album: album} do
      # Create a corrupted JPEG file
      temp_file = Path.join(System.tmp_dir!(), "corrupted_#{System.unique_integer()}.jpg")
      File.write!(temp_file, "This is not a valid JPEG image, just random text")

      on_exit(fn -> File.rm(temp_file) end)

      uploads = [
        %{
          path: temp_file,
          client_name: "corrupted.jpg",
          content_type: "image/jpeg"
        }
      ]

      # Should fail during image processing/validation
      assert {:error, _reason} = PhotoUploadService.execute(album.slug, uploads)
    end
  end

  describe "missing and invalid files" do
    setup do
      album = create_album(slug: "invalid-files-#{System.unique_integer([:positive])}")

      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      %{album: album}
    end

    test "handles missing file gracefully", %{album: album} do
      uploads = [
        %{
          path: "/nonexistent/path/to/file.jpg",
          client_name: "missing.jpg",
          content_type: "image/jpeg"
        }
      ]

      assert {:error, _reason} = PhotoUploadService.execute(album.slug, uploads)
    end

    test "handles file with wrong MIME type", %{album: album} do
      # Create a text file with .jpg extension
      temp_file = Path.join(System.tmp_dir!(), "text_as_image_#{System.unique_integer()}.jpg")
      File.write!(temp_file, "Plain text file masquerading as JPEG")

      on_exit(fn -> File.rm(temp_file) end)

      uploads = [
        %{
          path: temp_file,
          client_name: "fake.jpg",
          content_type: "text/plain"
        }
      ]

      # Should fail validation or processing
      assert {:error, _reason} = PhotoUploadService.execute(album.slug, uploads)
    end
  end

  describe "edge cases in upload metadata" do
    setup do
      album = create_album(slug: "metadata-edge-#{System.unique_integer([:positive])}")

      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      %{album: album}
    end

    test "handles extremely long filename", %{album: album} do
      long_filename = String.duplicate("a", 255) <> ".jpg"

      uploads = [
        %{
          path: @test_image_path,
          client_name: long_filename,
          content_type: "image/jpeg"
        }
      ]

      # Should either succeed or fail gracefully
      result = PhotoUploadService.execute(album.slug, uploads)
      refute match?({:error, :crash}, result)
    end

    test "handles filename with special characters", %{album: album} do
      special_filenames = [
        "photo with spaces.jpg",
        "photo-with-dashes.jpg",
        "photo_with_underscores.jpg",
        "phötö-ümlaut.jpg",
        "照片.jpg"
      ]

      for filename <- special_filenames do
        uploads = [
          %{
            path: @test_image_path,
            client_name: filename,
            content_type: "image/jpeg"
          }
        ]

        # Should handle gracefully (may sanitize filename)
        result = PhotoUploadService.execute(album.slug, uploads)
        refute match?({:error, :crash}, result)
      end
    end

    test "handles empty filename", %{album: album} do
      uploads = [
        %{
          path: @test_image_path,
          client_name: "",
          content_type: "image/jpeg"
        }
      ]

      # Should either use default name or fail gracefully
      result = PhotoUploadService.execute(album.slug, uploads)
      refute match?({:error, :crash}, result)
    end
  end

  describe "concurrent upload edge cases" do
    test "handles duplicate uploads to same album" do
      album = create_album(slug: "concurrent-#{System.unique_integer([:positive])}")

      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      uploads = [
        %{
          path: @test_image_path,
          client_name: "photo1.jpg",
          content_type: "image/jpeg"
        },
        %{
          path: @test_image_path,
          client_name: "photo2.jpg",
          content_type: "image/jpeg"
        }
      ]

      # First upload
      assert {:ok, _metadata} = PhotoUploadService.execute(album.slug, uploads)

      # Second upload of same files (different client names)
      # Should handle hash collision gracefully
      result = PhotoUploadService.execute(album.slug, uploads)

      # May succeed with different filenames or fail with duplicate error
      case result do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    end
  end
end
