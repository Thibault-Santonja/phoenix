defmodule Portfolio.Photography.Catalog.PhotoTest do
  use ExUnit.Case, async: true

  import PortfolioTest.Fixtures.CatalogFixtures

  alias Portfolio.Photography.Catalog.Decoder
  alias Portfolio.Photography.Catalog.Photo
  alias Portfolio.Photography.Catalog.Source

  setup do
    {:ok, album} = Decoder.decode_album(album_detail_response())
    %{photo: hd(album.photos)}
  end

  describe "source/3" do
    test "retourne le premier format disponible dans l'ordre demande", %{photo: photo} do
      assert %Source{format: "avif", preset: "medium"} =
               Photo.source(photo, "medium", ["avif", "webp"])
    end

    test "retombe sur le format suivant quand le premier manque", %{photo: photo} do
      assert %Source{format: "webp"} = Photo.source(photo, "medium", ["jpeg", "webp"])
    end

    test "retourne nil quand aucun format ne convient", %{photo: photo} do
      assert Photo.source(photo, "medium", ["jpeg"]) == nil
    end

    test "retourne nil pour un preset inconnu", %{photo: photo} do
      assert Photo.source(photo, "gigantesque", ["avif"]) == nil
    end
  end

  describe "fallback_url/2" do
    test "prefere le JPEG, le seul format que tous les navigateurs lisent", %{photo: photo} do
      assert Photo.fallback_url(photo, "large") =~ "large/photo.jpeg"
    end

    test "retombe sur le WebP quand le JPEG n'existe pas pour ce preset", %{photo: photo} do
      assert Photo.fallback_url(photo, "thumbnail") =~ "thumbnail/photo.webp"
    end

    test "retourne nil pour un preset inconnu", %{photo: photo} do
      assert Photo.fallback_url(photo, "gigantesque") == nil
    end
  end

  describe "srcset/3" do
    test "assemble les descripteurs de largeur dans l'ordre des presets", %{photo: photo} do
      assert Photo.srcset(photo, "avif", ["thumbnail", "medium", "large", "full"]) ==
               "https://cdn.thibaultsan.com/variants/thumbnail/photo.avif 400w, " <>
                 "https://cdn.thibaultsan.com/variants/medium/photo.avif 800w, " <>
                 "https://cdn.thibaultsan.com/variants/large/photo.avif 1600w, " <>
                 "https://cdn.thibaultsan.com/variants/full/photo.avif 2400w"
    end

    test "omet les presets absents du format demande", %{photo: photo} do
      assert Photo.srcset(photo, "jpeg", ["thumbnail", "large"]) =~ "large/photo.jpeg 1600w"
      refute Photo.srcset(photo, "jpeg", ["thumbnail", "large"]) =~ "thumbnail"
    end

    test "retourne nil quand le format est absent de bout en bout", %{photo: photo} do
      assert Photo.srcset(photo, "heic", ["thumbnail", "medium"]) == nil
    end
  end
end
