defmodule Portfolio.Photography.Storage.Properties.StorageUtilsPropertiesTest do
  @moduledoc """
  Property-based tests for StorageUtils pure functions.

  Tests invariants for MIME type handling and file operations.
  """
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Portfolio.Photography.Storage.StorageUtils

  describe "get_extension_for_mime properties" do
    property "always returns a non-empty string" do
      check all(
              mime_type <-
                one_of([
                  constant("image/jpeg"),
                  constant("image/png"),
                  constant("image/webp"),
                  constant("image/avif"),
                  constant("image/gif"),
                  string(:alphanumeric, min_length: 1, max_length: 30)
                ])
            ) do
        result = StorageUtils.get_extension_for_mime(mime_type)
        assert is_binary(result)
        assert String.length(result) > 0
      end
    end

    property "known image MIME types return expected extensions" do
      known_mappings = [
        {"image/jpeg", "jpg"},
        {"image/png", "png"},
        {"image/webp", "webp"},
        {"image/gif", "gif"}
      ]

      for {mime, expected_ext} <- known_mappings do
        assert StorageUtils.get_extension_for_mime(mime) == expected_ext
      end
    end

    property "unknown MIME types fall back to jpg" do
      check all(random_type <- string(:alphanumeric, min_length: 5, max_length: 20)) do
        # Construct an unlikely MIME type
        mime = "application/x-#{random_type}-unknown"
        result = StorageUtils.get_extension_for_mime(mime)
        # Should fall back to jpg for unknown types
        assert result == "jpg"
      end
    end

    property "result is always lowercase" do
      check all(
              mime_type <-
                member_of([
                  "image/jpeg",
                  "image/png",
                  "image/webp",
                  "image/gif",
                  "image/avif"
                ])
            ) do
        result = StorageUtils.get_extension_for_mime(mime_type)
        assert result == String.downcase(result)
      end
    end

    property "result contains no dots or special characters" do
      check all(
              mime_type <-
                member_of([
                  "image/jpeg",
                  "image/png",
                  "image/webp",
                  "image/gif",
                  "video/mp4",
                  "audio/mpeg"
                ])
            ) do
        result = StorageUtils.get_extension_for_mime(mime_type)
        refute String.contains?(result, ".")
        refute String.contains?(result, "/")
        refute String.contains?(result, " ")
      end
    end

    property "deterministic: same input always produces same output" do
      check all(
              mime_type <-
                member_of([
                  "image/jpeg",
                  "image/png",
                  "image/webp",
                  "text/plain",
                  "application/json"
                ])
            ) do
        result1 = StorageUtils.get_extension_for_mime(mime_type)
        result2 = StorageUtils.get_extension_for_mime(mime_type)
        assert result1 == result2
      end
    end
  end

  describe "calculate_directory_size properties" do
    property "always returns non-negative integer" do
      # Test with various path patterns
      check all(path_segment <- string(:alphanumeric, min_length: 1, max_length: 10)) do
        # These paths likely don't exist, so should return 0
        result = StorageUtils.calculate_directory_size("/nonexistent/#{path_segment}")
        assert is_integer(result)
        assert result >= 0
      end
    end

    property "non-existent directories return 0" do
      check all(random_name <- string(:alphanumeric, min_length: 5, max_length: 15)) do
        path = "/definitely/does/not/exist/#{random_name}"
        assert StorageUtils.calculate_directory_size(path) == 0
      end
    end

    property "deterministic for same path" do
      # For non-existent paths, should consistently return 0
      check all(path <- string(:alphanumeric, min_length: 3, max_length: 20)) do
        full_path = "/tmp/nonexistent_test_#{path}"
        result1 = StorageUtils.calculate_directory_size(full_path)
        result2 = StorageUtils.calculate_directory_size(full_path)
        assert result1 == result2
      end
    end
  end
end
