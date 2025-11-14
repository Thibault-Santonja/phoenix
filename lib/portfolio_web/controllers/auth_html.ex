defmodule PortfolioWeb.AuthHTML do
  @moduledoc """
  Renders HTML templates for authentication pages.
  """

  use PortfolioWeb, :html

  embed_templates "auth_html/*"
end
