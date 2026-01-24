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

  alias Portfolio.Auth

  def on_mount(:default, _params, session, socket) do
    # Le current_user peut venir de deux sources:
    # 1. Déjà assigné par le plug RequireAuth (production)
    # 2. Depuis le token de session (fallback pour tests et LiveView)
    current_user =
      socket.assigns[:current_user] ||
        find_current_user(session)

    {:cont, assign(socket, current_user: current_user)}
  end

  defp find_current_user(session) do
    with token when is_binary(token) <- session["session_token"],
         %Auth.UserSession{} = user_session <- Auth.get_session_by_token(token) do
      user_session.user
    else
      _ -> nil
    end
  end
end
