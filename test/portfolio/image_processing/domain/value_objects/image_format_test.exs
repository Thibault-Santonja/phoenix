defmodule Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormatTest do
  use ExUnit.Case, async: true

  alias Portfolio.ImageProcessing.Domain.ValueObjects.ImageFormat

  doctest ImageFormat

  describe "valid?/1" do
    test "returns true for webp format" do
      assert ImageFormat.valid?(:webp)
    end

    test "returns true for avif format" do
      assert ImageFormat.valid?(:avif)
    end

    test "returns true for jpeg format" do
      assert ImageFormat.valid?(:jpeg)
    end

    test "returns false for png format" do
      refute ImageFormat.valid?(:png)
    end

    test "returns false for gif format" do
      refute ImageFormat.valid?(:gif)
    end

    test "returns false for bmp format" do
      refute ImageFormat.valid?(:bmp)
    end

    test "returns false for tiff format" do
      refute ImageFormat.valid?(:tiff)
    end

    test "returns false for arbitrary atom" do
      refute ImageFormat.valid?(:invalid_format)
    end

    test "returns false for nil" do
      refute ImageFormat.valid?(nil)
    end

    test "returns false for string" do
      refute ImageFormat.valid?("webp")
    end

    test "returns false for integer" do
      refute ImageFormat.valid?(1)
    end
  end

  describe "extension/1" do
    test "returns 'webp' extension for webp format" do
      assert ImageFormat.extension(:webp) == "webp"
    end

    test "returns 'avif' extension for avif format" do
      assert ImageFormat.extension(:avif) == "avif"
    end

    test "returns 'jpg' extension for jpeg format" do
      assert ImageFormat.extension(:jpeg) == "jpg"
    end
  end

  describe "all/0" do
    test "returns list of all valid formats" do
      formats = ImageFormat.all()
      assert :webp in formats
      assert :avif in formats
      assert :jpeg in formats
    end

    test "returns exactly three formats" do
      assert length(ImageFormat.all()) == 3
    end

    test "all returned formats are valid" do
      formats = ImageFormat.all()

      Enum.each(formats, fn format ->
        assert ImageFormat.valid?(format)
      end)
    end

    test "returns formats as atoms" do
      formats = ImageFormat.all()

      Enum.each(formats, fn format ->
        assert is_atom(format)
      end)
    end
  end

  describe "from_string/1" do
    test "parses 'webp' to :webp atom" do
      assert {:ok, :webp} = ImageFormat.from_string("webp")
    end

    test "parses 'avif' to :avif atom" do
      assert {:ok, :avif} = ImageFormat.from_string("avif")
    end

    test "parses 'jpeg' to :jpeg atom" do
      assert {:ok, :jpeg} = ImageFormat.from_string("jpeg")
    end

    test "returns error for invalid format string" do
      assert {:error, :invalid_format} = ImageFormat.from_string("png")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_format} = ImageFormat.from_string("")
    end

    test "returns error for arbitrary string" do
      assert {:error, :invalid_format} = ImageFormat.from_string("invalid")
    end

    test "returns error for nil" do
      assert_raise FunctionClauseError, fn ->
        ImageFormat.from_string(nil)
      end
    end

    test "returns error for atom input" do
      assert_raise FunctionClauseError, fn ->
        ImageFormat.from_string(:webp)
      end
    end

    test "returns error for uppercase string" do
      assert {:error, :invalid_format} = ImageFormat.from_string("WEBP")
    end

    test "returns error for mixed case string" do
      assert {:error, :invalid_format} = ImageFormat.from_string("WebP")
    end

    test "returns error for string with spaces" do
      assert {:error, :invalid_format} = ImageFormat.from_string("web p")
    end
  end

  describe "integration scenarios" do
    test "all formats have unique extensions" do
      formats = ImageFormat.all()
      extensions = Enum.map(formats, &ImageFormat.extension/1)
      assert length(extensions) == length(Enum.uniq(extensions))
    end

    test "extension returns string type" do
      formats = ImageFormat.all()

      Enum.each(formats, fn format ->
        extension = ImageFormat.extension(format)
        assert is_binary(extension)
      end)
    end

    test "extension strings can be used in file paths" do
      formats = ImageFormat.all()

      Enum.each(formats, fn format ->
        extension = ImageFormat.extension(format)
        filename = "image.#{extension}"
        assert String.contains?(filename, ".")
        assert String.ends_with?(filename, extension)
      end)
    end

    test "from_string followed by extension returns expected values" do
      assert {:ok, format} = ImageFormat.from_string("webp")
      assert ImageFormat.extension(format) == "webp"

      assert {:ok, format} = ImageFormat.from_string("avif")
      assert ImageFormat.extension(format) == "avif"

      assert {:ok, format} = ImageFormat.from_string("jpeg")
      assert ImageFormat.extension(format) == "jpg"
    end
  end
end
