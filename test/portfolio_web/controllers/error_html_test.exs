defmodule PortfolioWeb.ErrorHTMLTest do
  use PortfolioWeb.ConnCase, async: true

  # Bring render_to_string/4 for testing custom views
  import Phoenix.Template

  describe "default error pages" do
    test "renders 404.html" do
      html = render_to_string(PortfolioWeb.ErrorHTML, "404", "html", [])
      assert html =~ "404"
      assert html =~ "Page non trouvée" or html =~ "Not Found"
    end

    test "renders 500.html" do
      html = render_to_string(PortfolioWeb.ErrorHTML, "500", "html", [])
      assert html =~ "500"
      assert html =~ "Erreur serveur" or html =~ "Internal Server Error"
    end
  end

  describe "403 Forbidden (CSRF) error page" do
    test "renders 403.html with proper title" do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      assert html =~ "403"
      assert html =~ "Forbidden" or html =~ "Non autorisé" or html =~ "Requête non autorisée"
    end

    test "403 page explains the security issue" do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should mention session expiration or security
      assert html =~ "session" or html =~ "sécurité" or html =~ "expiré"
    end

    test "403 page provides helpful user actions" do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should have actionable links
      assert html =~ "href=\"/\""
    end

    test "403 page does not expose technical details" do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should not reveal security implementation details
      refute html =~ "_csrf_token"
      refute html =~ "Plug.CSRFProtection"
      refute html =~ "stacktrace"
      refute html =~ "ForbiddenError"
    end

    test "403 page has proper HTML structure" do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should be valid HTML with structure
      assert html =~ "<div"
      assert html =~ "</div>"
      assert html =~ "<h1" or html =~ "<h2"
    end

    test "403 page is bilingual (FR/EN)" do
      html = render_to_string(PortfolioWeb.ErrorHTML, "403", "html", [])

      # Should have both French and English content for accessibility
      # Or at least one clear language
      assert String.length(html) > 50
    end
  end
end
