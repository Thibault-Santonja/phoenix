defmodule PortfolioWeb.AlbumNotFoundError do
  @moduledoc """
  Lève quand un album demandé n'existe pas, ou n'est pas publié.

  La plateforme photo ne distingue pas les deux cas, et c'est voulu :
  l'existence d'un brouillon est elle-même une information. Le portfolio
  reprend cette position et répond 404 dans les deux cas.
  """

  defexception [:message, plug_status: 404]
end
