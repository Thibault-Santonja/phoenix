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
  end

  describe "Photography section" do
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

    test "/?hl=fr&section=landscape path render landscape section in french", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?hl=fr&section=landscape")
      assert html =~ "photographie de paysage"
    end

    test "/?hl=en&section=landscape path render landscape section in english", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?hl=en&section=landscape")
      assert html =~ "landscape photography"
    end

    test "/?section=landscape path render landscape section in default language (french)", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?section=landscape")
      assert html =~ "photographie de paysage"
    end

    test "/?section=random path render default section in default language (french)", %{
      conn: conn,
      subdomain: subdomain
    } do
      {:ok, _index_live, html} = live(conn, subdomain <> "/?section=random")
      assert html =~ "Galerie"
    end
  end

  describe "format_section_title/1" do
    test "returns translated title for known sections" do
      assert Index.format_section_title("amvcc") == "AMVCC"
      assert Index.format_section_title("music") == "Concerts & Music"
      assert Index.format_section_title("street") == "Street Photography"
    end

    test "returns 'Gallery' for unknown section" do
      assert Index.format_section_title("unknown") == "Gallery"
    end
  end

  describe "section_image/1" do
    test "returns correct image paths for known sections" do
      string = "amvcc"
      assert Index.section_image(string) == "/images/photography/#{string}.webp"
    end

    test "returns empty string for sections without image" do
      assert Index.section_image("") == ""
      assert Index.section_image(nil) == ""
    end
  end
end
