defmodule Portfolio.Security.PathValidatorTest do
  use ExUnit.Case, async: true

  alias Portfolio.Security.PathValidator

  describe "validate/2" do
    test "accepts valid path within allowed directory" do
      assert :ok = PathValidator.validate("/app/uploads/photos/abc123", "/app/uploads")
    end

    test "accepts path that is exactly the allowed directory" do
      assert :ok = PathValidator.validate("/app/uploads", "/app/uploads")
    end

    test "rejects path with ../ traversal pattern" do
      assert {:error, :path_traversal_detected} =
               PathValidator.validate("/app/uploads/../secrets", "/app/uploads")
    end

    test "rejects path with ..\\ traversal pattern" do
      assert {:error, :path_traversal_detected} =
               PathValidator.validate("/app/uploads/..\\secrets", "/app/uploads")
    end

    test "rejects path with URL-encoded traversal" do
      assert {:error, :path_traversal_detected} =
               PathValidator.validate("/app/uploads/%2e%2e/secrets", "/app/uploads")
    end

    test "rejects path with null byte" do
      assert {:error, :path_traversal_detected} =
               PathValidator.validate("/app/uploads/file\0.jpg", "/app/uploads")
    end

    test "rejects path outside allowed directory" do
      assert {:error, :outside_allowed_directory} =
               PathValidator.validate("/etc/passwd", "/app/uploads")
    end

    test "rejects nil path" do
      assert {:error, :invalid_path} = PathValidator.validate(nil, "/app/uploads")
    end
  end

  describe "validate_and_expand/2" do
    test "returns expanded path on success" do
      base = Path.expand("priv/static/uploads")
      path = Path.join(base, "photos/abc123")

      assert {:ok, expanded} = PathValidator.validate_and_expand(path, base)
      assert String.starts_with?(expanded, "/")
      assert String.contains?(expanded, "photos/abc123")
    end

    test "returns error for traversal attempt" do
      assert {:error, :path_traversal_detected} =
               PathValidator.validate_and_expand("/app/../etc/passwd", "/app")
    end
  end

  describe "safe_join/2" do
    test "safely joins path segments" do
      assert {:ok, path} = PathValidator.safe_join("/uploads", ["photos", "abc123"])
      assert path == Path.expand("/uploads/photos/abc123")
    end

    test "accepts single segment as string" do
      assert {:ok, path} = PathValidator.safe_join("/uploads", "photos")
      assert path == Path.expand("/uploads/photos")
    end

    test "rejects segment with traversal pattern" do
      assert {:error, :path_traversal_detected} =
               PathValidator.safe_join("/uploads", ["photos", "../../../etc"])
    end

    test "rejects segment with .." do
      assert {:error, :path_traversal_detected} =
               PathValidator.safe_join("/uploads", "..")
    end
  end

  describe "safe_join/3" do
    test "safely joins two segments" do
      assert {:ok, path} = PathValidator.safe_join("/uploads", "photos", "abc123")
      assert path == Path.expand("/uploads/photos/abc123")
    end

    test "rejects traversal in first segment" do
      assert {:error, :path_traversal_detected} =
               PathValidator.safe_join("/uploads", "../etc", "passwd")
    end

    test "rejects traversal in second segment" do
      assert {:error, :path_traversal_detected} =
               PathValidator.safe_join("/uploads", "photos", "../../../etc")
    end
  end

  describe "validate_photo_id/1" do
    test "accepts valid 8-character hex photo_id" do
      assert :ok = PathValidator.validate_photo_id("a3f2b8c4")
      assert :ok = PathValidator.validate_photo_id("A3F2B8C4")
      assert :ok = PathValidator.validate_photo_id("12345678")
    end

    test "accepts valid UUID photo_id" do
      assert :ok = PathValidator.validate_photo_id("550e8400-e29b-41d4-a716-446655440000")
    end

    test "rejects photo_id with traversal pattern" do
      assert {:error, :invalid_photo_id} = PathValidator.validate_photo_id("../etc")
      assert {:error, :invalid_photo_id} = PathValidator.validate_photo_id("..\\etc")
    end

    test "rejects photo_id with wrong length" do
      assert {:error, :invalid_photo_id} = PathValidator.validate_photo_id("abc")
      assert {:error, :invalid_photo_id} = PathValidator.validate_photo_id("abcdefgh1")
    end

    test "rejects photo_id with invalid characters" do
      assert {:error, :invalid_photo_id} = PathValidator.validate_photo_id("abcdefg!")
      assert {:error, :invalid_photo_id} = PathValidator.validate_photo_id("abc defg")
    end

    test "rejects nil photo_id" do
      assert {:error, :invalid_photo_id} = PathValidator.validate_photo_id(nil)
    end

    test "rejects non-string photo_id" do
      assert {:error, :invalid_photo_id} = PathValidator.validate_photo_id(12_345_678)
    end
  end

  describe "validate_filename/1" do
    test "accepts valid filename" do
      assert :ok = PathValidator.validate_filename("image.jpg")
      assert :ok = PathValidator.validate_filename("my-photo_2024.webp")
      assert :ok = PathValidator.validate_filename("thumbnail.png")
    end

    test "accepts dotfiles" do
      assert :ok = PathValidator.validate_filename(".gitkeep")
      assert :ok = PathValidator.validate_filename(".hidden")
    end

    test "rejects filename with path separator" do
      assert {:error, :invalid_filename} = PathValidator.validate_filename("path/to/file.jpg")
      assert {:error, :invalid_filename} = PathValidator.validate_filename("path\\to\\file.jpg")
    end

    test "rejects filename with traversal pattern" do
      assert {:error, :invalid_filename} = PathValidator.validate_filename("../malicious.jpg")
      assert {:error, :invalid_filename} = PathValidator.validate_filename("..\\malicious.jpg")
    end

    test "rejects filename that is too long" do
      long_name = String.duplicate("a", 256) <> ".jpg"
      assert {:error, :invalid_filename} = PathValidator.validate_filename(long_name)
    end

    test "accepts filename at max length" do
      name = String.duplicate("a", 251) <> ".jpg"
      assert :ok = PathValidator.validate_filename(name)
    end

    test "rejects nil filename" do
      assert {:error, :invalid_filename} = PathValidator.validate_filename(nil)
    end

    test "rejects non-string filename" do
      assert {:error, :invalid_filename} = PathValidator.validate_filename(123)
    end
  end

  describe "integration scenarios" do
    test "prevents typical directory traversal attack" do
      base = "/app/uploads/photos"

      # Attacker tries to read /etc/passwd
      assert {:error, _} = PathValidator.safe_join(base, "../../../etc/passwd")

      # Attacker tries URL-encoded traversal
      assert {:error, :path_traversal_detected} =
               PathValidator.validate(
                 "/app/uploads/photos/%2e%2e/%2e%2e/etc/passwd",
                 base
               )
    end

    test "prevents null byte injection" do
      base = "/app/uploads/photos"

      # Attacker tries to bypass extension check with null byte
      malicious = "image.jpg\0.php"

      assert {:error, :path_traversal_detected} =
               PathValidator.validate(Path.join(base, malicious), base)
    end

    test "allows legitimate nested paths" do
      base = "/app/uploads/photos"

      assert {:ok, _} = PathValidator.safe_join(base, ["abc123", "thumbnail.webp"])
      assert {:ok, _} = PathValidator.safe_join(base, ["user-uploads", "2024", "01", "photo.jpg"])
    end
  end
end
