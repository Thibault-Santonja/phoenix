defmodule PortfolioWeb.PageController do
  use PortfolioWeb, :controller

  def home(conn, _params) do
    # The home page is often custom made,
    # so skip the default app layout.
    render(conn, :home, layout: false)
  end

  def amvcc(conn, _params) do
    redirect(conn, external: "#{conn.scheme}://amvcc.#{conn.host}:#{conn.port}")
  end
end
