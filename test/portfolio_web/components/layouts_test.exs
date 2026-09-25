defmodule PortfolioWeb.LayoutsTest do
  @moduledoc """
  Tests unitaires des fonctions de presentation de la coquille
  d'administration. Les tests d'integration (admin_shell_test.exs) verifient le
  rendu des pages reelles ; ceux-ci pinnent les regles de resolution, dont les
  cas limites qu'aucune route existante n'expose.
  """

  use ExUnit.Case, async: true

  alias PortfolioWeb.Layouts

  describe "admin_nav_current?/2" do
    test "marque l'entree dont le chemin est exactement le chemin courant" do
      assert Layouts.admin_nav_current?(%{current_path: "/admin/albums"}, "/admin/albums") ==
               "page"
    end

    test "n'omet pas le tableau de bord, dont le chemin est prefixe de tous les autres" do
      assert Layouts.admin_nav_current?(%{current_path: "/admin"}, "/admin") == "page"
      assert Layouts.admin_nav_current?(%{current_path: "/admin/albums"}, "/admin") == nil
    end

    test "rattache une page interne a sa section" do
      assigns = %{current_path: "/admin/albums/2e0f/edit"}

      assert Layouts.admin_nav_current?(assigns, "/admin/albums") == "page"
      assert Layouts.admin_nav_current?(assigns, "/admin") == nil
    end

    test "ne rattache pas un chemin voisin qui partage seulement le prefixe textuel" do
      assert Layouts.admin_nav_current?(%{current_path: "/admin/albumsxyz"}, "/admin/albums") ==
               nil
    end

    test "n'omet l'attribut sur aucune entree quand le chemin courant est inconnu" do
      for item <- Layouts.admin_nav_items() do
        assert Layouts.admin_nav_current?(%{}, item.path) == nil
      end
    end
  end

  describe "admin_nav_items/0" do
    test "expose chaque section du backoffice une seule fois" do
      paths = Enum.map(Layouts.admin_nav_items(), & &1.path)

      assert paths == Enum.uniq(paths)

      assert Enum.sort(paths) == [
               "/admin",
               "/admin/albums",
               "/admin/ip-whitelist",
               "/admin/photos",
               "/admin/profile",
               "/admin/users"
             ]
    end

    test "donne un libelle non vide a chaque entree" do
      for item <- Layouts.admin_nav_items() do
        assert item.label != ""
        refute item.label =~ "admin."
      end
    end
  end

  describe "admin_crumbs/1" do
    test "enchaine l'administration puis la page sur une page de section" do
      crumbs = Layouts.admin_crumbs(%{current_path: "/admin/albums", page_title: "Albums"})

      assert Enum.map(crumbs, & &1.label) == ["Administration", "Albums"]
      assert Enum.map(crumbs, & &1.path) == ["/admin", nil]
    end

    test "insere la section sur une page interne" do
      crumbs =
        Layouts.admin_crumbs(%{current_path: "/admin/albums/new", page_title: "Nouvel album"})

      assert Enum.map(crumbs, & &1.label) == ["Administration", "Albums", "Nouvel album"]
      assert Enum.map(crumbs, & &1.path) == ["/admin", "/admin/albums", nil]
    end

    test "ne repete pas l'administration sur le tableau de bord" do
      crumbs = Layouts.admin_crumbs(%{current_path: "/admin", page_title: "Tableau de bord"})

      assert Enum.map(crumbs, & &1.label) == ["Administration", "Tableau de bord"]
    end

    test "retombe sur Administration quand la page n'a pas de titre" do
      crumbs = Layouts.admin_crumbs(%{current_path: "/admin"})

      assert List.last(crumbs) == %{label: "Administration", path: nil}
    end
  end

  describe "admin_initials/1" do
    test "derive les initiales des deux premiers caracteres alphanumeriques" do
      assert Layouts.admin_initials(%{email: "thibault@example.com"}) == "TH"
    end

    test "retombe sur TS sans email exploitable" do
      assert Layouts.admin_initials(%{email: "@@@"}) == "TS"
      assert Layouts.admin_initials(%{email: nil}) == "TS"
      assert Layouts.admin_initials(nil) == "TS"
    end
  end

  describe "admin_role_label/1" do
    test "capitalise le role du compte connecte" do
      assert Layouts.admin_role_label(%{role: :admin}) == "Admin"
    end

    test "retombe sur Administrateur sans role" do
      assert Layouts.admin_role_label(%{role: nil}) == "Administrateur"
      assert Layouts.admin_role_label(nil) == "Administrateur"
    end
  end
end
