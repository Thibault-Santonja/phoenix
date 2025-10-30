defmodule Portfolio.Photography.Storage.PhotoStorageTest do
  @moduledoc """
  Tests for the PhotoStorage behaviour contract.

  These tests validate that the behaviour module compiles correctly,
  has proper typespecs, and documentation. Actual implementation tests
  are in the adapter-specific test files (e.g., local_storage_test.exs).
  """
  use ExUnit.Case, async: true

  alias Portfolio.Photography.Storage.PhotoMetadata
  alias Portfolio.Photography.Storage.PhotoStorage

  describe "behaviour definition" do
    test "defines required callbacks" do
      callbacks = PhotoStorage.behaviour_info(:callbacks)

      assert {:store_photo, 2} in callbacks
      assert {:delete_photo, 1} in callbacks
      assert {:get_photo_url, 2} in callbacks
      assert {:generate_variants, 1} in callbacks
    end

    test "callback count is correct" do
      callbacks = PhotoStorage.behaviour_info(:callbacks)
      assert length(callbacks) == 4
    end
  end

  describe "PhotoMetadata struct" do
    test "enforces required keys" do
      assert_raise ArgumentError, fn ->
        struct!(PhotoMetadata, %{})
      end
    end

    test "creates struct with required fields" do
      metadata = %PhotoMetadata{
        photo_id: "a3f2b8c4",
        hash: "a3f2b8c4f1e9d2a7c5b8d4a1e3f7c9d2",
        original_filename: "test.jpg",
        content_type: "image/jpeg",
        file_size: 1024,
        storage_path: "/uploads/photos/a3f2b8c4/original.jpg"
      }

      assert metadata.photo_id == "a3f2b8c4"
      assert metadata.hash == "a3f2b8c4f1e9d2a7c5b8d4a1e3f7c9d2"
      assert metadata.original_filename == "test.jpg"
      assert metadata.content_type == "image/jpeg"
      assert metadata.file_size == 1024
      assert metadata.storage_path == "/uploads/photos/a3f2b8c4/original.jpg"
    end

    test "accepts optional fields" do
      metadata = %PhotoMetadata{
        photo_id: "a3f2b8c4",
        hash: "a3f2b8c4f1e9d2a7",
        original_filename: "test.jpg",
        content_type: "image/jpeg",
        file_size: 1024,
        storage_path: "/uploads/test.jpg",
        width: 1920,
        height: 1080,
        stored_at: ~U[2024-01-15 10:30:00Z]
      }

      assert metadata.width == 1920
      assert metadata.height == 1080
      assert metadata.stored_at == ~U[2024-01-15 10:30:00Z]
    end

    test "new/1 creates metadata with current timestamp" do
      metadata =
        PhotoMetadata.new(%{
          photo_id: "a3f2b8c4",
          hash: "a3f2b8c4f1e9d2a7",
          original_filename: "test.jpg",
          content_type: "image/jpeg",
          file_size: 1024,
          storage_path: "/uploads/test.jpg"
        })

      assert %DateTime{} = metadata.stored_at
      # Should be within last second
      assert DateTime.diff(DateTime.utc_now(), metadata.stored_at) < 1
    end

    test "new/1 respects provided stored_at" do
      timestamp = ~U[2024-01-15 10:30:00Z]

      metadata =
        PhotoMetadata.new(%{
          photo_id: "a3f2b8c4",
          hash: "a3f2b8c4f1e9d2a7",
          original_filename: "test.jpg",
          content_type: "image/jpeg",
          file_size: 1024,
          storage_path: "/uploads/test.jpg",
          stored_at: timestamp
        })

      assert metadata.stored_at == timestamp
    end
  end

  describe "MockStorage adapter validation" do
    # This test validates that a minimal mock adapter compiles
    # It ensures that the behaviour contract is properly defined
    defmodule TestMockStorage do
      @moduledoc false
      @behaviour PhotoStorage

      @impl true
      def store_photo(_upload, _opts) do
        {:ok,
         %PhotoMetadata{
           photo_id: "mock123",
           hash: "mockhash",
           original_filename: "mock.jpg",
           content_type: "image/jpeg",
           file_size: 1024,
           storage_path: "/mock/path"
         }}
      end

      @impl true
      def delete_photo(_photo_id), do: :ok

      @impl true
      def get_photo_url(_photo_id, _variant), do: {:ok, "/mock/url"}

      @impl true
      def generate_variants(_photo_id), do: {:ok, %{}}
    end

    test "mock adapter implements all required callbacks" do
      upload = %{path: "/tmp/test.jpg", client_name: "test.jpg", content_type: "image/jpeg"}

      assert {:ok, %PhotoMetadata{}} = TestMockStorage.store_photo(upload, [])
      assert :ok = TestMockStorage.delete_photo("test")
      assert {:ok, _url} = TestMockStorage.get_photo_url("test", :thumbnail)
      assert {:ok, _variants} = TestMockStorage.generate_variants("test")
    end
  end
end
