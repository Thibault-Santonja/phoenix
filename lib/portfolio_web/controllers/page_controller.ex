defmodule PortfolioWeb.PageController do
  use PortfolioWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def subdomain_redirect(conn, _params) do
    redirect(conn, external: "#{conn.scheme}://#{hd(conn.path_info)}.#{conn.host}:#{conn.port}")
  end
end
