defmodule PortfolioTest.Fixtures.CatalogFixtures do
  @moduledoc """
  Charges utiles JSON conformes au contrat de l'API publique des albums.

  Ces fixtures decrivent ce que la plateforme photo renvoie, telle qu'elle le
  renvoie : des cles binaires, des dates ISO 8601, aucune valeur deja decodee.
  Elles servent a la fois aux tests du decodeur, de l'adaptateur HTTP et de
  l'adaptateur en dur.
  """

  @doc """
  Une photo complete, avec ses neuf sources responsives.
  """
  @spec photo_payload(keyword()) :: map()
  def photo_payload(opts \\ []) do
    %{
      "id" => Keyword.get(opts, :id, "1f0a9b4e-6c2a-4f1e-9b7d-2c3a5d6e7f80"),
      "position" => Keyword.get(opts, :position, 1),
      "alt" => Keyword.get(opts, :alt, "Mariee sous un porche de pierre, lumiere rasante"),
      "caption" => Keyword.get(opts, :caption, "Sortie de ceremonie"),
      "credit" => Keyword.get(opts, :credit, "Thibault San"),
      "blurhash" => Keyword.get(opts, :blurhash, "LEHV6nWB2yk8pyo0adR*.7kCMdnj"),
      "width" => Keyword.get(opts, :width, 4000),
      "height" => Keyword.get(opts, :height, 2667),
      "sources" => Keyword.get(opts, :sources, sources_payload())
    }
  end

  @doc """
  Les neuf sources produites par les quatre presets responsives du contrat.
  """
  @spec sources_payload() :: [map()]
  def sources_payload do
    [
      source_payload("thumbnail", "avif", 400, 267),
      source_payload("thumbnail", "webp", 400, 267),
      source_payload("medium", "avif", 800, 533),
      source_payload("medium", "webp", 800, 533),
      source_payload("large", "avif", 1600, 1067),
      source_payload("large", "webp", 1600, 1067),
      source_payload("large", "jpeg", 1600, 1067),
      source_payload("full", "avif", 2400, 1600),
      source_payload("full", "webp", 2400, 1600)
    ]
  end

  @spec source_payload(String.t(), String.t(), pos_integer(), pos_integer()) :: map()
  def source_payload(preset, format, width, height) do
    %{
      "preset" => preset,
      "format" => format,
      "url" => "https://cdn.thibaultsan.com/variants/#{preset}/photo.#{format}",
      "width" => width,
      "height" => height,
      "bytes" => width * height
    }
  end

  @doc """
  Un resume d'album tel que renvoye par la liste.
  """
  @spec album_payload(keyword()) :: map()
  def album_payload(opts \\ []) do
    slug = Keyword.get(opts, :slug, "mariage-claire-et-damien")

    %{
      "slug" => slug,
      "title" => Keyword.get(opts, :title, "Mariage de Claire et Damien"),
      "description" => Keyword.get(opts, :description, "Une journee de juin au chateau de Coucy"),
      "location" => Keyword.get(opts, :location, "Coucy-le-Chateau"),
      "shoot_date" => Keyword.get(opts, :shoot_date, "2024-06-15"),
      "shoot_end_date" => Keyword.get(opts, :shoot_end_date, "2024-06-16"),
      "reference_url" => Keyword.get(opts, :reference_url, "https://exemple.test/claire-damien"),
      "published_at" => Keyword.get(opts, :published_at, "2024-07-01T09:30:00Z"),
      "updated_at" => Keyword.get(opts, :updated_at, "2024-07-02T18:00:00Z"),
      "theme" => Keyword.get(opts, :theme, %{"slug" => "wedding", "name" => "Mariage"}),
      "photo_count" => Keyword.get(opts, :photo_count, 42),
      "canonical_url" =>
        Keyword.get(opts, :canonical_url, "https://photography.thibaultsan.com/albums/#{slug}"),
      "cover" => Keyword.get(opts, :cover, photo_payload())
    }
  end

  @doc """
  La reponse complete de `GET /api/v1/albums`.
  """
  @spec album_list_response(keyword()) :: map()
  def album_list_response(opts \\ []) do
    albums = Keyword.get(opts, :albums, [album_payload()])

    %{
      "data" => albums,
      "meta" => %{
        "total" => Keyword.get(opts, :total, length(albums)),
        "limit" => Keyword.get(opts, :limit, 50),
        "offset" => Keyword.get(opts, :offset, 0),
        "locale" => Keyword.get(opts, :locale, "fr"),
        "generated_at" => Keyword.get(opts, :generated_at, "2024-07-02T18:00:00Z")
      }
    }
  end

  @doc """
  La reponse complete de `GET /api/v1/albums/:slug`.
  """
  @spec album_detail_response(keyword()) :: map()
  def album_detail_response(opts \\ []) do
    photos = Keyword.get(opts, :photos, [photo_payload()])

    album =
      opts
      |> album_payload()
      |> Map.put("photos", photos)

    %{
      "data" => album,
      "meta" => %{
        "locale" => Keyword.get(opts, :locale, "fr"),
        "generated_at" => Keyword.get(opts, :generated_at, "2024-07-02T18:00:00Z")
      }
    }
  end

  @doc """
  La reponse complete de `GET /api/v1/themes`.
  """
  @spec theme_list_response(keyword()) :: map()
  def theme_list_response(opts \\ []) do
    themes =
      Keyword.get(opts, :themes, [
        %{
          "slug" => "wedding",
          "name" => "Mariage",
          "description" => "Les mariages",
          "position" => 1,
          "album_count" => 12
        },
        %{
          "slug" => "reenactment",
          "name" => "Reconstitution",
          "description" => nil,
          "position" => 2,
          "album_count" => 5
        }
      ])

    %{
      "data" => themes,
      "meta" => %{"generated_at" => "2024-07-02T18:00:00Z"}
    }
  end
end
