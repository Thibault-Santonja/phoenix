defmodule Portfolio.Photography.ValueObjects.SlugTest do
  use ExUnit.Case, async: true

  alias Portfolio.Photography.ValueObjects.Slug

  describe "new/1" do
    test "creates slug from simple string" do
      assert {:ok, %Slug{value: "hello-world"}} = Slug.new("Hello World")
    end

    test "creates slug from lowercase string" do
      assert {:ok, %Slug{value: "already-lowercase"}} = Slug.new("already-lowercase")
    end

    test "creates slug from uppercase string" do
      assert {:ok, %Slug{value: "uppercase-text"}} = Slug.new("UPPERCASE TEXT")
    end

    test "creates slug from mixed case string" do
      assert {:ok, %Slug{value: "mixed-case-text"}} = Slug.new("MiXeD CaSe TeXt")
    end

    test "transliterates French lowercase accents" do
      assert {:ok, %Slug{value: "cafe-a-paris"}} = Slug.new("café à paris")
    end

    test "transliterates French uppercase accents" do
      assert {:ok, %Slug{value: "cafe-a-paris"}} = Slug.new("Café À Paris")
    end

    test "transliterates various accented characters" do
      assert {:ok, %Slug{value: "ete-en-provence"}} = Slug.new("Été en Provence")
      assert {:ok, %Slug{value: "noel-a-nice"}} = Slug.new("Noël à Nice")
      assert {:ok, %Slug{value: "chateau-de-versailles"}} = Slug.new("Château de Versailles")
    end

    test "removes special characters" do
      assert {:ok, %Slug{value: "alexandre-anne"}} = Slug.new("Alexandre & Anne")
      assert {:ok, %Slug{value: "test123"}} = Slug.new("test!@#$%^&*()123")
      assert {:ok, %Slug{value: "hello-world"}} = Slug.new("hello, world!")
    end

    test "replaces multiple spaces with single hyphen" do
      assert {:ok, %Slug{value: "multiple-spaces"}} = Slug.new("multiple   spaces")
      assert {:ok, %Slug{value: "lots-of-spaces"}} = Slug.new("lots     of     spaces")
    end

    test "replaces multiple hyphens with single hyphen" do
      assert {:ok, %Slug{value: "multiple-hyphens"}} = Slug.new("multiple---hyphens")
      assert {:ok, %Slug{value: "many-hyphens"}} = Slug.new("many-----hyphens")
    end

    test "trims hyphens from start and end" do
      assert {:ok, %Slug{value: "trimmed"}} = Slug.new("-trimmed-")
      assert {:ok, %Slug{value: "test"}} = Slug.new("---test---")
    end

    test "handles numbers" do
      assert {:ok, %Slug{value: "mariage-2024"}} = Slug.new("Mariage 2024")
      assert {:ok, %Slug{value: "123-test-456"}} = Slug.new("123 test 456")
    end

    test "truncates to max length (100 characters)" do
      long_string = String.duplicate("a", 150)
      assert {:ok, %Slug{value: value}} = Slug.new(long_string)
      assert String.length(value) == 100
    end

    test "truncates properly with spaces" do
      long_title =
        "This is a very long album title that will definitely exceed one hundred characters when combined with additional text here"

      assert {:ok, %Slug{value: value}} = Slug.new(long_title)
      assert String.length(value) <= 100
      # Should not end with hyphen after truncation
      refute String.ends_with?(value, "-")
    end

    test "returns error for empty result after normalization" do
      assert {:error, :invalid_slug} = Slug.new("@@@@")
      assert {:error, :invalid_slug} = Slug.new("!@#$%^&*()")
      assert {:error, :invalid_slug} = Slug.new("---")
    end

    test "returns error for empty string" do
      assert {:error, :invalid_slug} = Slug.new("")
    end

    test "returns error for whitespace only" do
      assert {:error, :invalid_slug} = Slug.new("   ")
      assert {:error, :invalid_slug} = Slug.new("\t\n")
    end

    test "handles complex real-world album titles" do
      assert {:ok, %Slug{value: "alexandre-anne-mariage-2024"}} =
               Slug.new("Alexandre & Anne - Mariage 2024")

      assert {:ok, %Slug{value: "seance-photos-couples-au-chateau"}} =
               Slug.new("Séance photos couples au château")

      assert {:ok, %Slug{value: "concert-jazz-a-la-villette"}} =
               Slug.new("Concert Jazz à la Villette")
    end
  end

  describe "new!/1" do
    test "returns slug struct for valid input" do
      slug = Slug.new!("Valid Title")
      assert %Slug{value: "valid-title"} = slug
    end

    test "raises ArgumentError for invalid input" do
      assert_raise ArgumentError, "Invalid slug: invalid_slug", fn ->
        Slug.new!("@@@@")
      end
    end

    test "raises ArgumentError for empty string" do
      assert_raise ArgumentError, "Invalid slug: invalid_slug", fn ->
        Slug.new!("")
      end
    end
  end

  describe "normalize/1" do
    test "normalizes simple strings" do
      assert Slug.normalize("Hello World") == "hello-world"
    end

    test "normalizes strings with accents" do
      assert Slug.normalize("Café à Paris") == "cafe-a-paris"
    end

    test "removes special characters" do
      assert Slug.normalize("Test!@#$123") == "test123"
    end

    test "handles empty strings" do
      assert Slug.normalize("") == ""
    end

    test "handles only special characters" do
      assert Slug.normalize("!@#$%") == ""
    end

    test "normalizes maintains idempotence" do
      input = "Test Title 2024"
      normalized = Slug.normalize(input)
      # Normalizing again should give same result
      assert Slug.normalize(normalized) == normalized
    end
  end

  describe "String.Chars protocol" do
    test "converts slug to string using to_string/1" do
      {:ok, slug} = Slug.new("Hello World")
      assert to_string(slug) == "hello-world"
    end

    test "string interpolation works" do
      {:ok, slug} = Slug.new("Test Album")
      result = "URL: /albums/#{slug}"
      assert result == "URL: /albums/test-album"
    end
  end

  describe "Phoenix.Param protocol" do
    test "converts slug to param using Phoenix.Param.to_param/1" do
      {:ok, slug} = Slug.new("My Album")
      assert Phoenix.Param.to_param(slug) == "my-album"
    end
  end

  describe "edge cases" do
    test "handles slug with only hyphens and spaces" do
      assert {:error, :invalid_slug} = Slug.new("- - - -")
    end

    test "handles unicode characters outside Latin set" do
      # These should be removed as they're not in our transliteration map
      assert {:ok, %Slug{value: "test"}} = Slug.new("test 你好")
      assert {:ok, %Slug{value: "hello"}} = Slug.new("hello مرحبا")
    end

    test "handles mixed content" do
      assert {:ok, %Slug{value: "album-2024-paris"}} =
               Slug.new("Album 2024 - Paris!")
    end

    test "preserves existing hyphens correctly" do
      assert {:ok, %Slug{value: "pre-existing-hyphens"}} =
               Slug.new("pre-existing-hyphens")
    end

    test "handles titles with quotes" do
      # Quotes are removed as special characters
      assert {:ok, %Slug{value: "lalbum-de-lannee"}} =
               Slug.new("L'album de l'année")
    end
  end

  describe "struct immutability" do
    test "slug struct is immutable" do
      {:ok, slug} = Slug.new("Original")

      # Attempting to change the value should not affect original
      _new_map = Map.put(slug, :value, "modified")

      # Original should remain unchanged
      assert slug.value == "original"
    end

    test "slug has enforced keys" do
      # Attempting to create without value should raise
      assert_raise ArgumentError, fn ->
        struct!(Slug, %{})
      end
    end
  end
end
