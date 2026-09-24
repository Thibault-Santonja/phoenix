defmodule PortfolioWeb.PhotographyLive.Timeline do
  @moduledoc """
  Chronologie : l'index des albums publiés par la plateforme photo.

  Les albums sont lus par le port `AlbumCatalogPort`, qui porte le cache et
  l'échelle de dégradation. Cette vue ne traite que trois réponses.

  - Une page d'albums : elle s'affiche, par tranches de vingt, chargées à la
    demande au défilement.
  - `:not_found` : le thème demandé n'existe pas, donc 404. Rendre une liste
    vide masquerait une faute de frappe dans l'adresse. Sur la chronologie
    complète, rien n'a été nommé qui puisse manquer : le cas y est traité
    comme une panne, en 200.
  - `:unavailable` : la page s'affiche quand même, avec un message explicite,
    en 200.

  La liste des années affichée dans la navigation est déduite des albums
  chargés : l'API ne l'expose pas. Elle s'étoffe donc au fil du défilement.

  Les albums sont lus à l'affichage initial comme à la connexion du socket,
  et non seulement à la connexion : la page est ainsi complète sans
  JavaScript, et un thème inconnu répond bien 404 à un robot. La lecture a
  lieu une fois le chapitre connu, donc dans `handle_params/3` et non dans
  `mount/3`.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography.Catalog.Album
  alias Portfolio.Photography.Catalog.Photo
  alias Portfolio.Photography.Ports.AlbumCatalogPort
  alias PortfolioWeb.AlbumNotFoundError
  alias PortfolioWeb.SEO.Canonical

  @albums_per_page Application.compile_env(:portfolio, [:timeline, :albums_per_page], 20)

  # Presets responsives utilisés pour la vignette de couverture. La couverture
  # occupe au plus trois colonnes sur cinq : le preset `full` n'y sert a rien.
  @cover_presets ~w(thumbnail medium large)

  @impl true
  def mount(_params, session, socket) do
    locale = session["locale"] || "fr"
    _ = Gettext.put_locale(PortfolioWeb.Gettext, locale)

    # Le catalogue n'est pas lu ici : le chapitre n'est connu qu'à
    # `handle_params/3`, et lire avant lui reviendrait à demander la liste non
    # filtrée pour la jeter aussitôt. Une page de thème coûterait alors deux
    # fois plus d'appels, et une entrée de cache de plus, que la chronologie
    # complète.
    {:ok,
     socket
     |> assign(locale: locale, chapter: nil, catalogue_lu: false)
     |> assign(years: [], page: 1, has_more: true, albums_loaded: 0, unavailable: false)
     # Le slug est l'identité stable d'un album côté plateforme : c'est lui
     # qui doit porter l'identifiant de flux, pas un identifiant de base que
     # le catalogue n'expose pas.
     |> stream_configure(:albums, dom_id: &"album-#{&1.slug}")
     |> stream(:albums, [])}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply, push_event(socket, "change_locale", %{"locale" => locale})}
  end

  @impl true
  def handle_event("load_more", _params, socket) do
    if socket.assigns.has_more do
      {:noreply, load_albums(socket, socket.assigns.page + 1)}
    else
      {:noreply, socket}
    end
  end

  defp apply_action(socket, :index, params) do
    chapter = Map.get(params, "chapter")

    if socket.assigns.catalogue_lu and socket.assigns.chapter == chapter do
      socket
    else
      socket
      |> assign(chapter: chapter, catalogue_lu: true, page_title: build_title(chapter))
      |> put_canonical(chapter)
      |> assign(years: [], page: 1, has_more: true, albums_loaded: 0, unavailable: false)
      |> stream(:albums, [], reset: true)
      |> load_albums(1)
    end
  end

  # La canonique suit le chapitre : une page de thème du portfolio désigne la
  # page de thème correspondante de la plateforme, pas son accueil. Sans cela,
  # tous les chapitres se consolideraient sur la même adresse. La chronologie
  # complète, elle, garde la canonique posée par le plug de l'hôte.
  defp put_canonical(socket, nil), do: socket
  defp put_canonical(socket, chapter), do: assign(socket, canonical_url: Canonical.theme(chapter))

  defp build_title(nil), do: gettext("photography.timeline.title")

  defp build_title(chapter) do
    gettext("photography.timeline.gallery_prefix") <> String.capitalize(chapter)
  end

  # ============================================================================
  # Lecture du catalogue
  # ============================================================================

  defp load_albums(socket, page) do
    opts =
      [
        locale: socket.assigns.locale,
        # Une entrée de plus que la page demandée : c'est elle qui dit s'il
        # reste quelque chose à charger, sans réclamer un comptage.
        limit: @albums_per_page + 1,
        offset: (page - 1) * @albums_per_page
      ]
      |> maybe_put_theme(socket.assigns.chapter)

    case AlbumCatalogPort.list_albums(opts) do
      {:ok, %{albums: albums}} ->
        display(socket, page, albums)

      {:error, :not_found} ->
        theme_inconnu_ou_panne(socket)

      {:error, :unavailable} ->
        indisponible(socket)
    end
  end

  # Un thème demandé peut ne pas exister : c'est un 404. La chronologie
  # complète, elle, ne nomme rien qui puisse manquer : un `:not_found` ne peut
  # alors venir que d'une plateforme en panne ou d'une adresse mal configurée,
  # et la page doit dégrader en 200 comme le promet le palier 4.
  defp theme_inconnu_ou_panne(%{assigns: %{chapter: nil}} = socket), do: indisponible(socket)

  defp theme_inconnu_ou_panne(socket) do
    raise AlbumNotFoundError, message: "theme inconnu : #{socket.assigns.chapter}"
  end

  defp indisponible(socket), do: assign(socket, unavailable: true, has_more: false)

  defp maybe_put_theme(opts, nil), do: opts
  defp maybe_put_theme(opts, chapter), do: Keyword.put(opts, :theme, chapter)

  defp display(socket, page, albums) do
    {visibles, has_more} =
      if length(albums) > @albums_per_page do
        {Enum.take(albums, @albums_per_page), true}
      else
        {albums, false}
      end

    socket
    |> assign(page: page, has_more: has_more, unavailable: false)
    |> assign(albums_loaded: socket.assigns.albums_loaded + length(visibles))
    |> assign(years: merge_years(socket.assigns.years, visibles))
    |> stream(:albums, visibles)
  end

  defp merge_years(years, albums) do
    albums
    |> Enum.map(& &1.shoot_date)
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.year)
    |> Enum.concat(years)
    |> Enum.uniq()
    |> Enum.sort(:desc)
  end

  # ============================================================================
  # Présentation
  # ============================================================================

  @doc """
  Année de prise de vue d'un album, ou `nil` si la plateforme n'en fournit
  pas. Sert d'ancre de défilement.
  """
  @spec album_year(Album.t()) :: integer() | nil
  def album_year(%Album{shoot_date: %Date{year: year}}), do: year
  def album_year(_album), do: nil

  @doc """
  Période de prise de vue, sous forme de date unique ou de plage.
  """
  @spec date_range(Album.t()) :: String.t() | nil
  def date_range(%Album{shoot_date: nil}), do: nil
  def date_range(%Album{shoot_date: debut, shoot_end_date: nil}), do: Date.to_iso8601(debut)

  def date_range(%Album{shoot_date: debut, shoot_end_date: fin}) do
    Date.to_iso8601(debut) <> " - " <> Date.to_iso8601(fin)
  end

  @doc """
  Jeu de sources responsives de la couverture pour un format donné.
  """
  @spec cover_srcset(Photo.t(), String.t()) :: String.t() | nil
  def cover_srcset(photo, format), do: Photo.srcset(photo, format, @cover_presets)

  @doc """
  URL de la couverture posée dans l'attribut `src`.
  """
  @spec cover_url(Photo.t()) :: String.t() | nil
  def cover_url(photo), do: Photo.fallback_url(photo, "large")
end
