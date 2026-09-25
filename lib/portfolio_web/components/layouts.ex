defmodule PortfolioWeb.Layouts do
  @moduledoc """
  This module holds different layouts used by your application.

  See the `layouts` directory for all templates available.
  The "root" layout is a skeleton rendered as part of the
  application router. The "app" layout is set as the default
  layout on both `use PortfolioWeb, :controller` and
  `use PortfolioWeb, :live_view`.
  """
  use PortfolioWeb, :html

  embed_templates "layouts/*"

  # Coquille d'administration (layouts/admin.html.heex) : ces fonctions
  # portent la logique de presentation du shell (initiales, role, entree de
  # navigation courante), volontairement gardees hors du template heex.

  # Initiales du compte admin pour la vignette de la sidebar, derivees de
  # l'email (deux premiers caracteres alphanumeriques). Repli "TS" si l'email
  # est absent ou ne contient aucun caractere alphanumerique.
  @spec admin_initials(Portfolio.Auth.User.t() | nil) :: String.t()
  def admin_initials(%{email: email}) when is_binary(email) do
    email
    |> String.replace(~r/[^a-zA-Z0-9]/, "")
    |> String.slice(0, 2)
    |> String.upcase()
    |> case do
      "" -> "TS"
      initials -> initials
    end
  end

  def admin_initials(_), do: "TS"

  # Libelle du role affiche sous le nom du compte connecte.
  @spec admin_role_label(Portfolio.Auth.User.t() | nil) :: String.t()
  def admin_role_label(%{role: role}) when is_atom(role) and not is_nil(role) do
    role |> to_string() |> String.capitalize()
  end

  def admin_role_label(_), do: "Administrateur"

  # Source unique des entrees de navigation du backoffice : la barre laterale,
  # le menu mobile et le fil d'Ariane s'en servent tous, ce qui evite qu'une
  # entree ajoutee ici manque ailleurs.
  @spec admin_nav_groups() :: [
          %{id: String.t(), title: String.t(), items: [%{path: String.t(), label: String.t()}]}
        ]
  def admin_nav_groups do
    [
      %{
        id: "pilotage",
        title: gettext("admin.nav.group.pilotage"),
        items: [%{path: ~p"/admin", label: gettext("admin.nav.dashboard")}]
      },
      %{
        id: "galerie",
        title: gettext("admin.nav.group.gallery"),
        items: [
          %{path: ~p"/admin/albums", label: gettext("admin.nav.albums")},
          %{path: ~p"/admin/photos", label: gettext("admin.nav.photos")}
        ]
      },
      %{
        id: "compte",
        title: gettext("admin.nav.group.account"),
        items: [
          %{path: ~p"/admin/users", label: gettext("admin.nav.users")},
          %{path: ~p"/admin/profile", label: gettext("admin.nav.profile")},
          %{path: ~p"/admin/ip-whitelist", label: gettext("admin.nav.ip_whitelist")}
        ]
      }
    ]
  end

  # Entrees de navigation a plat, pour le menu mobile qui ne regroupe pas.
  @spec admin_nav_items() :: [%{path: String.t(), label: String.t()}]
  def admin_nav_items, do: Enum.flat_map(admin_nav_groups(), & &1.items)

  # Marque l'entree de navigation de la section courante (`aria-current="page"`,
  # WCAG 2.2 SC 2.4.8). La section est deduite du chemin courant (assign
  # `:current_path`, voir `PortfolioWeb.AdminNav`) et non du titre de page, qui
  # est une chaine traduite. `nil` omet l'attribut sur les autres entrees.
  @spec admin_nav_current?(map(), String.t()) :: String.t() | nil
  def admin_nav_current?(assigns, path) do
    section = admin_current_section(assigns)
    if section && section.path == path, do: "page"
  end

  # Fil d'Ariane reel : Administration, puis la section quand la page courante
  # n'est pas la page d'accueil de cette section, puis la page courante. Le
  # dernier maillon porte `aria-current="page"` et n'est pas un lien.
  @spec admin_crumbs(map()) :: [%{label: String.t(), path: String.t() | nil}]
  def admin_crumbs(assigns) do
    root_path = ~p"/admin"
    section = admin_current_section(assigns)
    current_path = Map.get(assigns, :current_path)
    page_title = Map.get(assigns, :page_title) || gettext("admin.shell.space")

    section_crumb =
      if section && section.path != root_path && section.path != current_path,
        do: [%{label: section.label, path: section.path}],
        else: []

    [%{label: gettext("admin.shell.space"), path: root_path}] ++
      section_crumb ++ [%{label: page_title, path: nil}]
  end

  # Section correspondant au chemin courant : l'entree dont le chemin est le
  # prefixe le plus long, pour que `/admin/albums/new` reste sous "Albums" sans
  # que `/admin` capture tout.
  defp admin_current_section(assigns) do
    current_path = Map.get(assigns, :current_path)

    admin_nav_items()
    |> Enum.sort_by(&byte_size(&1.path), :desc)
    |> Enum.find(&admin_section_match?(current_path, &1.path))
  end

  defp admin_section_match?(nil, _path), do: false

  defp admin_section_match?(current_path, path),
    do: current_path == path or String.starts_with?(current_path, path <> "/")
end
