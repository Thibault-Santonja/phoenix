defmodule Portfolio.Photography.Ports.AlbumCatalogPort do
  @moduledoc """
  Port de sortie vers le catalogue d'albums publiés.

  La plateforme photo reste seule détentrice des albums ; le portfolio les
  lit. Ce port est le seul point par lequel la lecture passe : la couche web
  ne connaît ni HTTP, ni cache, ni instantané sur disque, seulement ces trois
  fonctions et leurs contrats d'erreur.

  ## Adaptateurs

  - `Portfolio.Photography.Adapters.HttpAlbumCatalogAdapter` : l'appel réseau
    vers l'API publique de la plateforme.
  - `Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter` : décorateur
    qui ajoute le cache et l'échelle de dégradation autour d'un autre
    adaptateur. C'est celui qui est configuré en production.
  - `PortfolioTest.Support.ScriptedCatalogAdapter` : catalogue piloté depuis
    le test, pour les cas qui ne portent pas sur le transport.

  ## Configuration

      config :portfolio, Portfolio.Photography.Ports.AlbumCatalogPort,
        adapter: Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter

  ## Contrat d'erreur

  Aucune fonction ne lève : une panne de la plateforme est un cas nominal du
  point de vue du portfolio.

  - `{:error, :not_found}` : l'album ou le thème demandé n'existe pas, ou
    n'est pas publié. La plateforme ne distingue pas les deux, et c'est
    voulu : l'existence d'un brouillon est elle-même une information.
  - `{:error, :unavailable}` : la plateforme n'a pas répondu, a répondu hors
    contrat, ou a répondu une erreur serveur. L'appelant affiche alors ce
    qu'il peut et ne montre jamais ni page vide ni erreur.
  """

  alias Portfolio.Photography.Catalog.Album
  alias Portfolio.Photography.Catalog.Theme

  @type list_opts :: [
          theme: String.t() | nil,
          locale: String.t() | nil,
          limit: pos_integer() | nil,
          offset: non_neg_integer() | nil
        ]

  @type page :: %{albums: [Album.t()], meta: map()}

  @type error :: :not_found | :unavailable

  @doc """
  Liste les albums publiés, du plus récent au plus ancien.
  """
  @callback list_albums(list_opts()) :: {:ok, page()} | {:error, error()}

  @doc """
  Retourne un album publié et ses photos triées par position.
  """
  @callback get_album(slug :: String.t(), opts :: keyword()) ::
              {:ok, Album.t()} | {:error, error()}

  @doc """
  Liste les thèmes du catalogue, ordonnes par position.
  """
  @callback list_themes(opts :: keyword()) :: {:ok, [Theme.t()]} | {:error, error()}

  # ============================================================================
  # Facade
  # ============================================================================

  @doc """
  Liste les albums publiés via l'adaptateur configuré.
  """
  @spec list_albums(list_opts()) :: {:ok, page()} | {:error, error()}
  def list_albums(opts \\ []), do: adapter().list_albums(opts)

  @doc """
  Retourne un album publié via l'adaptateur configuré.
  """
  @spec get_album(String.t(), keyword()) :: {:ok, Album.t()} | {:error, error()}
  def get_album(slug, opts \\ []) when is_binary(slug), do: adapter().get_album(slug, opts)

  @doc """
  Liste les thèmes via l'adaptateur configuré.
  """
  @spec list_themes(keyword()) :: {:ok, [Theme.t()]} | {:error, error()}
  def list_themes(opts \\ []), do: adapter().list_themes(opts)

  @doc """
  Retourne le module d'adaptateur configuré.
  """
  @spec adapter() :: module()
  def adapter do
    :portfolio
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:adapter, Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter)
  end
end
