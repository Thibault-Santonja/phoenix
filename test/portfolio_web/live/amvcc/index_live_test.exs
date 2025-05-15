defmodule PortfolioWeb.Amvcc.IndexLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  defp open_subdomain(%{conn: conn}) do
    {:error, {:redirect, %{to: subdomain}}} = live(conn, ~p"/amvcc")

    %{conn: conn, subdomain: subdomain}
  end

  describe "AMVCC index" do
    setup [:open_subdomain]

    test "/ path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/")
      assert html =~ "La Seigneurie de Coucy"
    end
  end

  describe "Clothes page" do
    setup [:open_subdomain]

    test "/ path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/vetements")
      assert html =~ "habit au milieu du XIV<sup>e</sup> siècle"
    end
  end

  describe "Shoes page" do
    setup [:open_subdomain]

    test "/ path render default page", %{conn: conn, subdomain: subdomain} do
      {:ok, _index_live, html} = live(conn, subdomain <> "/chaussures")
      assert html =~ "Les chaussures au Moyen Âge (XIV<sup>e</sup> siècle)"
    end
  end
end
