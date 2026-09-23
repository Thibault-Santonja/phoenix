defmodule PortfolioWeb.AlbumNotFoundError do
  @moduledoc """
  Leve quand un album demande n'existe pas, ou n'est pas publie.

  La plateforme photo ne distingue pas les deux cas, et c'est voulu :
  l'existence d'un brouillon est elle-meme une information. Le portfolio
  reprend cette position et repond 404 dans les deux cas.
  """

  defexception [:message, plug_status: 404]
end
