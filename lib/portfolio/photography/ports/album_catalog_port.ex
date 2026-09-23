defmodule Portfolio.Photography.Ports.AlbumCatalogPort do
  @moduledoc """
  Port de sortie vers le catalogue d'albums publies.

  La plateforme photo reste seule detentrice des albums ; le portfolio les
  lit. Ce port est le seul point par lequel la lecture passe : la couche web
  ne connait ni HTTP, ni cache, ni instantane sur disque, seulement ces trois
  fonctions et leurs contrats d'erreur.

  ## Adaptateurs

  - `Portfolio.Photography.Adapters.HttpAlbumCatalogAdapter` : l'appel reseau
    vers l'API publique de la plateforme.
  - `Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter` : decorateur
    qui ajoute le cache et l'echelle de degradation autour d'un autre
    adaptateur. C'est celui qui est configure en production.
  - `Portfolio.Photography.Adapters.StubAlbumCatalogAdapter` : catalogue en
    dur, pour les tests qui ne portent pas sur le transport.

  ## Configuration

      config :portfolio, Portfolio.Photography.Ports.AlbumCatalogPort,
        adapter: Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter

  ## Contrat d'erreur

  Aucune fonction ne leve : une panne de la plateforme est un cas nominal du
  point de vue du portfolio.

  - `{:error, :not_found}` : l'album ou le theme demande n'existe pas, ou
    n'est pas publie. La plateforme ne distingue pas les deux, et c'est
    voulu : l'existence d'un brouillon est elle-meme une information.
  - `{:error, :unavailable}` : la plateforme n'a pas repondu, a repondu hors
    contrat, ou a repondu une erreur serveur. L'appelant affiche alors ce
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
  Liste les albums publies, du plus recent au plus ancien.
  """
  @callback list_albums(list_opts()) :: {:ok, page()} | {:error, error()}

  @doc """
  Retourne un album publie et ses photos triees par position.
  """
  @callback get_album(slug :: String.t(), opts :: keyword()) ::
              {:ok, Album.t()} | {:error, error()}

  @doc """
  Liste les themes du catalogue, ordonnes par position.
  """
  @callback list_themes(opts :: keyword()) :: {:ok, [Theme.t()]} | {:error, error()}

  # ============================================================================
  # Facade
  # ============================================================================

  @doc """
  Liste les albums publies via l'adaptateur configure.
  """
  @spec list_albums(list_opts()) :: {:ok, page()} | {:error, error()}
  def list_albums(opts \\ []), do: adapter().list_albums(opts)

  @doc """
  Retourne un album publie via l'adaptateur configure.
  """
  @spec get_album(String.t(), keyword()) :: {:ok, Album.t()} | {:error, error()}
  def get_album(slug, opts \\ []) when is_binary(slug), do: adapter().get_album(slug, opts)

  @doc """
  Liste les themes via l'adaptateur configure.
  """
  @spec list_themes(keyword()) :: {:ok, [Theme.t()]} | {:error, error()}
  def list_themes(opts \\ []), do: adapter().list_themes(opts)

  @doc """
  Retourne le module d'adaptateur configure.
  """
  @spec adapter() :: module()
  def adapter do
    :portfolio
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(:adapter, Portfolio.Photography.Adapters.CachingAlbumCatalogAdapter)
  end
end
