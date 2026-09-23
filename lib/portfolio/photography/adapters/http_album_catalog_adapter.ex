defmodule Portfolio.Photography.Adapters.HttpAlbumCatalogAdapter do
  @moduledoc """
  Adaptateur HTTP vers l'API publique des albums de la plateforme photo.

  ## Ce qu'il fait, et ce qu'il ne fait pas

  Il parle, décode, et traduit les pannes en `{:error, :unavailable}`. Il ne
  met rien en cache et ne rejoue aucune requête : ces deux responsabilites
  appartiennent au décorateur `CachingAlbumCatalogAdapter`.

  L'absence de reprise est un choix, pas un oubli. Rejouer dans le chemin de
  la requête doublerait la latence d'une page déjà dégradée, pour une chance
  faible de succes : la plateforme est soit la, soit absente pour plus
  longtemps qu'un aller-retour. Le rafraîchissement se fait hors du chemin
  critique, dans le décorateur.

  ## Délais

  Deux secondes pour établir la connexion, cinq pour recevoir la réponse. Les
  deux applications tournent sur le même hôte, derrière le réseau Docker
  interne : ces valeurs sont larges, et c'est voulu, elles couvrent le cas ou
  la plateforme est vivante mais lente, pas le cas ou elle est absente, que
  l'échec de connexion tranche en quelques millisecondes.

  ## Configuration

      config :portfolio, :album_catalog,
        base_url: "http://photography:4000",
        connect_timeout: 2_000,
        receive_timeout: 5_000

  La clé `:req_options` permet d'injecter des options `Req` supplementaires,
  ce dont les tests se servent pour brancher un bouchon `Req.Test` à la place
  du réseau.
  """

  @behaviour Portfolio.Photography.Ports.AlbumCatalogPort

  require Logger

  alias Portfolio.Photography.Catalog.Decoder

  @default_base_url "http://localhost:4000"
  @default_connect_timeout 2_000
  @default_receive_timeout 5_000

  @impl true
  def list_albums(opts \\ []) do
    "/api/v1/albums"
    |> get(params: list_params(opts))
    |> decode_with(&Decoder.decode_album_list/1)
  end

  @impl true
  def get_album(slug, opts \\ []) when is_binary(slug) do
    "/api/v1/albums/#{URI.encode_www_form(slug)}"
    |> get(params: locale_params(opts))
    |> decode_with(&Decoder.decode_album/1)
  end

  @impl true
  def list_themes(opts \\ []) do
    "/api/v1/themes"
    |> get(params: locale_params(opts))
    |> decode_with(&Decoder.decode_theme_list/1)
  end

  # ============================================================================
  # Transport
  # ============================================================================

  defp get(path, request_opts) do
    [
      base_url: base_url(),
      url: path,
      method: :get,
      retry: false,
      # Pas de compression annoncée : l'appel reste sur le réseau interne de
      # l'hôte, où compresser ne fait gagner ni temps ni bande passante, et
      # où décompresser une réponse de taille inconnue est le seul risque
      # mémoire que ce chemin porte sur une machine à 4 Go.
      compressed: false,
      connect_options: [timeout: config(:connect_timeout, @default_connect_timeout)],
      receive_timeout: config(:receive_timeout, @default_receive_timeout),
      decode_json: [keys: :strings]
    ]
    |> Keyword.merge(request_opts)
    |> Keyword.merge(config(:req_options, []))
    |> Req.request()
  end

  defp decode_with({:ok, %Req.Response{status: 200, body: body}}, decoder) when is_map(body) do
    case decoder.(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, :invalid_payload} ->
        Logger.warning("catalogue : réponse hors contrat de la plateforme photo")
        {:error, :unavailable}
    end
  end

  defp decode_with({:ok, %Req.Response{status: 404}}, _decoder), do: {:error, :not_found}

  defp decode_with({:ok, %Req.Response{status: status}}, _decoder) do
    Logger.warning("catalogue : la plateforme photo a répondu #{status}")
    {:error, :unavailable}
  end

  defp decode_with({:error, reason}, _decoder) do
    Logger.warning("catalogue : appel impossible vers la plateforme photo (#{inspect(reason)})")
    {:error, :unavailable}
  end

  # ============================================================================
  # Paramètres
  # ============================================================================

  # Les paramètres absents sont omis de l'URL plutôt qu'envoyes vides : une
  # locale vide serait un paramètre invalide pour la plateforme, qui répond
  # alors 400 au lieu de servir le contenu par défaut.
  defp list_params(opts) do
    [
      theme: Keyword.get(opts, :theme),
      locale: Keyword.get(opts, :locale),
      limit: Keyword.get(opts, :limit),
      offset: Keyword.get(opts, :offset)
    ]
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp locale_params(opts) do
    case Keyword.get(opts, :locale) do
      nil -> []
      locale -> [locale: locale]
    end
  end

  defp base_url, do: config(:base_url, @default_base_url)

  defp config(key, default) do
    :portfolio
    |> Application.get_env(:album_catalog, [])
    |> Keyword.get(key, default)
  end
end
