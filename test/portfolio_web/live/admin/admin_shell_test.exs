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

    test "marque l'entree de navigation de la section courante sur chaque page", %{conn: conn} do
      for {path, _label} <- admin_sections() do
        {:ok, _view, html} = live(conn, path)

        assert nav_current_hrefs(html) == [path],
               "#{path} devrait marquer son entree de navigation avec aria-current=\"page\""
      end
    end

    test "marque la section parente sur les pages internes d'une section", %{conn: conn} do
      internal_pages = [
        {"/admin/albums/new", "/admin/albums"},
        {"/admin/ip-whitelist/new", "/admin/ip-whitelist"}
      ]

      for {path, section} <- internal_pages do
        {:ok, _view, html} = live(conn, path)

        assert nav_current_hrefs(html) == [section],
               "#{path} devrait marquer la section #{section}"
      end
    end

    test "affiche un fil d'Ariane qui enchaine l'administration, la section et la page", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/admin/albums/new")

      assert crumbs(html) == ["Administration", "Albums", "Nouvel album"]
    end

    test "affiche un fil d'Ariane a deux niveaux sur une page de section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/albums")

      assert crumbs(html) == ["Administration", "Albums"]
    end

    test "accentue correctement les libelles francais de la coquille", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Déconnexion"
      assert html =~ "Adresses autorisées"
      refute html =~ "Deconnexion"
      refute html =~ "Adresses autorisees"
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
      {"/admin/ip-whitelist", "Adresses autorisées"}
    ]
  end

  # Liens de la barre laterale portant aria-current="page", par ordre de rendu.
  defp nav_current_hrefs(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(~s(.app-side__nav a[aria-current="page"]))
    |> Enum.flat_map(&Floki.attribute(&1, "href"))
  end

  defp crumbs(html) do
    html
    |> Floki.parse_document!()
    |> Floki.find(".app-crumbs li")
    |> Enum.map(&(&1 |> Floki.text() |> String.trim()))
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
