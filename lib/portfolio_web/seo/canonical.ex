defmodule PortfolioWeb.SEO.Canonical do
  @moduledoc """
  Adresses canoniques vers la plateforme photo.

  `photo.thibaultsan.com` sert le même catalogue que la plateforme. Deux
  adresses pour un même contenu, c'est du contenu dupliqué, et le moteur en
  choisit une lui-même. La canonique désigne explicitement la plateforme
  comme l'adresse de référence.

  La canonique d'un album n'est **pas** construite ici : elle est fournie
  telle quelle par l'API (`Album.canonical_url`). Une réorganisation des URL
  de la plateforme ne demande alors aucun déploiement du portfolio. Seules
  les pages qui n'ont pas d'équivalent dans l'API, l'accueil et les pages de
  thème, sont construites à partir de la racine configurée.
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
  Canonique d'une page de thème.
  """
  @spec theme(String.t()) :: String.t()
  def theme(slug) when is_binary(slug), do: base() <> "/galeries/" <> slug
end
