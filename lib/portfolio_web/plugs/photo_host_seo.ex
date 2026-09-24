defmodule PortfolioWeb.Plugs.PhotoHostSeo do
  @moduledoc """
  Empêche l'indexation de `photo.thibaultsan.com`.

  Le site professionnel indexe est la plateforme photo. Le portfolio sert le
  même catalogue sous `photo.`, en accès direct, et ne doit pas apparaitre
  dans les resultats de recherche : sans garde-fou, deux adresses servent le
  même contenu et le moteur choisit lui-même laquelle presenter.

  ## Pourquoi deux mecanismes plutôt qu'un

  L'en-tete `X-Robots-Tag` et la balise `meta name="robots"` portent une
  **directive** : elles désindexent. La balise `link rel="canonical"` n'est
  qu'un **indice** de consolidation, que le moteur peut ignorer. On pose donc
  les deux : la directive pour sortir de l'index, la canonique pour que le
  signal de popularite aille à la plateforme.

  ## Pourquoi pas un `Disallow: /` dans robots.txt

  Un chemin interdit d'exploration empêche le robot de **lire** la directive
  `noindex`, donc de désindexer. Une page atteinte par un lien externe finit
  alors indexée sans extrait : le pire des deux mondes. Le robots.txt du
  portfolio n'interdit rien sur cet hôte, c'est délibéré.

  ## Portée

  Seul l'hôte `photo.` est concerne. Les trois autres hôtes servis par le
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
  Indique si `host` est l'hôte non indexe du portfolio.
  """
  @spec photo_host?(String.t()) :: boolean()
  def photo_host?(host), do: String.starts_with?(host, "photo.")
end
