defmodule Portfolio.Auth.Repositories.IPWhitelistRepository do
  @moduledoc """
  Repository pour la gestion de la persistence des entrées IP Whitelist.

  Implémente le pattern Repository pour abstraire l'accès aux données des IP whitelistées.
  Ce repository se concentre uniquement sur l'accès aux données et isole
  la couche domaine vis-à-vis d'Ecto.

  ## Responsabilités

  - CRUD des entrées de whitelist
  - Requêtes de recherche
  - Isolation de la couche domaine vis-à-vis d'Ecto

  ## Exemples

      iex> IPWhitelistRepository.insert(%{ip_address: "192.168.1.100", ...})
      {:ok, %IPWhitelist{}}

      iex> IPWhitelistRepository.list_all()
      [%IPWhitelist{}, ...]
  """

  import Ecto.Query, warn: false

  alias Portfolio.Auth.IPWhitelist
  alias Portfolio.Repo

  # =============================================================================
  # Query Functions
  # =============================================================================

  @doc """
  Liste toutes les entrées de whitelist ordonnées par date d'insertion décroissante.

  ## Exemples

      iex> list_all()
      [%IPWhitelist{}, ...]
  """
  @spec list_all() :: [IPWhitelist.t()]
  def list_all do
    IPWhitelist
    |> order_by([w], desc: w.inserted_at)
    |> preload(:created_by)
    |> Repo.all()
  end

  @doc """
  Récupère une entrée de whitelist par son ID.

  ## Exemples

      iex> get(id)
      {:ok, %IPWhitelist{}}

      iex> get(non_existent_id)
      {:error, :not_found}
  """
  @spec get(Ecto.UUID.t()) :: {:ok, IPWhitelist.t()} | {:error, :not_found}
  def get(id) do
    case Repo.get(IPWhitelist, id) do
      nil -> {:error, :not_found}
      entry -> {:ok, Repo.preload(entry, :created_by)}
    end
  end

  @doc """
  Récupère toutes les adresses IP whitelistées (uniquement les IPs).

  Utilisé pour le cache.

  ## Exemples

      iex> list_ip_addresses()
      ["192.168.1.100", "10.0.0.1"]
  """
  @spec list_ip_addresses() :: [String.t()]
  def list_ip_addresses do
    IPWhitelist
    |> select([w], w.ip_address)
    |> Repo.all()
  end

  # =============================================================================
  # Insert/Update/Delete Functions
  # =============================================================================

  @doc """
  Insère une nouvelle entrée de whitelist.

  ## Exemples

      iex> insert(%{ip_address: "192.168.1.100", created_by_id: admin_id})
      {:ok, %IPWhitelist{}}
  """
  @spec insert(map()) :: {:ok, IPWhitelist.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) when is_map(attrs) do
    %IPWhitelist{}
    |> IPWhitelist.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Met à jour une entrée de whitelist existante.

  ## Exemples

      iex> update(entry, %{description: "Nouvelle description"})
      {:ok, %IPWhitelist{}}
  """
  @spec update(IPWhitelist.t(), map()) :: {:ok, IPWhitelist.t()} | {:error, Ecto.Changeset.t()}
  def update(%IPWhitelist{} = entry, attrs) do
    entry
    |> IPWhitelist.update_changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Supprime une entrée de whitelist.

  ## Exemples

      iex> delete(entry)
      {:ok, %IPWhitelist{}}
  """
  @spec delete(IPWhitelist.t()) :: {:ok, IPWhitelist.t()} | {:error, Ecto.Changeset.t()}
  def delete(%IPWhitelist{} = entry) do
    Repo.delete(entry)
  end
end
