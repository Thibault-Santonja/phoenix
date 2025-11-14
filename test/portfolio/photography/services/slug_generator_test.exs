defmodule Portfolio.Photography.Services.SlugGeneratorTest do
  use Portfolio.DataCase, async: true

  import PortfolioTest.Fixtures.PhotographyFixtures

  alias Portfolio.Photography.Services.SlugGenerator

  describe "generate_unique_slug/2" do
    test "generates base slug when no collision" do
      {:ok, slug} = SlugGenerator.generate_unique_slug("Voyage Japon", ~D[2024-05-15])

      assert slug == "voyage-japon"
    end

    test "generates slug with year suffix when base slug exists" do
      # Create album with base slug
      create_album(slug: "voyage-japon", date_prise_vue: ~D[2024-05-15])

      # Try to generate slug with same title but different year
      {:ok, slug} = SlugGenerator.generate_unique_slug("Voyage Japon", ~D[2025-06-20])

      assert slug == "voyage-japon-2025"
    end

    test "generates slug with year-month suffix when year suffix exists" do
      # Create albums with base and year suffix
      create_album(slug: "voyage-japon", date_prise_vue: ~D[2024-05-15])
      create_album(slug: "voyage-japon-2024", date_prise_vue: ~D[2024-03-10])

      # Try same title, same year but different month
      {:ok, slug} = SlugGenerator.generate_unique_slug("Voyage Japon", ~D[2024-08-20])

      assert slug == "voyage-japon-2024-08"
    end

    test "generates slug with year-month-day suffix when year-month exists" do
      # Create albums with base, year, and year-month suffixes
      create_album(slug: "voyage-japon", date_prise_vue: ~D[2024-05-15])
      create_album(slug: "voyage-japon-2024", date_prise_vue: ~D[2024-03-10])
      create_album(slug: "voyage-japon-2024-08", date_prise_vue: ~D[2024-08-10])

      # Try same title, same year-month but different day
      {:ok, slug} = SlugGenerator.generate_unique_slug("Voyage Japon", ~D[2024-08-25])

      assert slug == "voyage-japon-2024-08-25"
    end

    test "returns error when all suffix strategies exhausted" do
      # Create albums occupying all suffix levels
      create_album(slug: "voyage-japon", date_prise_vue: ~D[2024-05-15])
      create_album(slug: "voyage-japon-2024", date_prise_vue: ~D[2024-03-10])
      create_album(slug: "voyage-japon-2024-05", date_prise_vue: ~D[2024-05-10])
      create_album(slug: "voyage-japon-2024-05-15", date_prise_vue: ~D[2024-05-15])

      # Try exact same title and date
      assert {:error, :unable_to_generate_unique_slug} =
               SlugGenerator.generate_unique_slug("Voyage Japon", ~D[2024-05-15])
    end

    test "normalizes title to slug format" do
      {:ok, slug} = SlugGenerator.generate_unique_slug("Château d'Été 2024!", ~D[2024-07-01])

      # Apostrophe is removed by Slug normalization
      assert slug == "chateau-dete-2024"
    end

    test "handles special characters in title" do
      {:ok, slug} =
        SlugGenerator.generate_unique_slug("Mariage Claire & Damien 🎉", ~D[2024-06-15])

      assert slug == "mariage-claire-damien"
    end

    test "handles very long titles by returning error" do
      # Create a title that will exceed 100 chars after normalization
      long_title = String.duplicate("Very Long Title ", 10)

      # Should return error because normalized slug exceeds max length
      assert {:error, :too_long} = SlugGenerator.generate_unique_slug(long_title, ~D[2024-01-01])
    end

    test "pads month and day with zeros" do
      # Create albums to force year-month-day suffix
      create_album(slug: "nouvel-an", date_prise_vue: ~D[2024-01-01])
      create_album(slug: "nouvel-an-2024", date_prise_vue: ~D[2024-01-10])
      create_album(slug: "nouvel-an-2024-01", date_prise_vue: ~D[2024-01-12])

      {:ok, slug} = SlugGenerator.generate_unique_slug("Nouvel An", ~D[2024-01-15])

      assert slug == "nouvel-an-2024-01-15"
    end

    test "handles invalid title returning error" do
      assert {:error, :invalid_slug} = SlugGenerator.generate_unique_slug("", ~D[2024-01-01])
    end

    test "handles multiple albums with different dates" do
      create_album(slug: "paris", date_prise_vue: ~D[2020-06-15])
      create_album(slug: "paris-2021", date_prise_vue: ~D[2021-08-20])
      create_album(slug: "paris-2022", date_prise_vue: ~D[2022-09-10])

      {:ok, slug} = SlugGenerator.generate_unique_slug("Paris", ~D[2023-05-01])

      assert slug == "paris-2023"
    end
  end

  describe "generate_unique_slug/2 edge cases" do
    test "handles title with only special characters" do
      assert {:error, :invalid_slug} =
               SlugGenerator.generate_unique_slug("!@#$%^&*()", ~D[2024-01-01])
    end

    test "handles title with accents and special chars" do
      {:ok, slug} = SlugGenerator.generate_unique_slug("Événement été", ~D[2024-06-01])

      assert slug == "evenement-ete"
    end

    test "generates different slugs for albums on same day with different titles" do
      create_album(slug: "matin", date_prise_vue: ~D[2024-05-15])

      {:ok, slug} = SlugGenerator.generate_unique_slug("Soir", ~D[2024-05-15])

      assert slug == "soir"
    end

    test "handles leap year date" do
      {:ok, slug} = SlugGenerator.generate_unique_slug("Leap Day", ~D[2024-02-29])

      assert slug == "leap-day"
    end
  end

  describe "slug collision resolution strategy" do
    test "skips directly to year-month if year is taken" do
      create_album(slug: "test", date_prise_vue: ~D[2024-01-15])
      create_album(slug: "test-2024", date_prise_vue: ~D[2024-02-20])

      {:ok, slug} = SlugGenerator.generate_unique_slug("Test", ~D[2024-03-10])

      assert slug == "test-2024-03"
    end

    test "collision resolution is deterministic" do
      create_album(slug: "album", date_prise_vue: ~D[2024-05-15])

      # Generate twice with same params
      {:ok, slug1} = SlugGenerator.generate_unique_slug("Album", ~D[2025-06-20])
      {:ok, slug2} = SlugGenerator.generate_unique_slug("Album", ~D[2025-06-20])

      assert slug1 == slug2
      assert slug1 == "album-2025"
    end
  end
end
