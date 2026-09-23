defmodule Portfolio.Photography.Catalog.Snapshot do
  @moduledoc """
  Instantané JSON du catalogue, conserve sur disque.

  ## A quoi il sert

  Au redémarrage de l'hôte, les deux applications repartent ensemble et le
  portfolio, plus léger, est prêt avant la plateforme photo. Sans instantané,
  son cache mémoire est vide et la plateforme est muette : il n'aurait rien a
  montrer. L'instantané est exactement ce palier-là, et rien d'autre.

  ## Ce qui est conserve

  La charge utile JSON brute, telle qu'elle est arrivée, pas les structures
  décodées. Relire par le même décodeur que le réseau garantit qu'un
  instantané écrit par une version precedente est valide ou rejete, jamais
  interprete de travers.

  L'écriture passe par un fichier temporaire puis un `rename`, qui est
  atomique sur un même système de fichiers : une coupure pendant l'écriture
  laisse l'ancien instantané intact plutôt qu'un fichier tronque.

  Aucune erreur ne remonte à l'appelant sous forme d'exception : un
  instantané est un filet, pas une dépendance.
  """

  require Logger

  @doc """
  Écrit un instantané pour `key`.

  Un `dir` à `nil` désactive la fonctionnalité : l'appel réussit sans rien
  écrire, ce qui evite d'avoir a tester la configuration chez l'appelant.
  """
  @spec write(Path.t() | nil, term(), map()) :: :ok | {:error, term()}
  def write(nil, _key, _payload), do: :ok

  def write(dir, key, payload) when is_map(payload) do
    with {:ok, json} <- Jason.encode(payload),
         :ok <- File.mkdir_p(dir),
         path = path(dir, key),
         temporaire = path <> ".#{System.unique_integer([:positive])}.tmp",
         :ok <- File.write(temporaire, json),
         :ok <- File.rename(temporaire, path) do
      :ok
    else
      {:error, reason} ->
        Logger.warning("catalogue : instantané non écrit (#{inspect(reason)})")
        {:error, reason}
    end
  end

  @doc """
  Relit l'instantané de `key`, ou `:error` s'il n'existe pas ou n'est pas
  exploitable.
  """
  @spec read(Path.t() | nil, term()) :: {:ok, map()} | :error
  def read(nil, _key), do: :error

  def read(dir, key) do
    with {:ok, contenu} <- File.read(path(dir, key)),
         {:ok, payload} when is_map(payload) <- Jason.decode(contenu) do
      {:ok, payload}
    else
      _autre -> :error
    end
  end

  # Le nom de fichier est derive de la clé par condensat : une clé est un
  # terme quelconque (tuple, atome, binaire) et le système de fichiers ne
  # sait pas les nommer.
  defp path(dir, key) do
    nom =
      :sha256
      |> :crypto.hash(:erlang.term_to_binary(key))
      |> Base.url_encode64(padding: false)

    Path.join(dir, nom <> ".json")
  end
end
