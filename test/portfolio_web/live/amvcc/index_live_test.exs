defmodule PortfolioWeb.Amvcc.IndexLiveTest do
  use PortfolioWeb.ConnCase
  import Phoenix.LiveViewTest

  describe "AMVCC index" do
    test "/amvcc path render default page", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/amvcc")
      assert html =~ "La Seigneurie de Coucy"
    end

    test "/amvcc/vetements path render clothes page", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/amvcc/vetements")
      assert html =~ "habit au milieu du XIV<sup>e</sup> siècle"
    end

    test "/amvcc/chaussures path render shoes page", %{conn: conn} do
      {:ok, _index_live, html} = live(conn, "/amvcc/chaussures")
      assert html =~ "Les chaussures au Moyen Âge (XIV<sup>e</sup> siècle)"
    end
  end
end
