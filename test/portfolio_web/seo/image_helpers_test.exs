defmodule PortfolioWeb.SEO.ImageHelpersTest do
  use ExUnit.Case, async: true

  alias PortfolioWeb.SEO.ImageHelpers

  describe "generate_alt_text/2" do
    test "generates alt text with photo title" do
      photo = %{title: "La charge de la cavalerie", hash: "abc123def456", exif_data: nil}
      album = %{title: "Waterloo 2024"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "Waterloo 2024 - La charge de la cavalerie"
    end

    test "generates alt text without photo title using hash preview" do
      photo = %{title: nil, hash: "abc123def456", exif_data: nil}
      album = %{title: "Waterloo 2024"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Waterloo 2024 - photo-abc123d"
    end

    test "generates alt text with empty string title using hash preview" do
      photo = %{title: "", hash: "abc123def456", exif_data: nil}
      album = %{title: "Waterloo 2024"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Waterloo 2024 - photo-abc123d"
    end

    test "generates alt text with whitespace-only title using hash preview" do
      photo = %{title: "   ", hash: "abc123def456", exif_data: nil}
      album = %{title: "Waterloo 2024"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Waterloo 2024 - photo-abc123d"
    end

    test "truncates hash to 7 characters" do
      photo = %{title: nil, hash: "abcdefghijklmnop", exif_data: nil}
      album = %{title: "Test Album"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Test Album - photo-abcdefg"
    end

    test "handles short hash" do
      photo = %{title: nil, hash: "abc", exif_data: nil}
      album = %{title: "Test Album"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Test Album - photo-abc"
    end

    test "handles nil hash" do
      photo = %{title: nil, hash: nil, exif_data: nil}
      album = %{title: "Test Album"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Test Album - photo-unknown"
    end

    test "includes city from EXIF data" do
      photo = %{
        title: "La charge",
        hash: "abc123",
        exif_data: %{"City" => "Waterloo"}
      }

      album = %{title: "Reconstitution 2024"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "Reconstitution 2024 - La charge, Waterloo"
    end

    test "includes city and country from EXIF data" do
      photo = %{
        title: "La charge",
        hash: "abc123",
        exif_data: %{"City" => "Waterloo", "Country" => "Belgium"}
      }

      album = %{title: "Reconstitution 2024"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "Reconstitution 2024 - La charge, Waterloo, Belgium"
    end

    test "includes city, state, and country from EXIF data" do
      photo = %{
        title: "Tranchées",
        hash: "abc123",
        exif_data: %{"City" => "Verdun", "State" => "Meuse", "Country" => "France"}
      }

      album = %{title: "1914-1918"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "1914-1918 - Tranchées, Verdun, Meuse, France"
    end

    test "includes city and state from EXIF data" do
      photo = %{
        title: "Portrait",
        hash: "abc123",
        exif_data: %{"City" => "Paris", "State" => "Île-de-France"}
      }

      album = %{title: "Street Photography"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "Street Photography - Portrait, Paris, Île-de-France"
    end

    test "includes state and country from EXIF data" do
      photo = %{
        title: "Landscape",
        hash: "abc123",
        exif_data: %{"State" => "Picardie", "Country" => "France"}
      }

      album = %{title: "Nature"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "Nature - Landscape, Picardie, France"
    end

    test "includes only state from EXIF data" do
      photo = %{
        title: "Photo",
        hash: "abc123",
        exif_data: %{"State" => "Normandie"}
      }

      album = %{title: "Travel"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Travel - Photo, Normandie"
    end

    test "includes only country from EXIF data" do
      photo = %{
        title: "Photo",
        hash: "abc123",
        exif_data: %{"Country" => "France"}
      }

      album = %{title: "Travel"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Travel - Photo, France"
    end

    test "uses Province instead of State if available" do
      photo = %{
        title: "Photo",
        hash: "abc123",
        exif_data: %{"City" => "Montreal", "Province" => "Quebec", "Country" => "Canada"}
      }

      album = %{title: "Canada Trip"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "Canada Trip - Photo, Montreal, Quebec, Canada"
    end

    test "prefers State over Province if both present" do
      photo = %{
        title: "Photo",
        hash: "abc123",
        exif_data: %{
          "City" => "Test",
          "State" => "StateValue",
          "Province" => "ProvinceValue"
        }
      }

      album = %{title: "Test Album"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "Test Album - Photo, Test, StateValue"
    end

    test "handles empty EXIF map" do
      photo = %{title: "Photo", hash: "abc123", exif_data: %{}}
      album = %{title: "Album"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Album - Photo"
    end

    test "handles EXIF data with empty string values" do
      photo = %{
        title: "Photo",
        hash: "abc123",
        exif_data: %{"City" => "", "Country" => ""}
      }

      album = %{title: "Album"}

      # Empty strings are falsy in map access context, should not include location
      assert ImageHelpers.generate_alt_text(photo, album) == "Album - Photo"
    end

    test "handles non-map EXIF data" do
      photo = %{title: "Photo", hash: "abc123", exif_data: "invalid"}
      album = %{title: "Album"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Album - Photo"
    end
  end

  describe "generate_album_cover_alt/1" do
    test "generates alt text with photo count" do
      album = %{title: "Reconstitution Waterloo", photo_count: 42}

      assert ImageHelpers.generate_album_cover_alt(album) == "Reconstitution Waterloo - 42 photos"
    end

    test "generates alt text with single photo" do
      album = %{title: "Test Album", photo_count: 1}

      assert ImageHelpers.generate_album_cover_alt(album) == "Test Album - 1 photos"
    end

    test "generates alt text without count when zero photos" do
      album = %{title: "Empty Album", photo_count: 0}

      assert ImageHelpers.generate_album_cover_alt(album) == "Empty Album"
    end

    test "generates alt text without count when photo_count missing" do
      album = %{title: "Album Without Count"}

      assert ImageHelpers.generate_album_cover_alt(album) == "Album Without Count"
    end

    test "generates alt text with large photo count" do
      album = %{title: "Big Collection", photo_count: 1500}

      assert ImageHelpers.generate_album_cover_alt(album) == "Big Collection - 1500 photos"
    end
  end

  describe "edge cases and integration" do
    test "handles album with special characters" do
      photo = %{title: "Test", hash: "abc123", exif_data: nil}
      album = %{title: "L'été à Paris - 2024"}

      assert ImageHelpers.generate_alt_text(photo, album) == "L'été à Paris - 2024 - Test"
    end

    test "handles photo title with special characters" do
      photo = %{title: "Château & églises", hash: "abc123", exif_data: nil}
      album = %{title: "Architecture"}

      assert ImageHelpers.generate_alt_text(photo, album) == "Architecture - Château & églises"
    end

    test "handles very long titles" do
      long_title = String.duplicate("A very long title ", 20)
      photo = %{title: long_title, hash: "abc123", exif_data: nil}
      album = %{title: "Album"}

      result = ImageHelpers.generate_alt_text(photo, album)
      assert String.starts_with?(result, "Album - #{long_title}")
    end

    test "complete workflow with all data present" do
      photo = %{
        title: "La cavalerie française",
        hash: "abc123def456ghi789",
        exif_data: %{
          "City" => "Waterloo",
          "State" => "Walloon Brabant",
          "Country" => "Belgium"
        }
      }

      album = %{title: "Reconstitution Napoléonienne 2024"}

      assert ImageHelpers.generate_alt_text(photo, album) ==
               "Reconstitution Napoléonienne 2024 - La cavalerie française, Waterloo, Walloon Brabant, Belgium"
    end

    test "album cover with complete data" do
      album = %{
        title: "Festival Médiéval de Provins",
        photo_count: 156
      }

      assert ImageHelpers.generate_album_cover_alt(album) ==
               "Festival Médiéval de Provins - 156 photos"
    end
  end
end
