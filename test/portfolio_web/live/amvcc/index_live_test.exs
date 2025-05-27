defmodule PortfolioWeb.Amvcc.IndexLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/amvcc")

    %{conn: conn, subdomain: subdomain}
  end

  describe "Seigneurie de Coucy index" do
    setup [:open_subdomain]

    test "/ path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/")
      assert html =~ "La Seigneurie de Coucy"
    end

    test "/blog path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, index_live, _html} = live(conn, subdomain <> "/")

      {:ok, _blog_live} =
        index_live
        |> element("a", "Explorez nos articles")
        |> render_click()
        |> follow_redirect(conn, ~p"/blog")
    end
  end

  describe "Blog" do
    setup [:open_subdomain]

    test "/blog path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _blog_live, html} = live(conn, subdomain <> "/blog")
      assert html =~ "Our blog post"
    end

    test "/blog/clothes path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _clothes_live, html} = live(conn, subdomain <> "/blog/vetements")
      assert html =~ "habit au milieu du XIV<sup>e</sup> siècle"
    end

    test "/blog/shoes path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _shoes_live, html} = live(conn, subdomain <> "/blog/chaussures")
      assert html =~ "Les chaussures au Moyen Âge (XIV<sup>e</sup> siècle)"
    end
  end
end
