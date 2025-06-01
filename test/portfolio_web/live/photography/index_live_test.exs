defmodule PortfolioWeb.Photography.IndexLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  alias PortfolioWeb.PhotographyLive.Index

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/photo")

    %{conn: conn, subdomain: subdomain}
  end

  describe "Photography index" do
    setup [:open_subdomain]

    test "/ path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/")
      assert html =~ "Thibault San Photographie"
    end

    test "redirection to gallery ", %{conn: conn, subdomain: subdomain} do
      {:ok, index_live, _html} = live(conn, subdomain <> "/")

      index_live
      |> element("a", "Galerie")
      |> render_click()
      |> follow_redirect(conn, ~p"/timeline")
    end
  end

  describe "Photography chapter" do
    setup [:open_subdomain]

    test "/?hl=fr path render default page in french", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?hl=fr")
      assert html =~ "Thibault San Photographie"
    end

    test "/?hl=en path render default page in english", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?hl=en")
      assert html =~ "Thibault San Photography"
    end

    test "/?hl=random path render default page in default language (french)", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?hl=random")
      assert html =~ "Thibault San Photography"
    end

    test "/?hl=fr&chapter=landscape path render landscape chapter in french", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?hl=fr&chapter=landscape")
      assert html =~ "photographie de paysage"
    end

    test "/?hl=en&chapter=landscape path render landscape chapter in english", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?hl=en&chapter=landscape")
      assert html =~ "landscape photography"
    end

    test "/?chapter=landscape path render landscape chapter in default language (french)", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?chapter=landscape")
      assert html =~ "photographie de paysage"
    end

    test "/?chapter=random path render default chapter in default language (french)", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?chapter=random")
      assert html =~ "Galerie"
    end
  end

  describe "format_chapter_title/1" do
    test "returns translated title for known chapters" do
      assert Index.format_chapter_title("amvcc") == "AMVCC"
      assert Index.format_chapter_title("music") == "Concerts & Music"
      assert Index.format_chapter_title("street") == "Street Photography"
    end

    test "returns 'Gallery' for unknown chapter" do
      assert Index.format_chapter_title("unknown") == "Gallery"
    end
  end
end
