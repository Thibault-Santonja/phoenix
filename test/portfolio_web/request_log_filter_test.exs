defmodule PortfolioWeb.RequestLogFilterTest do
  @moduledoc """
  Les deux routes qui transportent un lien magique dans le CHEMIN de l'URL
  ne doivent jamais être journalisées par `Plug.Telemetry` (`endpoint.ex`),
  qui journalise sinon `method request_path` en clair à chaque requête.

  L'enjeu a changé de nature avec le pilote de journalisation `journald` :
  ces lignes ne restent plus dans un fichier local plafonné sur la machine,
  elles partent dans un moteur interrogeable et y sont conservées 30 jours.
  Un lien magique valide écrit là est sorti du périmètre de révocation de
  l'application.
  """

  use ExUnit.Case, async: true

  alias PortfolioWeb.RequestLogFilter

  defp conn_for(path), do: %Plug.Conn{path_info: String.split(path, "/", trim: true)}

  describe "log_level/1 sur les routes à jeton" do
    for path <- [
          "/auth/magic/Q21K5U3bYuQ9emofZUStw84NxJY4LxBi1F2gcpi6v2Y",
          "/auth/verify/Q21K5U3bYuQ9emofZUStw84NxJY4LxBi1F2gcpi6v2Y"
        ] do
      test "supprime la ligne de journal de #{path}" do
        assert RequestLogFilter.log_level(conn_for(unquote(path))) == false
      end
    end
  end

  describe "log_level/1 sur les routes ordinaires" do
    for path <- [
          "/",
          "/login",
          "/auth",
          "/auth/logout",
          "/albums/mon-album",
          "/admin/dashboard"
        ] do
      test "journalise normalement #{path}" do
        assert RequestLogFilter.log_level(conn_for(unquote(path))) == :info
      end
    end
  end

  describe "couverture des routes du routeur" do
    test "toute route du routeur portant `:token` dans son chemin est filtrée" do
      # Garde-fou de complétude : une route à jeton ajoutée au routeur sans
      # être ajoutée au filtre rend ce test rouge. C'est le seul moyen que le
      # filtre ne se périme pas en silence, et le coût d'un oubli est un
      # jeton valide conservé 30 jours hors de l'application.
      token_paths =
        PortfolioWeb.Router
        |> Phoenix.Router.routes()
        |> Enum.map(& &1.path)
        |> Enum.filter(&String.contains?(&1, ":token"))
        |> Enum.uniq()

      assert token_paths != [], "aucune route à jeton trouvée : le garde-fou ne garde plus rien"

      for path <- token_paths do
        path_info =
          path
          |> String.split("/", trim: true)
          |> Enum.map(fn
            ":" <> _segment -> "valeur-de-jeton"
            segment -> segment
          end)

        assert RequestLogFilter.log_level(%Plug.Conn{path_info: path_info}) == false,
               "la route #{path} porte un jeton dans son chemin mais n'est pas filtrée : " <>
                 "ajouter sa forme à PortfolioWeb.RequestLogFilter"
      end
    end
  end
end
