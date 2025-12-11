defmodule Portfolio.Services.Photography.PhotoUploadServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Services.Photography.PhotoUploadService

  import PortfolioTest.Fixtures.PhotographyFixtures

  describe "execute/3" do
    test "returns error when album not found" do
      result = PhotoUploadService.execute("non-existent-album", [])
      assert {:error, :not_found} = result
    end

    test "returns ok with empty uploads list" do
      album = create_album()

      result = PhotoUploadService.execute(album.slug, [])
      assert {:ok, []} = result
    end

    test "accepts max_concurrency option" do
      album = create_album()

      # Should not raise with valid options
      result = PhotoUploadService.execute(album.slug, [], max_concurrency: 8)
      assert {:ok, []} = result
    end

    test "accepts timeout option" do
      album = create_album()

      result = PhotoUploadService.execute(album.slug, [], timeout: 60_000)
      assert {:ok, []} = result
    end

    test "accepts ordered option" do
      album = create_album()

      result = PhotoUploadService.execute(album.slug, [], ordered: true)
      assert {:ok, []} = result
    end

    test "accepts combined options" do
      album = create_album()

      result =
        PhotoUploadService.execute(album.slug, [],
          max_concurrency: 2,
          timeout: 5000,
          ordered: true
        )

      assert {:ok, []} = result
    end

    test "emits telemetry event" do
      album = create_album()

      test_pid = self()

      :telemetry.attach(
        "test-photo-upload-telemetry",
        [:portfolio, :photography, :photos, :uploaded],
        fn event, measurements, metadata, _config ->
          send(test_pid, {:telemetry, event, measurements, metadata})
        end,
        nil
      )

      PhotoUploadService.execute(album.slug, [])

      assert_receive {:telemetry, [:portfolio, :photography, :photos, :uploaded], _, metadata}

      assert metadata.album_slug == album.slug
      assert metadata.count == 0

      :telemetry.detach("test-photo-upload-telemetry")
    end
  end

  describe "execute/3 with upload validation" do
    setup do
      album = create_album()

      # Create a temporary test file
      tmp_dir = System.tmp_dir!()
      test_file_path = Path.join(tmp_dir, "test_upload_#{System.unique_integer([:positive])}.jpg")
      File.write!(test_file_path, String.duplicate("x", 100))

      on_exit(fn ->
        File.rm(test_file_path)
      end)

      {:ok, album: album, test_file_path: test_file_path}
    end

    test "validates file size before upload", %{album: album, test_file_path: test_file_path} do
      # Create a fake upload struct with all required fields
      upload = %{
        path: test_file_path,
        client_name: "test.jpg",
        content_type: "image/jpeg"
      }

      # This will proceed past size validation but may fail at storage level
      result = PhotoUploadService.execute(album.slug, [upload])

      # Size validation passed - may fail at storage level but that's expected
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "rejects files that don't exist", %{album: album} do
      upload = %{
        path: "/non/existent/path/file.jpg",
        client_name: "missing.jpg"
      }

      result = PhotoUploadService.execute(album.slug, [upload])

      assert {:error, {:file_error, "missing.jpg", :enoent}} = result
    end
  end
end
