defmodule PortfolioWeb.AmvccController do
  use PortfolioWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end

  def clothes(conn, _params) do
    render(conn, :clothes, layout: false)
  end

  def shoes(conn, _params) do
    render(conn, :shoes, layout: false)
  end
end
