defmodule PortfolioWeb.Admin.AdminShellTest do
  @moduledoc """
  Verifie que la coquille d'administration (barre laterale, fil d'Ariane,
  compte connecte) est rendue de facon homogene sur les pages du backoffice,
  en se rapprochant de la charte graphique de la plateforme photo.
  """

  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import PortfolioTest.Fixtures.AuthFixtures

  describe "coquille d'administration" do
    setup [:create_admin_user, :log_in_admin]

    test "affiche la barre laterale avec un lien vers chaque section du backoffice", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ ~s(class="app-side")

      for {path, _label} <- admin_sections() do
        assert html =~ path
      end
    end

    test "affiche le fil d'Ariane avec le titre de la page courante", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert html =~ ~s(class="app-crumbs")
      assert html =~ "Albums"
    end

    test "affiche le compte connecte dans la coquille", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ ~s(class="app-account")
      assert html =~ "admin@example.com"
    end

    test "ne duplique pas le bouton de retour au tableau de bord sur les pages internes", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      refute html =~ "Retour au tableau de bord"
    end
  end

  defp admin_sections do
    [
      {"/admin", "Tableau de bord"},
      {"/admin/albums", "Albums"},
      {"/admin/photos", "Photos"},
      {"/admin/users", "Utilisateurs"},
      {"/admin/profile", "Mon profil"},
      {"/admin/ip-whitelist", "Adresses autorisees"}
    ]
  end

  defp create_admin_user(_context) do
    admin = create_user(email: "admin@example.com", role: :admin)
    %{admin: admin}
  end

  defp log_in_admin(%{conn: conn, admin: admin}) do
    session = create_session(user: admin)
    octet = 1 + rem(System.unique_integer([:positive]), 254)
    conn = %{conn | remote_ip: {127, 0, 0, octet}}
    conn = Plug.Test.init_test_session(conn, %{"session_token" => session.token})
    %{conn: conn}
  end
end
