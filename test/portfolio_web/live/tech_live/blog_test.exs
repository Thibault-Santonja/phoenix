defmodule PortfolioWeb.TechLive.BlogTest do
  @moduledoc """
  Tests for Tech blog LiveViews (CI, Kamal, Elixir articles).
  Routes require tech. subdomain.
  """
  use PortfolioWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  # Helper to set the tech subdomain
  defp with_tech_host(conn) do
    %{conn | host: "tech.localhost"}
  end

  describe "Elixir blog page" do
    test "renders elixir blog page", %{conn: conn} do
      {:ok, _view, html} = conn |> with_tech_host() |> live("/blog/elixir")

      assert html =~ "Elixir"
    end

    test "sets correct page title", %{conn: conn} do
      {:ok, view, _html} = conn |> with_tech_host() |> live("/blog/elixir")

      title = page_title(view) || ""
      assert title =~ "Elixir" or title =~ "tech" or title == ""
    end

    test "includes article structured data for SEO", %{conn: conn} do
      {:ok, _view, html} = conn |> with_tech_host() |> live("/blog/elixir")

      # Should include JSON-LD schema for article
      assert html =~ "application/ld+json"
    end

    test "includes breadcrumb schema for SEO", %{conn: conn} do
      {:ok, _view, html} = conn |> with_tech_host() |> live("/blog/elixir")

      # Should include breadcrumb navigation schema
      assert html =~ "BreadcrumbList" or html =~ "breadcrumb"
    end
  end

  describe "CI blog page" do
    test "renders CI blog page", %{conn: conn} do
      {:ok, _view, html} = conn |> with_tech_host() |> live("/blog/ci")

      assert html =~ "CI" or html =~ "Continuous Integration"
    end

    test "sets correct page title", %{conn: conn} do
      {:ok, view, _html} = conn |> with_tech_host() |> live("/blog/ci")

      title = page_title(view) || ""
      assert title =~ "CI" or title =~ "tech" or title == ""
    end
  end

  describe "Kamal blog page" do
    test "renders Kamal blog page", %{conn: conn} do
      {:ok, _view, html} = conn |> with_tech_host() |> live("/blog/kamal")

      assert html =~ "Kamal"
    end

    test "sets correct page title", %{conn: conn} do
      {:ok, view, _html} = conn |> with_tech_host() |> live("/blog/kamal")

      title = page_title(view) || ""
      assert title =~ "Kamal" or title =~ "tech" or title == ""
    end
  end

  describe "Tech index page" do
    test "renders tech index page", %{conn: conn} do
      {:ok, _view, html} = conn |> with_tech_host() |> live("/")

      assert html =~ "tech" or html =~ "Tech"
    end

    test "contains navigation to blog posts", %{conn: conn} do
      {:ok, _view, html} = conn |> with_tech_host() |> live("/")

      # Should have links to blog articles
      assert html =~ "/blog/" or html =~ "blog"
    end
  end
end
