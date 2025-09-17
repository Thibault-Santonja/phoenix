defmodule Portfolio.Photography.Repositories.PhotoRepository do
  @moduledoc """
  Repository pour la gestion de la persistence des Photos.

  Implémente le pattern Repository pour abstraire l'accès aux données des Photos.
  Les Photos sont des entités appartenant à l'agrégat Album.

  La logique de construction des requêtes est déléguée aux Query Objects,
  ce repository se concentre uniquement sur l'accès aux données.

  ## Responsabilités

  - CRUD complet sur les Photos
  - Exécution des requêtes construites par PhotoQuery
  - Réorganisation de l'ordre d'affichage
  - Gestion des erreurs de persistence
  - Isolation de la couche domaine vis-à-vis d'Ecto

  ## Exemples

      iex> PhotoRepository.list_by_album(album_id)
      [%Photo{}, %Photo{}]

      iex> PhotoRepository.get(photo_id)
      {:ok, %Photo{}}

      iex> PhotoRepository.reorder(album_id, [photo1_id, photo2_id, photo3_id])
      :ok

  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Portfolio.Photography.Photo
  alias Portfolio.Photography.Queries.PhotoQuery
  alias Portfolio.Repo

  @doc """
  Liste toutes les photos d'un album, triées par display_order croissant.

  ## Exemples

      iex> list_by_album(album_id)
      [%Photo{display_order: 0}, %Photo{display_order: 1}]

      iex> list_by_album(album_id, preload: [:album])
      [%Photo{album: %Album{}}]

  """
  @spec list_by_album(Ecto.UUID.t(), keyword()) :: [Photo.t()]
  def list_by_album(album_id, opts \\ []) do
    query =
      PhotoQuery.base()
      |> PhotoQuery.by_album(album_id)
      |> PhotoQuery.order_by_display_order()

    query =
      if opts[:preload] do
        apply_preload(query, opts[:preload])
      else
        query
      end

    Repo.all(query)
  end

  @doc """
  Récupère une photo par son ID.

  Retourne `{:ok, photo}` si trouvée, `{:error, :not_found}` sinon.

  ## Exemples

      iex> get(photo_id)
      {:ok, %Photo{}}

      iex> get("invalid-id")
      {:error, :not_found}

  """
  @spec get(Ecto.UUID.t(), keyword()) :: {:ok, Photo.t()} | {:error, :not_found}
  def get(id, opts \\ []) do
    query = from p in Photo, where: p.id == ^id

    query
    |> apply_preload(opts[:preload])
    |> Repo.one()
    |> case do
      nil -> {:error, :not_found}
      photo -> {:ok, photo}
    end
  end

  @doc """
  Récupère une photo par son ID, lève une exception si non trouvée.

  ## Exemples

      iex> get!(photo_id)
      %Photo{}

      iex> get!("invalid-id")
      ** (Ecto.NoResultsError)

  """
  @spec get!(Ecto.UUID.t(), keyword()) :: Photo.t()
  def get!(id, opts \\ []) do
    query = from p in Photo, where: p.id == ^id

    query
    |> apply_preload(opts[:preload])
    |> Repo.one!()
  end

  @doc """
  Insère une nouvelle photo.

  ## Exemples

      iex> insert(%{album_id: album_id, original_filename: "test.jpg", file_path: "/test.jpg"})
      {:ok, %Photo{}}

      iex> insert(%{album_id: nil})
      {:error, %Ecto.Changeset{}}

  """
  @spec insert(map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def insert(attrs) do
    %Photo{}
    |> Photo.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Met à jour une photo existante.

  ## Exemples

      iex> update(photo, %{title: "Nouveau titre"})
      {:ok, %Photo{}}

      iex> update(photo, %{display_order: -1})
      {:error, %Ecto.Changeset{}}

  """
  @spec update(Photo.t(), map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def update(%Photo{} = photo, attrs) do
    photo
    |> Photo.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Supprime une photo.

  ## Exemples

      iex> delete(photo)
      {:ok, %Photo{}}

  """
  @spec delete(Photo.t()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def delete(%Photo{} = photo) do
    Repo.delete(photo)
  end

  @doc """
  Réorganise l'ordre d'affichage des photos d'un album.

  Prend une liste d'IDs de photos dans l'ordre désiré et met à jour
  le champ display_order de chaque photo pour refléter sa position dans la liste.

  ## Paramètres

  - `album_id` - L'ID de l'album contenant les photos
  - `photo_ids` - Liste ordonnée des IDs de photos (premier = display_order 0)

  ## Exemples

      iex> reorder(album_id, [photo3_id, photo1_id, photo2_id])
      :ok

      # Photo 3 aura display_order = 0
      # Photo 1 aura display_order = 1
      # Photo 2 aura display_order = 2

  ## Erreurs

  Retourne `{:error, :invalid_photos}` si :
  - Une photo n'appartient pas à l'album spécifié
  - Un ID de photo n'existe pas

  """
  @spec reorder(Ecto.UUID.t(), [Ecto.UUID.t()]) :: {:ok, integer()} | {:error, :invalid_photos}
  def reorder(album_id, photo_ids) when is_list(photo_ids) do
    # Build a transaction with all updates using Ecto.Multi
    multi =
      Multi.new()
      |> Multi.run(:validate_photos, fn _repo, _changes ->
        # Vérifier que toutes les photos appartiennent à l'album
        photos = list_by_album(album_id)
        photo_ids_set = MapSet.new(photo_ids)
        existing_ids_set = MapSet.new(Enum.map(photos, & &1.id))

        if MapSet.subset?(photo_ids_set, existing_ids_set) do
          {:ok, photos}
        else
          {:error, :invalid_photos}
        end
      end)
      |> Multi.run(:reorder_photos, fn repo, %{validate_photos: _photos} ->
        # Update display_order for each photo
        # Note: For better performance with large albums (>100 photos),
        # this could be optimized with a single UPDATE query using CASE WHEN
        updated_count =
          Enum.with_index(photo_ids)
          |> Enum.reduce(0, fn {photo_id, index}, acc ->
            {count, _} =
              from(p in Photo, where: p.id == ^photo_id)
              |> repo.update_all(set: [display_order: index, updated_at: DateTime.utc_now()])

            acc + count
          end)

        {:ok, updated_count}
      end)

    case Repo.transaction(multi) do
      {:ok, %{reorder_photos: count}} -> {:ok, count}
      {:error, :validate_photos, :invalid_photos, _changes} -> {:error, :invalid_photos}
      {:error, _failed_operation, reason, _changes} -> {:error, reason}
    end
  end

  # Applique les preloads à la query en utilisant PhotoQuery
  @spec apply_preload(Ecto.Query.t(), nil | atom() | [atom()]) :: Ecto.Query.t()
  defp apply_preload(query, nil), do: query
  defp apply_preload(query, []), do: query

  defp apply_preload(query, preloads) do
    PhotoQuery.with_preload(query, preloads)
  end
end
