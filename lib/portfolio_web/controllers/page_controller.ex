defmodule PortfolioWeb.PageController do
  @moduledoc """
  Controller for static pages and subdomain redirections.
  """

  use PortfolioWeb, :controller

  @allowed_subdomains %{
    "photo" => "https://photo.thibaultsan.com",
    "tech" => "https://tech.thibaultsan.com",
    "amvcc" => "https://amvcc.thibaultsan.com"
  }

  def home(conn, _params) do
    render(conn, :home, layout: false)
  end

  @doc """
  Repond 404 pour une ressource qui n'a pas lieu d'exister sur cet hote.

  Sert aux plans de site sous `photo.thibaultsan.com`, qui porte une
  directive de non-indexation.
  """
  def not_found(conn, _params) do
    conn
    |> put_status(:not_found)
    |> put_view(PortfolioWeb.ErrorHTML)
    |> render("404.html")
  end

  @doc """
  Redirects to the appropriate subdomain based on the first path segment.

  Uses a whitelist to prevent open redirect attacks via Host header injection.
  """
  def subdomain_redirect(conn, _params) do
    subdomain = List.first(conn.path_info)

    case Map.get(@allowed_subdomains, subdomain) do
      nil ->
        conn
        |> put_status(:not_found)
        |> put_view(PortfolioWeb.ErrorHTML)
        |> render("404.html")

      url ->
        redirect(conn, external: url)
    end
  end
end
