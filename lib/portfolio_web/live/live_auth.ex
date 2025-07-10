defmodule PortfolioWeb.LiveAuth do
  @moduledoc """
  Hook LiveView pour rendre l'utilisateur connecté disponible dans tous les LiveViews.

  Usage dans un LiveView:

      defmodule MyAppWeb.SomeLive do
        use MyAppWeb, :live_view

        on_mount PortfolioWeb.LiveAuth

        def mount(_params, _session, socket) do
          # socket.assigns.current_user est maintenant disponible
          {:ok, socket}
        end
      end

  L'utilisateur connecté est disponible via `@current_user` dans le template.
  """

  import Phoenix.Component

  def on_mount(:default, _params, _session, socket) do
    # Le current_user a déjà été assigné par le plug RequireAuth
    # Il est disponible dans socket.assigns depuis le Endpoint
    current_user = socket.assigns[:current_user]

    {:cont, assign(socket, current_user: current_user)}
  end
end
