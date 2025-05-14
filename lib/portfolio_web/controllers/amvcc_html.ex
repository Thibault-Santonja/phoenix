defmodule PortfolioWeb.AmvccHTML do
  @moduledoc """
  This module contains pages rendered by AmvccController.

  See the `amvcc_html` directory for all templates available.
  """
  use PortfolioWeb, :html

  embed_templates "amvcc_html/*"
end
