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

  ## Ce qu'un 404 veut dire

  Il dépend de ce qui a été demandé. Une adresse qui nomme un thème ou un
  slug peut ne rien désigner : c'est `{:error, :not_found}`. Une adresse de
  collection (la liste complète des albums, la liste des thèmes) existe tant
  que la plateforme répond : un 404 dessus est une panne ou une adresse mal
  configurée, donc `{:error, :unavailable}`.

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
    |> decode_with(&Decoder.decode_album_list/1, sens_du_404(Keyword.get(opts, :theme)))
  end

  @impl true
  def get_album(slug, opts \\ []) when is_binary(slug) do
    "/api/v1/albums/#{URI.encode_www_form(slug)}"
    |> get(params: locale_params(opts))
    |> decode_with(&Decoder.decode_album/1, :not_found)
  end

  @impl true
  def list_themes(opts \\ []) do
    "/api/v1/themes"
    |> get(params: locale_params(opts))
    |> decode_with(&Decoder.decode_theme_list/1, :unavailable)
  end

  # Ce qu'un 404 veut dire, pour la requête qui vient d'être envoyée.
  #
  # Une adresse qui nomme quelque chose (un thème, un slug) peut
  # légitimement ne rien désigner : le 404 est alors une absence. Une adresse
  # de collection existe, elle, tant que la plateforme répond : un 404 dessus
  # ne dit rien du catalogue, il dit que la réponse ne vient pas de la
  # plateforme attendue, ou qu'elle est cassée. C'est une panne, donc le
  # palier 4, et une page en 200 plutôt qu'un 404.
  defp sens_du_404(nil), do: :unavailable
  defp sens_du_404(_identifiant), do: :not_found

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
      decoders: [json: &Jason.decode(&1, keys: :strings)]
    ]
    |> Keyword.merge(request_opts)
    |> Keyword.merge(config(:req_options, []))
    |> Req.request()
  end

  defp decode_with({:ok, %Req.Response{status: 200, body: body}}, decoder, _sens_du_404)
       when is_map(body) do
    case decoder.(body) do
      {:ok, decoded} ->
        {:ok, decoded}

      {:error, :invalid_payload} ->
        Logger.warning("catalogue : réponse hors contrat de la plateforme photo")
        {:error, :unavailable}
    end
  end

  defp decode_with({:ok, %Req.Response{status: 404}}, _decoder, :not_found) do
    {:error, :not_found}
  end

  defp decode_with({:ok, %Req.Response{status: 404}}, _decoder, :unavailable) do
    Logger.warning("catalogue : 404 sur une collection, la plateforme photo n'a pas répondu")
    {:error, :unavailable}
  end

  defp decode_with({:ok, %Req.Response{status: status}}, _decoder, _sens_du_404) do
    Logger.warning("catalogue : la plateforme photo a répondu #{status}")
    {:error, :unavailable}
  end

  defp decode_with({:error, reason}, _decoder, _sens_du_404) do
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
