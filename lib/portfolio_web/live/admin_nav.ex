defmodule PortfolioWeb.AdminNav do
  @moduledoc """
  Hook LiveView de la coquille d'administration : publie le chemin courant
  dans les assigns sous la cle `:current_path`.

  La coquille determine l'entree de navigation courante a partir de la route
  et jamais d'un libelle d'interface : un libelle passe par gettext et change
  donc avec la locale, alors que la route est stable. Le hook est attache a
  `handle_params` pour suivre aussi les navigations `patch` a l'interieur
  d'une meme LiveView (par exemple `/admin/ip-whitelist/new`).
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4]

  @doc """
  Attache le hook qui alimente `:current_path`. Branche sur le `live_session`
  d'administration (voir `PortfolioWeb.Router`).
  """
  def on_mount(:current_path, _params, _session, socket) do
    {:cont, attach_hook(socket, :admin_current_path, :handle_params, &put_current_path/3)}
  end

  defp put_current_path(_params, uri, socket) do
    {:cont, assign(socket, :current_path, URI.parse(uri).path)}
  end
end
