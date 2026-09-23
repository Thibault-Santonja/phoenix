defmodule Portfolio.Photography.Catalog.Snapshot do
  @moduledoc """
  Instantane JSON du catalogue, conserve sur disque.

  ## A quoi il sert

  Au redemarrage de l'hote, les deux applications repartent ensemble et le
  portfolio, plus leger, est pret avant la plateforme photo. Sans instantane,
  son cache memoire est vide et la plateforme est muette : il n'aurait rien a
  montrer. L'instantane est exactement ce palier-la, et rien d'autre.

  ## Ce qui est conserve

  La charge utile JSON brute, telle qu'elle est arrivee, pas les structures
  decodees. Relire par le meme decodeur que le reseau garantit qu'un
  instantane ecrit par une version precedente est valide ou rejete, jamais
  interprete de travers.

  L'ecriture passe par un fichier temporaire puis un `rename`, qui est
  atomique sur un meme systeme de fichiers : une coupure pendant l'ecriture
  laisse l'ancien instantane intact plutot qu'un fichier tronque.

  Aucune erreur ne remonte a l'appelant sous forme d'exception : un
  instantane est un filet, pas une dependance.
  """

  require Logger

  @doc """
  Ecrit un instantane pour `key`.

  Un `dir` a `nil` desactive la fonctionnalite : l'appel reussit sans rien
  ecrire, ce qui evite d'avoir a tester la configuration chez l'appelant.
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
        Logger.warning("catalogue: instantane non ecrit (#{inspect(reason)})")
        {:error, reason}
    end
  end

  @doc """
  Relit l'instantane de `key`, ou `:error` s'il n'existe pas ou n'est pas
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

  # Le nom de fichier est derive de la cle par condensat : une cle est un
  # terme quelconque (tuple, atome, binaire) et le systeme de fichiers ne
  # sait pas les nommer.
  defp path(dir, key) do
    nom =
      :sha256
      |> :crypto.hash(:erlang.term_to_binary(key))
      |> Base.url_encode64(padding: false)

    Path.join(dir, nom <> ".json")
  end
end
