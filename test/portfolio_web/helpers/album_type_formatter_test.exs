defmodule PortfolioWeb.Helpers.AlbumTypeFormatterTest do
  @moduledoc """
  Tests for AlbumTypeFormatter helper module.
  """

  use ExUnit.Case, async: true

  alias PortfolioWeb.Helpers.AlbumTypeFormatter

  describe "format_type/1" do
    test "formats known album types as atoms" do
      # All known types should return non-empty strings
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
        assert is_binary(result), "Expected string for type #{inspect(type)}"
        assert result != "", "Expected non-empty string for type #{inspect(type)}"
      end
    end

    test "formats :amvcc as literal 'AMVCC'" do
      assert AlbumTypeFormatter.format_type(:amvcc) == "AMVCC"
    end

    test "formats unknown atom types by converting to string" do
      assert AlbumTypeFormatter.format_type(:unknown_type) == "unknown_type"
      assert AlbumTypeFormatter.format_type(:custom) == "custom"
    end

    test "formats string types by converting to existing atom first" do
      # Known types as strings should work
      assert is_binary(AlbumTypeFormatter.format_type("wedding"))
      assert is_binary(AlbumTypeFormatter.format_type("couples"))
    end

    test "raises for non-existent atom strings" do
      # Strings that don't map to existing atoms should raise
      assert_raise ArgumentError, fn ->
        AlbumTypeFormatter.format_type("definitely_not_an_existing_atom_xyz123")
      end
    end
  end

  describe "format_chapter_title/1" do
    test "formats known chapter strings" do
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
        assert is_binary(result), "Expected string for chapter #{inspect(chapter)}"
        assert result != "", "Expected non-empty string for chapter #{inspect(chapter)}"
      end
    end

    test "formats 'amvcc' as literal 'AMVCC'" do
      assert AlbumTypeFormatter.format_chapter_title("amvcc") == "AMVCC"
    end

    test "returns generic gallery title for unknown chapters" do
      result = AlbumTypeFormatter.format_chapter_title("unknown")
      assert is_binary(result)
      # Should return the gallery translation
      assert result != ""
    end

    test "handles nil and empty string gracefully" do
      # These fall through to the catch-all clause
      assert is_binary(AlbumTypeFormatter.format_chapter_title(nil))
      assert is_binary(AlbumTypeFormatter.format_chapter_title(""))
    end
  end

  describe "consistency between format_type and format_chapter_title" do
    test "wedding type is formatted consistently" do
      atom_result = AlbumTypeFormatter.format_type(:wedding)
      string_result = AlbumTypeFormatter.format_chapter_title("wedding")
      assert atom_result == string_result
    end

    test "amvcc is formatted identically" do
      assert AlbumTypeFormatter.format_type(:amvcc) == "AMVCC"
      assert AlbumTypeFormatter.format_chapter_title("amvcc") == "AMVCC"
    end

    test "china type is formatted consistently" do
      atom_result = AlbumTypeFormatter.format_type(:china)
      string_result = AlbumTypeFormatter.format_chapter_title("china")
      assert atom_result == string_result
    end

    test "japan type is formatted consistently" do
      atom_result = AlbumTypeFormatter.format_type(:japan)
      string_result = AlbumTypeFormatter.format_chapter_title("japan")
      assert atom_result == string_result
    end

    test "taiwan type is formatted consistently" do
      atom_result = AlbumTypeFormatter.format_type(:taiwan)
      string_result = AlbumTypeFormatter.format_chapter_title("taiwan")
      assert atom_result == string_result
    end

    test "couples type is formatted consistently" do
      atom_result = AlbumTypeFormatter.format_type(:couples)
      string_result = AlbumTypeFormatter.format_chapter_title("couples")
      assert atom_result == string_result
    end

    test "events type is formatted consistently" do
      atom_result = AlbumTypeFormatter.format_type(:events)
      string_result = AlbumTypeFormatter.format_chapter_title("events")
      assert atom_result == string_result
    end

    test "landscape type is formatted consistently" do
      atom_result = AlbumTypeFormatter.format_type(:landscape)
      string_result = AlbumTypeFormatter.format_chapter_title("landscape")
      assert atom_result == string_result
    end

    test "reenactment type is formatted consistently" do
      atom_result = AlbumTypeFormatter.format_type(:reenactment)
      string_result = AlbumTypeFormatter.format_chapter_title("reenactment")
      assert atom_result == string_result
    end
  end
end
