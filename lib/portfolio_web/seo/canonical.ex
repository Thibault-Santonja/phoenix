defmodule PortfolioWeb.SEO.Canonical do
  @moduledoc """
  Adresses canoniques vers la plateforme photo.

  `photo.thibaultsan.com` sert le meme catalogue que la plateforme. Deux
  adresses pour un meme contenu, c'est du contenu duplique, et le moteur en
  choisit une lui-meme. La canonique designe explicitement la plateforme
  comme l'adresse de reference.

  La canonique d'un album n'est **pas** construite ici : elle est fournie
  telle quelle par l'API (`Album.canonical_url`). Une reorganisation des URL
  de la plateforme ne demande alors aucun deploiement du portfolio. Seules
  les pages qui n'ont pas d'equivalent dans l'API, l'accueil et les pages de
  theme, sont construites a partir de la racine configuree.
  """

  @default_base "https://photography.thibaultsan.com"

  @doc """
  Racine de la plateforme photo.
  """
  @spec base() :: String.t()
  def base do
    :portfolio
    |> Application.get_env(:album_catalog, [])
    |> Keyword.get(:platform_url, @default_base)
    |> String.trim_trailing("/")
  end

  @doc """
  Canonique de l'accueil.
  """
  @spec home() :: String.t()
  def home, do: base()

  @doc """
  Canonique d'une page de theme.
  """
  @spec theme(String.t() | nil) :: String.t()
  def theme(nil), do: home()
  def theme(slug) when is_binary(slug), do: base() <> "/galeries/" <> slug
end
