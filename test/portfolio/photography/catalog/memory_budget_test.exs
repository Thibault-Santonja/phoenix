defmodule Portfolio.Photography.Catalog.MemoryBudgetTest do
  @moduledoc """
  Garde le cout mémoire du cache de catalogue.

  Le serveur cible est une machine a 4 Go partagee entre les deux
  applications, la base, la supervision et la mesure d'audience. Le budget du
  portfolio est de l'ordre de 400 Mo : un cache de catalogue qui deraperait
  s'y verrait tout de suite.

  Ce test mesure au lieu de supposer. Les bornes sont larges à dessein : leur
  role n'est pas de figer un octet pres, c'est de faire échouer la CI le jour
  ou une photo coutera dix fois plus cher qu'aujourd'hui.
  """

  use ExUnit.Case, async: true

  import PortfolioTest.Fixtures.CatalogFixtures

  alias Portfolio.Photography.Catalog.Decoder

  # `:erts_debug.size/1` compte des mots machine ; huit octets sur un système
  # 64 bits.
  defp octets(terme), do: :erts_debug.size(terme) * 8

  # Mesure du 23/09/2026 : 2 200 octets pour une photo et ses neuf sources,
  # avec des URL de soixante caracteres. La conception tablait sur 1,7 ko :
  # l'écart vient de la longueur des URL, qui dominent la structure.
  test "une photo décodée, ses neuf sources comprises, tient sous 3 kilo-octets" do
    {:ok, album} = Decoder.decode_album(album_detail_response())
    [photo] = album.photos

    assert octets(photo) < 3_000
  end

  test "un album de quarante photos tient sous 100 kilo-octets" do
    photos = for position <- 1..40, do: photo_payload(id: "photo-#{position}", position: position)
    {:ok, album} = Decoder.decode_album(album_detail_response(photos: photos))

    assert length(album.photos) == 40
    assert octets(album) < 100_000
  end

  test "une liste de soixante résumés d'albums tient sous 200 kilo-octets" do
    albums = for numero <- 1..60, do: album_payload(slug: "album-#{numero}")
    {:ok, page} = Decoder.decode_album_list(album_list_response(albums: albums))

    assert length(page.albums) == 60
    assert octets(page) < 200_000
  end

  test "cent entrées de la taille d'une liste complète restent sous 20 megaoctets" do
    albums = for numero <- 1..60, do: album_payload(slug: "album-#{numero}")
    {:ok, page} = Decoder.decode_album_list(album_list_response(albums: albums))

    # Le plafond du cache est de cent entrées (voir Portfolio.Application).
    assert octets(page) * 100 < 20_000_000
  end
end
