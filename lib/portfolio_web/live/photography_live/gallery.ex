defmodule PortfolioWeb.PhotographyLive.Gallery do
  @moduledoc """
  Page d'album : les photos d'un album publié par la plateforme photo.

  L'album n'appartient pas au portfolio. Il est lu par le port
  `AlbumCatalogPort`, qui porte à lui seul le cache et la dégradation : cette
  vue ne connaît ni HTTP, ni cache, ni instantané. Elle ne traite que trois
  réponses.

  - Un album : la page s'affiche, et sa canonique désigne la plateforme.
  - `:not_found` : 404. Inventer un contenu de remplacement serait mentir au
    visiteur et au moteur.
  - `:unavailable` : la page s'affiche quand même, avec un message explicite
    et un chemin vers la chronologie, en 200. Jamais de page vide, jamais
    d'erreur.

  Les images ne transitent pas par le portfolio : les URL sont absolues et
  pointent vers le stockage objet de la plateforme, en AVIF puis WebP, avec
  un JPEG en dernier recours.
  """

  use PortfolioWeb, :live_view

  import PortfolioWeb.Components.ThemeButton

  alias Portfolio.Photography.Catalog.Photo
  alias Portfolio.Photography.Ports.AlbumCatalogPort
  alias PortfolioWeb.AlbumNotFoundError

  # Les quatre presets responsives exposés par la plateforme, du plus léger au
  # plus lourd. L'ordre est celui du `srcset`.
  @presets ~w(thumbnail medium large full)

  @impl true
  def mount(params, session, socket) do
    locale = Map.get(params, "hl", session["locale"] || "fr")
    _ = Gettext.put_locale(PortfolioWeb.Gettext, locale)

    socket = assign(socket, language: locale)

    case Map.get(params, "chapter") do
      nil ->
        # Sans album demandé, il n'y a rien à montrer ici : la chronologie est
        # l'index des albums.
        {:ok, push_navigate(socket, to: ~p"/timeline")}

      slug ->
        {:ok, load_album(socket, slug, locale)}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  @impl true
  def handle_event("show_project", %{"project" => index}, socket) do
    {:noreply, select_photo(socket, index)}
  end

  @impl true
  def handle_event("change_locale", %{"locale" => locale}, socket) do
    {:noreply,
     socket
     |> push_event("change_locale", %{"locale" => locale})
     |> assign(language: locale)}
  end

  # ============================================================================
  # Lecture du catalogue
  # ============================================================================

  defp load_album(socket, slug, locale) do
    case AlbumCatalogPort.get_album(slug, locale: locale) do
      {:ok, album} ->
        socket
        |> assign(album: album, photos: album.photos, unavailable: false)
        |> assign(pictures: length(album.photos))
        |> assign(canonical_url: album.canonical_url)
        |> select_photo("0")

      {:error, :not_found} ->
        raise AlbumNotFoundError, message: "album introuvable ou non publie : #{slug}"

      {:error, :unavailable} ->
        socket
        |> assign(album: nil, photos: [], unavailable: true)
        |> assign(pictures: 0, photo: nil, project_id: "0")
        |> assign(page_title: gettext("photography.page_title"))
        |> assign(meta_description: gettext("layouts.photography.description"))
    end
  end

  defp apply_action(socket, :index, %{"project" => index}) do
    select_photo(socket, index)
  end

  defp apply_action(socket, :index, _params), do: socket

  defp select_photo(%{assigns: %{unavailable: true}} = socket, _index), do: socket

  defp select_photo(socket, index) do
    photos = socket.assigns.photos
    position = parse_index(index, length(photos))
    photo = Enum.at(photos, position)
    album = socket.assigns.album

    socket
    |> assign(photo: photo, project_id: Integer.to_string(position))
    |> assign(page_title: gettext("photography.brand") <> " - " <> album.title)
    |> assign(meta_description: album.description || album.title)
  end

  defp parse_index(_index, 0), do: 0

  defp parse_index(index, count) when is_binary(index) do
    case Integer.parse(index) do
      {position, ""} when position >= 0 and position < count -> position
      _autre -> 0
    end
  end

  # ============================================================================
  # Présentation des images
  # ============================================================================

  @doc """
  Jeu de sources responsives d'une photo pour un format donné.
  """
  @spec srcset(Photo.t(), String.t()) :: String.t() | nil
  def srcset(photo, format), do: Photo.srcset(photo, format, @presets)

  @doc """
  URL posée dans l'attribut `src`, pour les navigateurs qui ne lisent pas
  `srcset`.
  """
  @spec fallback_url(Photo.t()) :: String.t() | nil
  def fallback_url(photo), do: Photo.fallback_url(photo, "large")

  @doc """
  URL d'une vignette de la bande de sélection.
  """
  @spec thumbnail_url(Photo.t()) :: String.t() | nil
  def thumbnail_url(photo), do: Photo.fallback_url(photo, "thumbnail")

  @doc """
  Rapport largeur sur hauteur de l'original, pose sur l'image pour réserver sa
  place avant le chargement et éviter tout décalage de mise en page.
  """
  @spec aspect_ratio(Photo.t()) :: String.t() | nil
  def aspect_ratio(%Photo{width: width, height: height})
      when is_integer(width) and is_integer(height) and height > 0 do
    "#{width} / #{height}"
  end

  def aspect_ratio(_photo), do: nil
end
