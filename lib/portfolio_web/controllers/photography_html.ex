defmodule PortfolioWeb.PhotographyHTML do
  @moduledoc """
  This module contains pages rendered by PhotographyController.

  See the `photography_html` directory for all templates available.
  """
  use PortfolioWeb, :html

  embed_templates "photography_html/*"
end
