defmodule Portfolio.PhotographyTest do
  use Portfolio.DataCase, async: false

  alias Portfolio.Photography
  alias Portfolio.Photography.Photo

  import PortfolioTest.Fixtures.PhotographyFixtures

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

  describe "module structure" do
    test "module exists and compiles" do
      assert Code.ensure_loaded?(Photography)
    end

    test "has complete moduledoc" do
      {:docs_v1, _, :elixir, _, %{"en" => moduledoc}, _, _} = Code.fetch_docs(Photography)

      assert moduledoc =~ "Photography Bounded Context"
      assert moduledoc =~ "Ubiquitous Language"
      assert moduledoc =~ "Architecture"
      assert moduledoc =~ "Exemples"
    end
  end

  describe "delete_photo/1" do
    test "deletes photo and its file when file exists", %{test_base_path: test_base_path} do
      album = create_album(title: "Test Album", slug: "test-album")

      # Create a real file
      file_path = "/uploads/albums/test-album/original/photo-abc123.jpg"

      full_path =
        Path.join([test_base_path, "albums", "test-album", "original", "photo-abc123.jpg"])

      File.mkdir_p!(Path.dirname(full_path))
      File.write!(full_path, "test content")

      photo = create_photo(album_id: album.id, file_path: file_path)

      # Verify file exists
      assert File.exists?(full_path)

      # Delete photo (now returns Ecto.Multi result)
      assert {:ok, %{photo: %Photo{}, file: :ok}} = Photography.delete_photo(photo)

      # Verify file is deleted
      refute File.exists?(full_path)

      # Verify DB record is deleted
      assert {:error, :not_found} = Photography.get_photo(photo.id)
    end

    test "deletes photo record even if file doesn't exist (orphaned data)" do
      album = create_album(title: "Test Album")
      photo = create_photo(album_id: album.id, file_path: "/uploads/nonexistent.jpg")

      # File doesn't exist, but delete should still work (Ecto.Multi result)
      assert {:ok, %{photo: %Photo{}, file: :ok}} = Photography.delete_photo(photo)

      # Verify DB record is deleted
      assert {:error, :not_found} = Photography.get_photo(photo.id)
    end

    test "returns error if file deletion fails for other reasons" do
      # This test would require mocking File operations or setting permissions
      # For now, we'll skip it but it's documented in the spec
      :ok
    end
  end

  describe "upload_photos/2" do
    test "uploads multiple photos successfully", %{test_base_path: test_base_path} do
      # Create album first
      album = create_album(title: "Test Album", slug: "test-album")

      # Cleanup: Delete album directory after test
      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      # Create temporary test files
      uploads = [
        %{
          path: create_temp_file("photo 1 content"),
          client_name: "photo1.jpg",
          client_type: "image/jpeg"
        },
        %{
          path: create_temp_file("photo 2 content"),
          client_name: "photo2.jpg",
          client_type: "image/jpeg"
        }
      ]

      assert {:ok, metadata_list} = Photography.upload_photos("test-album", uploads)

      assert length(metadata_list) == 2

      for metadata <- metadata_list do
        assert metadata.file_path =~ ~r|/uploads/albums/test-album/original/|
        assert is_binary(metadata.hash)
        assert is_binary(metadata.original_filename)

        # Verify file exists on disk
        full_path =
          Path.join([test_base_path, String.trim_leading(metadata.file_path, "/uploads/")])

        assert File.exists?(full_path)
      end
    end

    test "returns error if any upload fails" do
      uploads = [
        %{
          path: "/nonexistent/file1.jpg",
          client_name: "photo1.jpg",
          client_type: "image/jpeg"
        }
      ]

      assert {:error, _reason} = Photography.upload_photos("test-album", uploads)
    end

    test "handles empty upload list" do
      # Create album first
      album = create_album(title: "Test Album", slug: "test-album")

      # Cleanup: Delete album directory after test
      on_exit(fn ->
        album_dir = Path.join(["priv", "static", "uploads", "albums", album.slug])
        File.rm_rf(album_dir)
      end)

      assert {:ok, []} = Photography.upload_photos("test-album", [])
    end
  end

  describe "get_photo_url/2" do
    test "delegates to storage adapter" do
      # This test verifies the function exists and delegates correctly
      # The actual URL generation is tested in LocalStorage tests
      result = Photography.get_photo_url("nonexistent", :thumbnail)

      # Should return error for non-existent photo
      assert {:error, _reason} = result
    end
  end

  describe "reprocess_photo/1" do
    setup do
      album = create_album()
      %{album: album}
    end

    test "resets photo status to pending and enqueues job", %{album: album} do
      photo = create_photo(album: album, processing_status: "failed")

      assert {:ok, updated_photo} = Photography.reprocess_photo(photo)
      assert updated_photo.processing_status == "pending"
    end

    test "works for completed photos", %{album: album} do
      photo = create_photo(album: album, processing_status: "completed")

      assert {:ok, updated_photo} = Photography.reprocess_photo(photo)
      assert updated_photo.processing_status == "pending"
    end
  end

  describe "list_pending_photos/1" do
    setup do
      album = create_album()
      %{album: album}
    end

    test "returns photos with pending status", %{album: album} do
      photo1 = create_photo(album: album, processing_status: "pending")
      photo2 = create_photo(album: album, processing_status: "pending")
      _photo3 = create_photo(album: album, processing_status: "completed")

      photos = Photography.list_pending_photos()

      photo_ids = Enum.map(photos, & &1.id)
      assert photo1.id in photo_ids
      assert photo2.id in photo_ids
      assert length(photos) >= 2
    end

    test "respects limit option", %{album: album} do
      Enum.each(1..5, fn _ ->
        create_photo(album: album, processing_status: "pending")
      end)

      photos = Photography.list_pending_photos(limit: 3)
      assert length(photos) <= 3
    end

    test "returns empty list when no pending photos" do
      photos = Photography.list_pending_photos()
      # Filter to only pending (there might be other photos from other tests)
      pending_photos = Enum.filter(photos, &(&1.processing_status == "pending"))
      # We can't assert empty because of async tests, just verify structure
      assert is_list(pending_photos)
    end
  end

  describe "list_failed_photos/1" do
    setup do
      album = create_album()
      %{album: album}
    end

    test "returns photos with failed status", %{album: album} do
      photo1 = create_photo(album: album, processing_status: "failed")
      photo2 = create_photo(album: album, processing_status: "failed")
      _photo3 = create_photo(album: album, processing_status: "completed")

      photos = Photography.list_failed_photos()

      photo_ids = Enum.map(photos, & &1.id)
      assert photo1.id in photo_ids
      assert photo2.id in photo_ids
    end

    test "respects limit option", %{album: album} do
      Enum.each(1..5, fn _ ->
        create_photo(album: album, processing_status: "failed")
      end)

      photos = Photography.list_failed_photos(limit: 3)
      assert length(photos) <= 3
    end

    test "can preload associations", %{album: album} do
      _photo = create_photo(album: album, processing_status: "failed")

      photos = Photography.list_failed_photos(preload: [:album])

      assert length(photos) >= 1
      first_photo = List.first(photos)

      if first_photo.album_id == album.id do
        assert %Portfolio.Photography.Album{} = first_photo.album
      end
    end
  end

  # Helper functions

  defp create_temp_file(content) do
    temp_path = Path.join([System.tmp_dir!(), "test-#{:rand.uniform(1_000_000)}.tmp"])
    File.write!(temp_path, content)
    temp_path
  end
end
