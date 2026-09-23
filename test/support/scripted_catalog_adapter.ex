defmodule PortfolioTest.Support.ScriptedCatalogAdapter do
  @moduledoc """
  Catalogue pilote depuis le test, pour eprouver le decorateur de cache.

  Ce n'est pas un bouchon universel : c'est le service externe substitue, le
  seul que la strategie de test du depot autorise a remplacer. Il compte les
  appels, ce qui permet de verifier qu'un palier de degradation n'a
  effectivement pas touche au reseau.
  """

  @behaviour Portfolio.Photography.Ports.AlbumCatalogPort

  @doc """
  Demarre le scenario. A appeler dans le `setup` du test.
  """
  @spec start_link() :: {:ok, pid()}
  def start_link do
    Agent.start_link(fn -> %{responses: %{}, calls: %{}} end, name: __MODULE__)
  end

  @doc """
  Definit la reponse rendue par `fonction` (`:list_albums`, `:get_album` ou
  `:list_themes`).
  """
  @spec script(atom(), term()) :: :ok
  def script(fonction, reponse) do
    Agent.update(__MODULE__, &put_in(&1.responses[fonction], reponse))
  end

  @doc """
  Nombre d'appels recus par `fonction` depuis le demarrage.
  """
  @spec calls(atom()) :: non_neg_integer()
  def calls(fonction) do
    Agent.get(__MODULE__, &Map.get(&1.calls, fonction, 0))
  end

  @impl true
  def list_albums(_opts \\ []), do: respond(:list_albums)

  @impl true
  def get_album(_slug, _opts \\ []), do: respond(:get_album)

  @impl true
  def list_themes(_opts \\ []), do: respond(:list_themes)

  defp respond(fonction) do
    Agent.get_and_update(__MODULE__, fn state ->
      state = update_in(state.calls, &Map.update(&1, fonction, 1, fn n -> n + 1 end))
      {Map.get(state.responses, fonction, {:error, :unavailable}), state}
    end)
  end
end
