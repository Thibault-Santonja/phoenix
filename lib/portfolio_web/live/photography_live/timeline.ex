defmodule PortfolioWeb.PhotographyLive.Timeline do
  @moduledoc """
  Chronologie : l'index des albums publies par la plateforme photo.

  Les albums sont lus par le port `AlbumCatalogPort`, qui porte le cache et
  l'echelle de degradation. Cette vue ne traite que trois reponses.

  - Une page d'albums : elle s'affiche, par tranches de vingt, chargees a la
    demande au defilement.
  - `:not_found` : le theme demande n'existe pas, donc 404. Rendre une liste
    vide masquerait une faute de frappe dans l'adresse.
  - `:unavailable` : la page s'affiche quand meme, avec un message explicite,
    en 200.

  La liste des annees affichee dans la navigation est deduite des albums
  charges : l'API ne l'expose pas. Elle s'etoffe donc au fil du defilement.

  Les albums sont lus a l'affichage initial comme a la connexion du socket,
  et non seulement a la connexion : la page est ainsi complete sans
  JavaScript, et un theme inconnu repond bien 404 a un robot.
  """

  use PortfolioWeb, :live_view

  alias Portfolio.Photography.Catalog.Album
  alias Portfolio.Photography.Catalog.Photo
  alias Portfolio.Photography.Ports.AlbumCatalogPort
  alias PortfolioWeb.AlbumNotFoundError

  @albums_per_page Application.compile_env(:portfolio, [:timeline, :albums_per_page], 20)

  # Presets responsives utilises pour la vignette de couverture. La couverture
  # occupe au plus trois colonnes sur cinq : le preset `full` n'y sert a rien.
  @cover_presets ~w(thumbnail medium large)

  @impl true
  def mount(_params, session, socket) do
    locale = session["locale"] || "fr"
    _ = Gettext.put_locale(PortfolioWeb.Gettext, locale)

    {:ok,
     socket
     |> assign(locale: locale, chapter: nil)
     |> assign(years: [], page: 1, has_more: true, albums_loaded: 0, unavailable: false)
     # Le slug est l'identite stable d'un album cote plateforme : c'est lui
     # qui doit porter l'identifiant de flux, pas un identifiant de base que
     # le catalogue n'expose pas.
     |> stream_configure(:albums, dom_id: &"album-#{&1.slug}")
     |> stream(:albums, [])
     |> load_albums(1)}
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

  defp apply_action(socket, :index, %{"chapter" => chapter}) do
    if socket.assigns.chapter == chapter do
      socket
    else
      socket
      |> assign(chapter: chapter, page_title: build_title(chapter))
      |> assign(years: [], page: 1, has_more: true, albums_loaded: 0, unavailable: false)
      |> stream(:albums, [], reset: true)
      |> load_albums(1)
    end
  end

  defp apply_action(socket, :index, _params) do
    assign(socket, page_title: gettext("photography.timeline.title"))
  end

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
        # Une entree de plus que la page demandee : c'est elle qui dit s'il
        # reste quelque chose a charger, sans reclamer un comptage.
        limit: @albums_per_page + 1,
        offset: (page - 1) * @albums_per_page
      ]
      |> maybe_put_theme(socket.assigns.chapter)

    case AlbumCatalogPort.list_albums(opts) do
      {:ok, %{albums: albums}} ->
        display(socket, page, albums)

      {:error, :not_found} ->
        raise AlbumNotFoundError, message: "theme inconnu : #{socket.assigns.chapter}"

      {:error, :unavailable} ->
        assign(socket, unavailable: true, has_more: false)
    end
  end

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
  # Presentation
  # ============================================================================

  @doc """
  Annee de prise de vue d'un album, ou `nil` si la plateforme n'en fournit
  pas. Sert d'ancre de defilement.
  """
  @spec album_year(Album.t()) :: integer() | nil
  def album_year(%Album{shoot_date: %Date{year: year}}), do: year
  def album_year(_album), do: nil

  @doc """
  Periode de prise de vue, sous forme de date unique ou de plage.
  """
  @spec date_range(Album.t()) :: String.t() | nil
  def date_range(%Album{shoot_date: nil}), do: nil
  def date_range(%Album{shoot_date: debut, shoot_end_date: nil}), do: Date.to_iso8601(debut)

  def date_range(%Album{shoot_date: debut, shoot_end_date: fin}) do
    Date.to_iso8601(debut) <> " - " <> Date.to_iso8601(fin)
  end

  @doc """
  Jeu de sources responsives de la couverture pour un format donne.
  """
  @spec cover_srcset(Photo.t(), String.t()) :: String.t() | nil
  def cover_srcset(photo, format), do: Photo.srcset(photo, format, @cover_presets)

  @doc """
  URL de la couverture posee dans l'attribut `src`.
  """
  @spec cover_url(Photo.t()) :: String.t() | nil
  def cover_url(photo), do: Photo.fallback_url(photo, "large")
end
