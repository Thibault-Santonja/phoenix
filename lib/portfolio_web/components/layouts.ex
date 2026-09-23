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

  # Marque l'entree de navigation correspondant au titre de la page courante
  # (`aria-current="page"`, WCAG 2.2 SC 2.4.8). `nil` omet l'attribut : les
  # autres entrees restent non marquees.
  @spec admin_nav_current?(map(), String.t()) :: String.t() | nil
  def admin_nav_current?(assigns, title) do
    if Map.get(assigns, :page_title) == title, do: "page"
  end
end
