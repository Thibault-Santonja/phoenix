defmodule PortfolioWeb.Photography.GalleryLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/photo")

    %{conn: conn, subdomain: subdomain}
  end

  describe "Photography gallery index" do
    setup [:open_subdomain]

    test "/gallery path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _gallery_live, html} = live(conn, subdomain <> "/gallery")
      assert html =~ "Thibault San Photographie"
    end

    test "redirection to home ", %{conn: conn, subdomain: subdomain} do
      {:ok, gallery_live, _html} = live(conn, subdomain <> "/gallery")

      gallery_live
      |> element("a", "Home")
      |> render_click()
      |> follow_redirect(conn, ~p"/")
    end
  end

  describe "Redirect from Photography index to gallery" do
    setup [:open_subdomain]

    test "redirect from index/china to gallery", %{conn: conn, subdomain: subdomain} do
      {:ok, index_live, _html} = live(conn, subdomain <> "/?chapter=china")

      index_live
      |> element("a", "Voir plus")
      |> render_click()
      |> follow_redirect(conn, ~p"/gallery/china")
    end
  end
end
