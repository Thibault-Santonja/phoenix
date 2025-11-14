defmodule PortfolioWeb.ErrorHTML do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on HTML requests.

  Custom error pages are available for:
  - 403 Forbidden: CSRF protection and session expiration
  - 404 Not Found: Uses default Phoenix message
  - 500 Internal Server Error: Uses default Phoenix message

  See config/config.exs.
  """
  use PortfolioWeb, :html

  # Embed custom error templates
  embed_templates "error_html/*"

  # Fallback for error codes without custom templates
  # Renders a plain text page based on the template name
  # For example, "404.html" becomes "Not Found"
  def render(template, _assigns) do
    Phoenix.Controller.status_message_from_template(template)
  end
end
