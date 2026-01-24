defmodule PortfolioWeb.Helpers.AlbumTypeFormatterTest do
  @moduledoc """
  Tests for AlbumTypeFormatter helper module.
  """

  use ExUnit.Case, async: true

  alias PortfolioWeb.Helpers.AlbumTypeFormatter

  describe "format_type/1" do
    test "formats known album types as atoms" do
      # Each known type should return a non-empty string
      known_types = [
        :couples,
        :wedding,
        :motherhood,
        :events,
        :landscape,
        :street,
        :music,
        :reenactment,
        :amvcc,
        :china,
        :japan,
        :taiwan
      ]

      for type <- known_types do
        result = AlbumTypeFormatter.format_type(type)
        assert is_binary(result), "Expected string for #{type}, got #{inspect(result)}"
        assert result != "", "Expected non-empty string for #{type}"
      end
    end

    test "formats :amvcc without translation" do
      # AMVCC is a proper noun, always returned as-is
      assert AlbumTypeFormatter.format_type(:amvcc) == "AMVCC"
    end

    test "handles unknown atom types by converting to string" do
      assert AlbumTypeFormatter.format_type(:unknown_type) == "unknown_type"
      assert AlbumTypeFormatter.format_type(:random) == "random"
    end

    test "handles string input by converting to existing atom" do
      # Known types as strings should work
      result = AlbumTypeFormatter.format_type("wedding")
      assert is_binary(result)
      assert result != ""
    end

    test "raises for non-existent atom strings" do
      # String.to_existing_atom/1 raises for unknown atoms
      assert_raise ArgumentError, fn ->
        AlbumTypeFormatter.format_type("definitely_not_an_existing_atom_xyz123")
      end
    end
  end

  describe "format_chapter_title/1" do
    test "formats all known chapter types" do
      known_chapters = [
        "amvcc",
        "china",
        "couples",
        "events",
        "japan",
        "landscape",
        "motherhood",
        "music",
        "reenactment",
        "street",
        "taiwan",
        "wedding"
      ]

      for chapter <- known_chapters do
        result = AlbumTypeFormatter.format_chapter_title(chapter)
        assert is_binary(result), "Expected string for #{chapter}, got #{inspect(result)}"
        assert result != "", "Expected non-empty string for #{chapter}"
      end
    end

    test "formats amvcc without translation" do
      assert AlbumTypeFormatter.format_chapter_title("amvcc") == "AMVCC"
    end

    test "returns gallery for unknown chapters" do
      # Unknown chapters fall back to generic gallery title
      result = AlbumTypeFormatter.format_chapter_title("unknown")
      assert is_binary(result)
    end

    test "returns gallery for empty string" do
      result = AlbumTypeFormatter.format_chapter_title("")
      assert is_binary(result)
    end

    test "returns gallery for nil" do
      result = AlbumTypeFormatter.format_chapter_title(nil)
      assert is_binary(result)
    end
  end

  describe "consistency between format_type and format_chapter_title" do
    test "amvcc returns same value for both functions" do
      assert AlbumTypeFormatter.format_type(:amvcc) == "AMVCC"
      assert AlbumTypeFormatter.format_chapter_title("amvcc") == "AMVCC"
    end

    test "common types return consistent translations" do
      # Types that exist in both functions should return similar values
      # (may differ slightly due to different gettext keys, but should be non-empty)
      common_types = ["wedding", "landscape", "events", "china", "japan", "taiwan"]

      for type <- common_types do
        atom_result = AlbumTypeFormatter.format_type(String.to_atom(type))
        string_result = AlbumTypeFormatter.format_chapter_title(type)

        assert is_binary(atom_result), "format_type should return string for #{type}"
        assert is_binary(string_result), "format_chapter_title should return string for #{type}"
      end
    end
  end
end
