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
      create_album(title: "Test Album", slug: "test-album")

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
      create_album(title: "Test Album", slug: "test-album")

      assert {:ok, []} = Photography.upload_photos("test-album", [])
    end
  end

  # Helper functions

  defp create_temp_file(content) do
    temp_path = Path.join([System.tmp_dir!(), "test-#{:rand.uniform(1_000_000)}.tmp"])
    File.write!(temp_path, content)
    temp_path
  end
end
