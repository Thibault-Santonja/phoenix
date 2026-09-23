defmodule PortfolioTest.Support.ScriptedCatalogAdapter do
  @moduledoc """
  Catalogue pilote depuis le test, pour éprouver le décorateur de cache.

  Ce n'est pas un bouchon universel : c'est le service externe substitué, le
  seul que la strategie de test du dépôt autorise a remplacer. Il compte les
  appels, ce qui permet de vérifier qu'un palier de dégradation n'a
  effectivement pas touche au réseau.
  """

  @behaviour Portfolio.Photography.Ports.AlbumCatalogPort

  @doc """
  Démarre le scénario. À appeler dans le `setup` du test.
  """
  @spec start_link() :: {:ok, pid()}
  def start_link do
    Agent.start_link(fn -> %{responses: %{}, calls: %{}, args: %{}} end, name: __MODULE__)
  end

  @doc """
  Definit la réponse rendue par `fonction` (`:list_albums`, `:get_album` ou
  `:list_themes`).
  """
  @spec script(atom(), term()) :: :ok
  def script(fonction, reponse) do
    Agent.update(__MODULE__, &put_in(&1.responses[fonction], reponse))
  end

  @doc """
  Nombre d'appels reçus par `fonction` depuis le démarrage.
  """
  @spec calls(atom()) :: non_neg_integer()
  def calls(fonction) do
    Agent.get(__MODULE__, &Map.get(&1.calls, fonction, 0))
  end

  @doc """
  Derniers arguments reçus par `fonction`, ou `nil` si elle n'a pas ete
  appelee.
  """
  @spec last_args(atom()) :: term() | nil
  def last_args(fonction) do
    Agent.get(__MODULE__, &Map.get(&1.args, fonction))
  end

  @impl true
  def list_albums(opts \\ []), do: respond(:list_albums, opts)

  @impl true
  def get_album(slug, opts \\ []), do: respond(:get_album, {slug, opts})

  @impl true
  def list_themes(opts \\ []), do: respond(:list_themes, opts)

  # Un test qui n'a pas démarré de scénario voit une plateforme éteinte. C'est
  # le défaut le plus sûr : aucune page ne doit casser pour autant, et c'est
  # justement ce que les paliers de dégradation promettent.
  defp respond(fonction, args) do
    case Process.whereis(__MODULE__) do
      nil -> {:error, :unavailable}
      _pid -> Agent.get_and_update(__MODULE__, &enregistre(&1, fonction, args))
    end
  end

  defp enregistre(state, fonction, args) do
    state =
      state
      |> update_in([:calls], &Map.update(&1, fonction, 1, fn n -> n + 1 end))
      |> update_in([:args], &Map.put(&1, fonction, args))

    {Map.get(state.responses, fonction, {:error, :unavailable}), state}
  end
end
