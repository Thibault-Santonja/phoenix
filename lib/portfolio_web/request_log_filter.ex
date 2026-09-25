defmodule PortfolioWeb.RequestLogFilter do
  @moduledoc """
  Empêche les liens magiques transportés dans le CHEMIN d'une URL
  d'atteindre les journaux applicatifs.

  `Plug.Telemetry` (`endpoint.ex`) journalise par défaut `method
  request_path` à `:info` pour chaque requête. `filter_parameters` ne
  s'applique qu'aux paramètres du dispatch, jamais au chemin. Les deux
  routes d'authentification portent un jeton en clair dans le chemin
  (`/auth/magic/:token`, `/auth/verify/:token`) : ce jeton se retrouvait
  donc en clair dans la sortie standard du conteneur.

  Tant que ces journaux restaient dans un fichier local plafonné, la fuite
  était bornée. Depuis que `config/deploy.yml` déclare le pilote `journald`,
  ils partent vers un moteur interrogeable qui les conserve 30 jours : un
  lien magique encore valide écrit là est sorti du périmètre de révocation
  de l'application. Ce module est donc le préalable à cette centralisation,
  pas un raffinement.

  `log_level/1` est passé à `Plug.Telemetry` via l'option `:log` (MFA) :
  `false` supprime totalement la ligne de journal pour ces routes, `:info`
  journalise normalement les autres.
  """

  @doc """
  Niveau de journalisation à appliquer pour cette requête (MFA
  `Plug.Telemetry`, appelé `apply(__MODULE__, :log_level, [conn])`).
  """
  @spec log_level(Plug.Conn.t()) :: Logger.level() | false
  def log_level(%Plug.Conn{path_info: path_info}) do
    if token_path?(path_info), do: false, else: :info
  end

  @doc """
  Vrai si le chemin (`conn.path_info`) porte un lien magique en clair.

  Source unique de la table des routes à jeton. Toute route du routeur
  portant `:token` dans son chemin doit y figurer : un test de complétude
  compare cette table aux routes réellement déclarées.
  """
  @spec token_path?([String.t()]) :: boolean()
  def token_path?(["auth", "magic", _token]), do: true
  def token_path?(["auth", "verify", _token]), do: true
  def token_path?(_path_info), do: false
end
