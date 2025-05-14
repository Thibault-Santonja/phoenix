defmodule PhotoWeb.PageController do
  use PortfolioWeb, :controller

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end
end
