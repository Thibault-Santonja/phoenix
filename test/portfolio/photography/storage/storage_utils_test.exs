defmodule Portfolio.Photography.Storage.StorageUtilsTest do
  @moduledoc """
  Tests pour les utilitaires de stockage.
  """

  use ExUnit.Case, async: true

  alias Portfolio.Photography.Storage.StorageUtils

  doctest StorageUtils

  describe "get_extension_for_mime/1" do
    test "returns correct extension for common image types" do
      assert StorageUtils.get_extension_for_mime("image/jpeg") == "jpg"
      assert StorageUtils.get_extension_for_mime("image/png") == "png"
      assert StorageUtils.get_extension_for_mime("image/gif") == "gif"
      assert StorageUtils.get_extension_for_mime("image/webp") == "webp"
    end

    test "returns jpg as fallback for unknown MIME type" do
      assert StorageUtils.get_extension_for_mime("unknown/type") == "jpg"
    end
  end

  describe "calculate_directory_size/1" do
    test "returns 0 for non-existent directory" do
      assert StorageUtils.calculate_directory_size("/non/existent/path") == 0
    end

    test "calculates size of directory with files" do
      # Create a temp directory with a file
      tmp_dir = Path.join(System.tmp_dir!(), "storage_utils_test_#{:rand.uniform(100_000)}")
      File.mkdir_p!(tmp_dir)

      try do
        # Create a file with known content
        file_path = Path.join(tmp_dir, "test.txt")
        content = "Hello, World!"
        File.write!(file_path, content)

        size = StorageUtils.calculate_directory_size(tmp_dir)
        assert size == byte_size(content)
      after
        File.rm_rf!(tmp_dir)
      end
    end
  end
end
