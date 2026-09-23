defmodule PortfolioWeb.Plugs.PhotoHostSeo do
  @moduledoc """
  Empeche l'indexation de `photo.thibaultsan.com`.

  Le site professionnel indexe est la plateforme photo. Le portfolio sert le
  meme catalogue sous `photo.`, en acces direct, et ne doit pas apparaitre
  dans les resultats de recherche : sans garde-fou, deux adresses servent le
  meme contenu et le moteur choisit lui-meme laquelle presenter.

  ## Pourquoi deux mecanismes plutot qu'un

  L'en-tete `X-Robots-Tag` et la balise `meta name="robots"` portent une
  **directive** : elles desindexent. La balise `link rel="canonical"` n'est
  qu'un **indice** de consolidation, que le moteur peut ignorer. On pose donc
  les deux : la directive pour sortir de l'index, la canonique pour que le
  signal de popularite aille a la plateforme.

  ## Pourquoi pas un `Disallow: /` dans robots.txt

  Un chemin interdit d'exploration empeche le robot de **lire** la directive
  `noindex`, donc de desindexer. Une page atteinte par un lien externe finit
  alors indexee sans extrait : le pire des deux mondes. Le robots.txt du
  portfolio n'interdit rien sur cet hote, c'est delibere.

  ## Portee

  Seul l'hote `photo.` est concerne. Les trois autres hotes servis par le
  portfolio restent indexables.
  """

  import Plug.Conn

  alias PortfolioWeb.SEO.Canonical

  @directive "noindex, follow"

  @doc false
  def init(opts), do: opts

  @doc false
  def call(%Plug.Conn{host: host} = conn, _opts) do
    if photo_host?(host) do
      conn
      |> put_resp_header("x-robots-tag", @directive)
      |> assign(:robots, @directive)
      |> assign(:canonical_url, Canonical.home())
    else
      conn
    end
  end

  @doc """
  Indique si `host` est l'hote non indexe du portfolio.
  """
  @spec photo_host?(String.t()) :: boolean()
  def photo_host?(host) when is_binary(host), do: String.starts_with?(host, "photo.")
  def photo_host?(_host), do: false
end
