defmodule Portfolio.Photography.Catalog.DecoderTest do
  use ExUnit.Case, async: true

  import PortfolioTest.Fixtures.CatalogFixtures

  alias Portfolio.Photography.Catalog.Album
  alias Portfolio.Photography.Catalog.Decoder
  alias Portfolio.Photography.Catalog.Photo
  alias Portfolio.Photography.Catalog.Source
  alias Portfolio.Photography.Catalog.Theme

  describe "decode_album_list/1" do
    test "transforme la charge utile en résumés d'albums" do
      assert {:ok, page} = Decoder.decode_album_list(album_list_response())

      assert %{total: 1, limit: 50, offset: 0, locale: "fr"} = page.meta
      assert [%Album{} = album] = page.albums

      assert album.slug == "mariage-claire-et-damien"
      assert album.title == "Mariage de Claire et Damien"
      assert album.location == "Coucy-le-Chateau"
      assert album.shoot_date == ~D[2024-06-15]
      assert album.shoot_end_date == ~D[2024-06-16]
      assert album.reference_url == "https://exemple.test/claire-damien"
      assert album.photo_count == 42

      assert album.canonical_url ==
               "https://photography.thibaultsan.com/albums/mariage-claire-et-damien"

      assert %Theme{slug: "wedding", name: "Mariage"} = album.theme
      assert %Photo{} = album.cover
      assert album.photos == []
    end

    test "accepte un album sans couverture, sans dates de fin et sans lien de référence" do
      payload =
        album_list_response(
          albums: [album_payload(cover: nil, shoot_end_date: nil, reference_url: nil)]
        )

      assert {:ok, %{albums: [album]}} = Decoder.decode_album_list(payload)
      assert album.cover == nil
      assert album.shoot_end_date == nil
      assert album.reference_url == nil
    end

    test "refuse une charge utile dont la clé data n'est pas une liste" do
      assert {:error, :invalid_payload} = Decoder.decode_album_list(%{"data" => "nope"})
    end

    test "refuse un album ampute de son slug" do
      payload = album_list_response(albums: [Map.delete(album_payload(), "slug")])

      assert {:error, :invalid_payload} = Decoder.decode_album_list(payload)
    end

    test "refuse une date de prise de vue illisible" do
      payload = album_list_response(albums: [album_payload(shoot_date: "pas-une-date")])

      assert {:error, :invalid_payload} = Decoder.decode_album_list(payload)
    end
  end

  describe "decode_album/1" do
    test "transforme la charge utile en album complet, photos triées par position" do
      payload =
        album_detail_response(
          photos: [
            photo_payload(id: "b", position: 2, alt: "Seconde"),
            photo_payload(id: "a", position: 1, alt: "Premiere")
          ]
        )

      assert {:ok, %Album{} = album} = Decoder.decode_album(payload)
      assert Enum.map(album.photos, & &1.alt) == ["Premiere", "Seconde"]

      photo = hd(album.photos)
      assert photo.id == "a"
      assert photo.width == 4000
      assert photo.height == 2667
      assert photo.blurhash == "LEHV6nWB2yk8pyo0adR*.7kCMdnj"
      assert length(photo.sources) == 9
      assert %Source{preset: "thumbnail", format: "avif", width: 400} = hd(photo.sources)
    end

    test "refuse une photo sans texte alternatif exploitable" do
      payload = album_detail_response(photos: [photo_payload(alt: "   ")])

      assert {:error, :invalid_payload} = Decoder.decode_album(payload)
    end

    test "refuse une photo privee de sources" do
      payload = album_detail_response(photos: [photo_payload(sources: [])])

      assert {:error, :invalid_payload} = Decoder.decode_album(payload)
    end
  end

  describe "decode_theme_list/1" do
    test "transforme la charge utile en thèmes ordonnes" do
      assert {:ok, themes} = Decoder.decode_theme_list(theme_list_response())

      assert [%Theme{slug: "wedding", name: "Mariage", position: 1, album_count: 12}, second] =
               themes

      assert second.slug == "reenactment"
      assert second.description == nil
    end

    test "refuse un thème sans slug" do
      payload = theme_list_response(themes: [%{"name" => "Mariage"}])

      assert {:error, :invalid_payload} = Decoder.decode_theme_list(payload)
    end
  end

  describe "refus des charges utiles hors contrat" do
    # Ces cas ne viennent pas d'une plateforme saine : ils viennent d'une
    # plateforme en panne, d'un mandataire qui renvoie une page d'erreur, ou
    # d'un instantané écrit par une version antérieure. Le décodeur doit les
    # refuser franchement, pas fabriquer un album à moitié rempli.

    test "refuse un album dont la charge utile n'est pas un objet" do
      assert {:error, :invalid_payload} = Decoder.decode_album(%{"data" => "pas un objet"})
      assert {:error, :invalid_payload} = Decoder.decode_album("pas un objet")
    end

    test "refuse une liste de thèmes qui n'en est pas une" do
      assert {:error, :invalid_payload} = Decoder.decode_theme_list(%{"data" => "pas une liste"})
      assert {:error, :invalid_payload} = Decoder.decode_theme_list([])
    end

    test "refuse un album qui n'est pas un objet dans la liste" do
      assert {:error, :invalid_payload} = Decoder.decode_album_list(%{"data" => ["pas un objet"]})
    end

    test "refuse une photo qui n'est pas un objet" do
      payload = album_detail_response(photos: ["pas un objet"])

      assert {:error, :invalid_payload} = Decoder.decode_album(payload)
    end

    test "refuse une source qui n'est pas un objet" do
      payload = album_detail_response(photos: [photo_payload(sources: ["pas un objet"])])

      assert {:error, :invalid_payload} = Decoder.decode_album(payload)
    end

    test "refuse une liste de sources qui n'en est pas une" do
      payload = album_detail_response(photos: [photo_payload(sources: "pas une liste")])

      assert {:error, :invalid_payload} = Decoder.decode_album(payload)
    end

    test "refuse une source privée de dimensions" do
      source = Map.delete(source_payload("large", "jpeg", 1600, 1067), "width")
      payload = album_detail_response(photos: [photo_payload(sources: [source])])

      assert {:error, :invalid_payload} = Decoder.decode_album(payload)
    end

    test "refuse un thème qui n'est pas un objet" do
      payload = theme_list_response(themes: ["pas un objet"])

      assert {:error, :invalid_payload} = Decoder.decode_theme_list(payload)
    end

    test "refuse une date qui n'est pas une chaîne" do
      payload = album_list_response(albums: [album_payload(shoot_date: 20_240_615)])

      assert {:error, :invalid_payload} = Decoder.decode_album_list(payload)
    end

    test "refuse un horodatage illisible" do
      payload = album_list_response(albums: [album_payload(published_at: "hier")])

      assert {:error, :invalid_payload} = Decoder.decode_album_list(payload)
    end

    test "refuse un horodatage qui n'est pas une chaîne" do
      payload = album_list_response(albums: [album_payload(updated_at: 1_720_000_000)])

      assert {:error, :invalid_payload} = Decoder.decode_album_list(payload)
    end
  end

  describe "métadonnées de liste" do
    test "se passe d'un bloc meta absent plutôt que d'échouer" do
      assert {:ok, page} = Decoder.decode_album_list(%{"data" => []})

      assert page.meta == %{
               total: nil,
               limit: nil,
               offset: nil,
               locale: nil,
               generated_at: nil
             }
    end

    test "ignore un bloc meta qui n'est pas un objet" do
      assert {:ok, page} = Decoder.decode_album_list(%{"data" => [], "meta" => "rien"})

      assert page.meta.total == nil
    end
  end
end
