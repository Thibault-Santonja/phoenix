defmodule Portfolio.Photography.ValueObjects.SlugTest do
  use ExUnit.Case, async: true

  alias Portfolio.Photography.ValueObjects.Slug

  doctest Slug

  describe "new/1" do
    test "creates valid slug from title" do
      assert {:ok, slug} = Slug.new("Paris 2024")
      assert Slug.to_string(slug) == "paris-2024"
    end

    test "normalizes to lowercase" do
      assert {:ok, slug} = Slug.new("HELLO WORLD")
      assert Slug.to_string(slug) == "hello-world"
    end

    test "replaces spaces with hyphens" do
      assert {:ok, slug} = Slug.new("my   great    title")
      assert Slug.to_string(slug) == "my-great-title"
    end

    test "removes special characters" do
      assert {:ok, slug} = Slug.new("Hello!@#$ World%^&*()")
      assert Slug.to_string(slug) == "hello-world"
    end

    test "removes leading and trailing hyphens" do
      assert {:ok, slug} = Slug.new("---test---")
      assert Slug.to_string(slug) == "test"
    end

    test "collapses multiple hyphens" do
      assert {:ok, slug} = Slug.new("test---slug")
      assert Slug.to_string(slug) == "test-slug"
    end

    test "accepts alphanumeric with hyphens" do
      assert {:ok, slug} = Slug.new("test-123-abc")
      assert Slug.to_string(slug) == "test-123-abc"
    end

    test "rejects empty string" do
      assert {:error, :invalid_slug} = Slug.new("")
    end

    test "rejects string with only special characters" do
      assert {:error, :invalid_slug} = Slug.new("!@#$%^&*()")
    end

    test "rejects string with only spaces" do
      assert {:error, :invalid_slug} = Slug.new("   ")
    end

    test "rejects too long slug" do
      long_title = String.duplicate("a", 150)
      assert {:error, :too_long} = Slug.new(long_title)
    end

    test "accepts slug at max length" do
      title = String.duplicate("a", 100)
      assert {:ok, slug} = Slug.new(title)
      assert String.length(Slug.to_string(slug)) == 100
    end
  end

  describe "new!/1" do
    test "returns slug struct on success" do
      slug = Slug.new!("Valid Title")
      assert %Slug{value: "valid-title"} = slug
    end

    test "raises ArgumentError on invalid slug" do
      assert_raise ArgumentError, "Invalid slug: invalid_slug", fn ->
        Slug.new!("")
      end
    end

    test "raises ArgumentError on too long slug" do
      assert_raise ArgumentError, "Invalid slug: too_long", fn ->
        Slug.new!(String.duplicate("a", 150))
      end
    end
  end

  describe "to_string/1" do
    test "extracts the string value" do
      {:ok, slug} = Slug.new("test")
      assert Slug.to_string(slug) == "test"
    end
  end

  describe "equal?/2" do
    test "returns true for identical slugs" do
      {:ok, slug1} = Slug.new("test")
      {:ok, slug2} = Slug.new("test")
      assert Slug.equal?(slug1, slug2)
    end

    test "returns false for different slugs" do
      {:ok, slug1} = Slug.new("test1")
      {:ok, slug2} = Slug.new("test2")
      refute Slug.equal?(slug1, slug2)
    end

    test "compares by value not reference" do
      {:ok, slug1} = Slug.new("paris-2024")
      {:ok, slug2} = Slug.new("Paris 2024")
      assert Slug.equal?(slug1, slug2)
    end
  end

  describe "String.Chars protocol" do
    test "converts slug to string automatically" do
      {:ok, slug} = Slug.new("test")
      assert "#{slug}" == "test"
    end

    test "works with string interpolation" do
      {:ok, slug} = Slug.new("my-album")
      assert "Album slug: #{slug}" == "Album slug: my-album"
    end
  end

  describe "transliteration" do
    test "transliterates French accents" do
      assert {:ok, slug} = Slug.new("café français")
      assert Slug.to_string(slug) == "cafe-francais"
    end

    test "transliterates various accented characters" do
      test_cases = [
        {"àáâãäå", "aaaaaa"},
        {"èéêë", "eeee"},
        {"ìíîï", "iiii"},
        {"òóôõö", "ooooo"},
        {"ùúûü", "uuuu"},
        {"ñ", "n"},
        {"ç", "c"},
        {"ÿ", "y"}
      ]

      Enum.each(test_cases, fn {input, expected} ->
        {:ok, slug} = Slug.new(input)
        assert Slug.to_string(slug) == expected
      end)
    end

    test "handles mixed case accented characters" do
      assert {:ok, slug} = Slug.new("CAFÉ Français")
      assert Slug.to_string(slug) == "cafe-francais"
    end

    test "transliterates special ligatures" do
      assert {:ok, slug} = Slug.new("œuvre")
      assert Slug.to_string(slug) == "oeuvre"

      assert {:ok, slug} = Slug.new("encyclopædia")
      assert Slug.to_string(slug) == "encyclopaedia"
    end

    test "removes smart quotes and apostrophes" do
      assert {:ok, slug} = Slug.new("l'été c'est")
      assert Slug.to_string(slug) == "lete-cest"
    end
  end

  describe "edge cases and boundary conditions" do
    test "handles single character" do
      assert {:ok, slug} = Slug.new("a")
      assert Slug.to_string(slug) == "a"
    end

    test "handles numbers only" do
      assert {:ok, slug} = Slug.new("2024")
      assert Slug.to_string(slug) == "2024"
    end

    test "handles mixed alphanumeric" do
      assert {:ok, slug} = Slug.new("abc123xyz")
      assert Slug.to_string(slug) == "abc123xyz"
    end

    test "handles underscores" do
      assert {:ok, slug} = Slug.new("test_with_underscores")
      # Underscores are converted to hyphens or removed
      result = Slug.to_string(slug)
      assert result == "testwithunderscores"
    end

    test "collapses whitespace" do
      assert {:ok, slug} = Slug.new("test     with    spaces")
      assert Slug.to_string(slug) == "test-with-spaces"
    end

    test "handles tabs and newlines" do
      assert {:ok, slug} = Slug.new("test\twith\ntabs")
      assert Slug.to_string(slug) == "test-with-tabs"
    end

    test "rejects only hyphens" do
      assert {:error, :invalid_slug} = Slug.new("---")
    end

    test "handles unicode characters" do
      # Non-latin characters are removed, resulting in empty slug
      assert {:error, :invalid_slug} = Slug.new("日本語")
    end

    test "handles emoji" do
      # Emoji are removed, leaving valid text
      assert {:ok, slug} = Slug.new("test 😀 emoji")
      assert Slug.to_string(slug) == "test-emoji"
    end

    test "exactly at max length boundary" do
      # Test at exactly 100 characters
      text = String.duplicate("a", 100)
      assert {:ok, slug} = Slug.new(text)
      assert String.length(Slug.to_string(slug)) == 100
    end

    test "one character over max length" do
      text = String.duplicate("a", 101)
      assert {:error, :too_long} = Slug.new(text)
    end

    test "handles repeating patterns" do
      assert {:ok, slug} = Slug.new("test-test-test")
      assert Slug.to_string(slug) == "test-test-test"
    end
  end

  describe "real-world album titles" do
    test "handles typical album title" do
      assert {:ok, slug} = Slug.new("Mariage de Sophie et Thomas")
      assert Slug.to_string(slug) == "mariage-de-sophie-et-thomas"
    end

    test "handles album with year" do
      assert {:ok, slug} = Slug.new("Paris 2024 - Été")
      assert Slug.to_string(slug) == "paris-2024-ete"
    end

    test "handles album with location" do
      assert {:ok, slug} = Slug.new("Photos de Tokyo, Japon")
      assert Slug.to_string(slug) == "photos-de-tokyo-japon"
    end

    test "handles album with special event" do
      assert {:ok, slug} = Slug.new("Concert de Rock'n'Roll!")
      assert Slug.to_string(slug) == "concert-de-rocknroll"
    end
  end

  describe "normalization consistency" do
    test "same input produces same slug" do
      {:ok, slug1} = Slug.new("Test Album 2024")
      {:ok, slug2} = Slug.new("Test Album 2024")

      assert Slug.equal?(slug1, slug2)
    end

    test "equivalent inputs produce same slug" do
      {:ok, slug1} = Slug.new("Test   Album")
      {:ok, slug2} = Slug.new("Test Album")

      assert Slug.equal?(slug1, slug2)
    end

    test "case variations produce same slug" do
      {:ok, slug1} = Slug.new("Test Album")
      {:ok, slug2} = Slug.new("TEST ALBUM")
      {:ok, slug3} = Slug.new("test album")

      assert Slug.equal?(slug1, slug2)
      assert Slug.equal?(slug2, slug3)
    end
  end

  describe "value object properties" do
    test "slug is immutable" do
      {:ok, slug} = Slug.new("original")

      # Slugs are structs, not maps, so Map.put creates a new map
      # This test verifies immutability conceptually
      assert slug.value == "original"
    end

    test "two slugs with same value are equal" do
      {:ok, slug1} = Slug.new("test")
      {:ok, slug2} = Slug.new("test")

      # Value equality
      assert slug1.value == slug2.value
      assert Slug.equal?(slug1, slug2)
    end

    test "slug has no identity" do
      {:ok, slug1} = Slug.new("test")
      {:ok, slug2} = Slug.new("test")

      # Structs with same values are equal in Elixir
      # But we use Slug.equal?/2 for semantic equality
      assert Slug.equal?(slug1, slug2)
      assert slug1.value == slug2.value
    end
  end

  describe "error messages" do
    test "new! provides clear error for empty slug" do
      assert_raise ArgumentError, "Invalid slug: invalid_slug", fn ->
        Slug.new!("")
      end
    end

    test "new! provides clear error for too long slug" do
      assert_raise ArgumentError, "Invalid slug: too_long", fn ->
        Slug.new!(String.duplicate("a", 150))
      end
    end
  end
end
