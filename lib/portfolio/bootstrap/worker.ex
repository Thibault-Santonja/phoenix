defmodule Portfolio.Bootstrap.Worker do
  @moduledoc """
  GenServer responsable du bootstrap automatique de l'application.

  Ce processus s'exécute au démarrage de l'application et garantit que
  l'utilisateur admin initial existe en base de données.

  ## Fonctionnement

  1. Attend que le Repo soit disponible (avec retry configurable)
  2. Exécute le bootstrap de l'admin initial via `Portfolio.Bootstrap.run/1`
  3. Se termine automatiquement (pas besoin de rester actif)

  ## Configuration

  Le worker utilise la configuration de `Portfolio.Bootstrap` :

      config :portfolio, Portfolio.Bootstrap,
        max_retries: 20,              # ~10 minutes avec 30s d'intervalle
        retry_interval_ms: 30_000,    # 30 secondes entre chaque retry
        admin_email: "admin@example.com"

  ## Environnements

  - ✅ Production : Bootstrap activé
  - ✅ Développement : Bootstrap activé
  - ❌ Test : Bootstrap désactivé (retourne :ignore)

  ## Logs

  Le worker émet des logs pour suivre la progression :

      [debug] Repo not ready yet, retrying in 30000ms (attempt 1/20)
      [info] ✓ Admin user created: thibault.santonja@pm.me
      [info] ✓ Admin user bootstrap completed successfully

  En cas d'échec après tous les retries :

      [error] Failed to bootstrap admin user after 20 retries. Database may not be available.
  """

  use GenServer
  require Logger

  alias Portfolio.Bootstrap

  # Cache environment at compile time to avoid runtime lookups
  @env Mix.env()

  @doc """
  Démarre le processus de bootstrap.

  En environnement :test, le processus s'ignore automatiquement.
  """
  @spec start_link(keyword()) :: GenServer.on_start() | :ignore
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    # En test, on skip le bootstrap
    if @env == :test do
      :ignore
    else
      # En production/dev, on lance le bootstrap de manière asynchrone
      send(self(), :bootstrap)
      {:ok, %{retry_count: 0}}
    end
  end

  @impl true
  def handle_info(:bootstrap, state) do
    max_retries = Bootstrap.config(:max_retries) || 20
    retry_interval = Bootstrap.config(:retry_interval_ms) || 30_000
    admin_email = Bootstrap.config(:admin_email)

    case Bootstrap.run(admin_email: admin_email) do
      :ok ->
        Logger.info("✓ Admin user bootstrap completed successfully")
        # Le processus reste actif mais n'a plus rien à faire
        {:noreply, Map.put(state, :completed, true)}

      {:error, :repo_not_ready} when state.retry_count < max_retries ->
        Logger.debug(
          "Repo not ready yet, retrying in #{retry_interval}ms (attempt #{state.retry_count + 1}/#{max_retries})"
        )

        Process.send_after(self(), :bootstrap, retry_interval)
        {:noreply, %{state | retry_count: state.retry_count + 1}}

      {:error, :repo_not_ready} ->
        Logger.error(
          "Failed to bootstrap admin user after #{max_retries} retries (~#{div(max_retries * retry_interval, 60_000)} minutes). Database may not be available."
        )

        {:stop, :repo_unavailable, state}

      {:error, reason} ->
        Logger.error("Failed to bootstrap admin user: #{inspect(reason)}")
        {:stop, :bootstrap_failed, state}
    end
  end
end
