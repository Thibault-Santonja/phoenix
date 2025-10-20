defmodule Portfolio.Photography.ValueObjects.SlugTest do
  use ExUnit.Case, async: true

  alias Portfolio.Photography.ValueObjects.Slug

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
end
