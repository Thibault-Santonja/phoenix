defmodule PortfolioWeb.ErrorViewTest do
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.Template

  alias PortfolioWeb.ErrorHTML

  describe "render/2 for 403.html" do
    test "renders 403 page with CSRF explanation" do
      html = render_to_string(ErrorHTML, "403", "html", [])

      assert html =~ "403"
      assert html =~ "Forbidden" or html =~ "Non autorisé" or html =~ "Requête non autorisée"
    end

    test "403 page explains CSRF protection" do
      html = render_to_string(ErrorHTML, "403", "html", [])

      # Should mention session or security
      assert html =~ "session" or html =~ "sécurité" or html =~ "security"
    end

    test "403 page provides helpful action" do
      html = render_to_string(ErrorHTML, "403", "html", [])

      # Should have a link to go somewhere useful
      assert html =~ "href" or html =~ "Retour" or html =~ "Accueil" or html =~ "Réessayer"
    end

    test "403 page is user-friendly" do
      html = render_to_string(ErrorHTML, "403", "html", [])

      # Should not expose technical details that could help attackers
      refute html =~ "_csrf_token"
      refute html =~ "Plug.CSRFProtection"
      refute html =~ "stacktrace"
    end

    test "403 page has proper HTML structure" do
      html = render_to_string(ErrorHTML, "403", "html", [])

      assert html =~ "<div"
      assert html =~ "</div>"
    end
  end

  describe "render/2 for other error codes" do
    test "renders 404 page" do
      html = render_to_string(ErrorHTML, "404", "html", [])

      assert html =~ "404"
    end

    test "renders 500 page" do
      html = render_to_string(ErrorHTML, "500", "html", [])

      assert html =~ "500"
    end
  end

  describe "render/2 for error with layout" do
    test "403 error renders correctly" do
      # Phoenix 1.8+ uses render_to_string directly without put_view
      html = render_to_string(ErrorHTML, "403", "html", [])

      assert html =~ "403"
    end
  end
end
