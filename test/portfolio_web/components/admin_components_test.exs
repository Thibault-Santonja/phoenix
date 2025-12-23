defmodule PortfolioWeb.AdminComponentsTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias PortfolioWeb.AdminComponents

  describe "stat_card/1" do
    test "renders stat card with required attributes" do
      html =
        render_component(&AdminComponents.stat_card/1,
          title: "Total Albums",
          value: 42,
          icon: "hero-folder",
          color: "blue"
        )

      assert html =~ "Total Albums"
      assert html =~ "42"
      assert html =~ "hero-folder"
      assert html =~ "border-blue-500"
      assert html =~ "bg-blue-100"
    end

    test "renders stat card with green color" do
      html =
        render_component(&AdminComponents.stat_card/1,
          title: "Photos",
          value: 100,
          icon: "hero-photo",
          color: "green"
        )

      assert html =~ "border-green-500"
      assert html =~ "bg-green-100"
      assert html =~ "text-green-600"
    end

    test "renders stat card with purple color" do
      html =
        render_component(&AdminComponents.stat_card/1,
          title: "Views",
          value: "1.2K",
          icon: "hero-eye",
          color: "purple"
        )

      assert html =~ "border-purple-500"
      assert html =~ "bg-purple-100"
    end

    test "renders stat card with orange color" do
      html =
        render_component(&AdminComponents.stat_card/1,
          title: "Pending",
          value: 5,
          icon: "hero-clock",
          color: "orange"
        )

      assert html =~ "border-orange-500"
      assert html =~ "bg-orange-100"
    end

    test "renders stat card with red color" do
      html =
        render_component(&AdminComponents.stat_card/1,
          title: "Errors",
          value: 3,
          icon: "hero-exclamation-triangle",
          color: "red"
        )

      assert html =~ "border-red-500"
      assert html =~ "bg-red-100"
    end

    test "renders stat card as div when no navigate" do
      html =
        render_component(&AdminComponents.stat_card/1,
          title: "Static Card",
          value: 10,
          icon: "hero-chart-bar",
          color: "blue"
        )

      assert html =~ "<div"
      refute html =~ "href="
      refute html =~ "cursor-pointer"
    end

    test "renders stat card as link when navigate is provided" do
      html =
        render_component(&AdminComponents.stat_card/1,
          title: "Clickable Card",
          value: 25,
          icon: "hero-folder",
          color: "blue",
          navigate: "/admin/albums"
        )

      assert html =~ "href=\"/admin/albums\""
      assert html =~ "cursor-pointer"
      assert html =~ "hover:shadow-lg"
    end

    test "renders stat card with custom class" do
      html =
        render_component(&AdminComponents.stat_card/1,
          title: "Custom",
          value: 1,
          icon: "hero-star",
          color: "blue",
          class: "my-custom-class"
        )

      assert html =~ "my-custom-class"
    end

    test "renders stat card with footer slot" do
      assigns = %{
        title: "With Footer",
        value: 50,
        icon: "hero-chart-pie",
        color: "green",
        footer: [%{__slot__: :footer, inner_block: fn _, _ -> "Footer content here" end}]
      }

      html = render_component(&AdminComponents.stat_card/1, assigns)

      assert html =~ "Footer content here"
    end
  end

  describe "back_to_dashboard/1" do
    test "renders back link" do
      html = render_component(&AdminComponents.back_to_dashboard/1, %{})

      assert html =~ "href=\"/admin\""
      assert html =~ "Retour au tableau de bord"
      assert html =~ "hero-chevron-left"
    end
  end

  describe "admin_logout_button/1" do
    test "renders logout button with user name" do
      user = %{name: "John Doe", email: "john@example.com"}

      html =
        render_component(&AdminComponents.admin_logout_button/1,
          current_user: user
        )

      assert html =~ "Connecté en tant que"
      assert html =~ "John Doe"
      assert html =~ "Déconnexion"
      assert html =~ "href=\"/logout\""
      assert html =~ "method=\"delete\""
    end

    test "renders logout button with email when no name" do
      user = %{name: nil, email: "jane@example.com"}

      html =
        render_component(&AdminComponents.admin_logout_button/1,
          current_user: user
        )

      assert html =~ "jane@example.com"
    end

    test "renders with custom class" do
      user = %{name: "Admin", email: "admin@example.com"}

      html =
        render_component(&AdminComponents.admin_logout_button/1,
          current_user: user,
          class: "custom-logout-class"
        )

      assert html =~ "custom-logout-class"
    end

    test "does not render when current_user is nil" do
      html =
        render_component(&AdminComponents.admin_logout_button/1,
          current_user: nil
        )

      refute html =~ "Connecté en tant que"
      refute html =~ "Déconnexion"
    end
  end

  describe "action_card/1" do
    test "renders action card with all attributes" do
      html =
        render_component(&AdminComponents.action_card/1,
          title: "Gérer les albums",
          description: "Créer, modifier et organiser",
          icon: "hero-folder",
          color: "blue",
          navigate: "/admin/albums"
        )

      assert html =~ "Gérer les albums"
      assert html =~ "Créer, modifier et organiser"
      assert html =~ "hero-folder"
      assert html =~ "href=\"/admin/albums\""
      assert html =~ "hero-chevron-right"
    end

    test "renders action card with green color" do
      html =
        render_component(&AdminComponents.action_card/1,
          title: "Photos",
          description: "Manage photos",
          icon: "hero-photo",
          color: "green",
          navigate: "/admin/photos"
        )

      assert html =~ "bg-green-100"
      assert html =~ "text-green-600"
      assert html =~ "hover:border-green-400"
    end

    test "renders action card with purple color" do
      html =
        render_component(&AdminComponents.action_card/1,
          title: "Stats",
          description: "View statistics",
          icon: "hero-chart-bar",
          color: "purple",
          navigate: "/admin/stats"
        )

      assert html =~ "bg-purple-100"
      assert html =~ "hover:border-purple-400"
    end

    test "renders action card with orange color" do
      html =
        render_component(&AdminComponents.action_card/1,
          title: "Settings",
          description: "Configure settings",
          icon: "hero-cog",
          color: "orange",
          navigate: "/admin/settings"
        )

      assert html =~ "bg-orange-100"
      assert html =~ "hover:border-orange-400"
    end

    test "renders action card with custom class" do
      html =
        render_component(&AdminComponents.action_card/1,
          title: "Custom",
          description: "Custom card",
          icon: "hero-star",
          color: "blue",
          navigate: "/admin/custom",
          class: "my-action-class"
        )

      assert html =~ "my-action-class"
    end
  end

  describe "badge/1" do
    test "renders gray badge by default" do
      html =
        render_component(&AdminComponents.badge/1,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Default" end}]
        )

      assert html =~ "Default"
      assert html =~ "bg-gray-100"
      assert html =~ "text-gray-800"
      assert html =~ "rounded-full"
    end

    test "renders green badge" do
      html =
        render_component(&AdminComponents.badge/1,
          color: "green",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Published" end}]
        )

      assert html =~ "bg-green-100"
      assert html =~ "text-green-800"
    end

    test "renders orange badge" do
      html =
        render_component(&AdminComponents.badge/1,
          color: "orange",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Draft" end}]
        )

      assert html =~ "bg-orange-100"
      assert html =~ "text-orange-800"
    end

    test "renders blue badge" do
      html =
        render_component(&AdminComponents.badge/1,
          color: "blue",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Info" end}]
        )

      assert html =~ "bg-blue-100"
      assert html =~ "text-blue-800"
    end

    test "renders red badge" do
      html =
        render_component(&AdminComponents.badge/1,
          color: "red",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Error" end}]
        )

      assert html =~ "bg-red-100"
      assert html =~ "text-red-800"
    end

    test "renders indigo badge" do
      html =
        render_component(&AdminComponents.badge/1,
          color: "indigo",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Active" end}]
        )

      assert html =~ "bg-indigo-100"
      assert html =~ "text-indigo-800"
    end

    test "renders purple badge" do
      html =
        render_component(&AdminComponents.badge/1,
          color: "purple",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Special" end}]
        )

      assert html =~ "bg-purple-100"
      assert html =~ "text-purple-800"
    end

    test "renders yellow badge" do
      html =
        render_component(&AdminComponents.badge/1,
          color: "yellow",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Warning" end}]
        )

      assert html =~ "bg-yellow-100"
      assert html =~ "text-yellow-800"
    end

    test "renders badge with custom class" do
      html =
        render_component(&AdminComponents.badge/1,
          color: "green",
          class: "ml-2 custom-badge",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Custom" end}]
        )

      assert html =~ "ml-2 custom-badge"
    end
  end

  describe "filter_badge/1" do
    test "renders active filter badge" do
      html =
        render_component(&AdminComponents.filter_badge/1,
          navigate: "/admin/albums",
          active: true,
          color: "indigo",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "All (42)" end}]
        )

      assert html =~ "All (42)"
      assert html =~ "href=\"/admin/albums\""
      assert html =~ "bg-indigo-100"
      assert html =~ "text-indigo-800"
    end

    test "renders inactive filter badge" do
      html =
        render_component(&AdminComponents.filter_badge/1,
          navigate: "/admin/albums?filter=draft",
          active: false,
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Drafts (5)" end}]
        )

      assert html =~ "Drafts (5)"
      assert html =~ "bg-gray-100"
      assert html =~ "text-gray-700"
      assert html =~ "hover:bg-gray-200"
    end

    test "renders filter badge with green color when active" do
      html =
        render_component(&AdminComponents.filter_badge/1,
          navigate: "/admin/albums?filter=published",
          active: true,
          color: "green",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Published" end}]
        )

      assert html =~ "bg-green-100"
      assert html =~ "text-green-800"
    end

    test "renders filter badge with custom class" do
      html =
        render_component(&AdminComponents.filter_badge/1,
          navigate: "/admin/test",
          active: false,
          class: "mx-2",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Test" end}]
        )

      assert html =~ "mx-2"
    end
  end

  describe "primary_button/1" do
    test "renders primary button with navigate" do
      html =
        render_component(&AdminComponents.primary_button/1,
          navigate: "/admin/albums/new",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "New Album" end}]
        )

      assert html =~ "New Album"
      assert html =~ "href=\"/admin/albums/new\""
      assert html =~ "bg-indigo-600"
      assert html =~ "hover:bg-indigo-700"
    end

    test "renders primary button with patch" do
      html =
        render_component(&AdminComponents.primary_button/1,
          patch: "/admin/modal",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Open Modal" end}]
        )

      assert html =~ "Open Modal"
      assert html =~ "href=\"/admin/modal\""
    end

    test "renders primary button with custom class" do
      html =
        render_component(&AdminComponents.primary_button/1,
          navigate: "/admin/test",
          class: "w-full mt-4",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Full Width" end}]
        )

      assert html =~ "w-full mt-4"
    end
  end

  describe "link_button/1" do
    test "renders link button with navigate and indigo color" do
      html =
        render_component(&AdminComponents.link_button/1,
          navigate: "/admin/albums/1/edit",
          color: "indigo",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Edit" end}]
        )

      assert html =~ "Edit"
      assert html =~ "href=\"/admin/albums/1/edit\""
      assert html =~ "text-indigo-600"
      assert html =~ "hover:text-indigo-900"
    end

    test "renders link button with red color" do
      html =
        render_component(&AdminComponents.link_button/1,
          navigate: "/admin/delete",
          color: "red",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Delete" end}]
        )

      assert html =~ "text-red-600"
      assert html =~ "hover:text-red-900"
    end

    test "renders link button with gray color" do
      html =
        render_component(&AdminComponents.link_button/1,
          navigate: "/admin/cancel",
          color: "gray",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Cancel" end}]
        )

      assert html =~ "text-gray-600"
      assert html =~ "hover:text-gray-900"
    end

    test "renders link button with patch" do
      html =
        render_component(&AdminComponents.link_button/1,
          patch: "/admin/modal/edit",
          color: "indigo",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Edit in Modal" end}]
        )

      assert html =~ "href=\"/admin/modal/edit\""
    end

    test "renders anchor when no navigate or patch" do
      html =
        render_component(&AdminComponents.link_button/1,
          color: "indigo",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Action" end}]
        )

      assert html =~ "<a"
      assert html =~ "href=\"#\""
    end

    test "renders link button with custom class" do
      html =
        render_component(&AdminComponents.link_button/1,
          navigate: "/admin/test",
          color: "indigo",
          class: "ml-4 font-bold",
          inner_block: [%{__slot__: :inner_block, inner_block: fn _, _ -> "Styled" end}]
        )

      assert html =~ "ml-4 font-bold"
    end
  end
end
