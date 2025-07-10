defmodule Portfolio.Auth.SessionCleaner do
  @moduledoc """
  GenServer pour nettoyer périodiquement les sessions expirées.

  Ce worker tourne en arrière-plan et supprime automatiquement les sessions
  expirées à intervalle régulier (par défaut toutes les heures).

  Solution écologique:
  - Faible empreinte mémoire
  - Une seule requête SQL par intervalle
  - Pas de dépendances externes
  - Pas de polling constant
  """

  use GenServer
  require Logger

  alias Portfolio.Auth

  # Intervalle de nettoyage en millisecondes (1 heure par défaut)
  @cleanup_interval_ms 60 * 60 * 1000

  ## Client API

  @doc """
  Démarre le SessionCleaner.
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Force un nettoyage immédiat (utile pour les tests).
  """
  def cleanup_now do
    GenServer.call(__MODULE__, :cleanup_now)
  end

  ## Server Callbacks

  @impl true
  def init(_opts) do
    # Planifier le premier nettoyage après le démarrage
    schedule_cleanup()

    Logger.info(
      "[SessionCleaner] Started - will clean expired sessions every #{@cleanup_interval_ms / 1000 / 60} minutes"
    )

    {:ok, %{}}
  end

  @impl true
  def handle_info(:cleanup, state) do
    perform_cleanup()
    schedule_cleanup()
    {:noreply, state}
  end

  @impl true
  def handle_call(:cleanup_now, _from, state) do
    result = perform_cleanup()
    {:reply, result, state}
  end

  ## Private Functions

  defp schedule_cleanup do
    Process.send_after(self(), :cleanup, @cleanup_interval_ms)
  end

  defp perform_cleanup do
    case Auth.delete_expired_sessions() do
      {0, nil} ->
        Logger.debug("[SessionCleaner] No expired sessions to delete")
        {:ok, 0}

      {count, nil} ->
        Logger.info("[SessionCleaner] Deleted #{count} expired session(s)")
        {:ok, count}
    end
  rescue
    error ->
      Logger.error("[SessionCleaner] Error during cleanup: #{inspect(error)}")
      {:error, error}
  end
end
