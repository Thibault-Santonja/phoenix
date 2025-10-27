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
  Liste toutes les photos avec options de filtrage.

  ## Options

  - `:album_id` - Filtre par ID d'album
  - `:limit` - Limite le nombre de résultats
  - `:offset` - Décalage pour la pagination
  - `:preload` - Associations à précharger
  - `:order_by` - Ordre de tri

  ## Exemples

      iex> list()
      [%Photo{}, %Photo{}]

      iex> list(album_id: album_id, limit: 10, preload: [:album])
      [%Photo{album: %Album{}}]
  """
  @spec list(keyword()) :: [Photo.t()]
  def list(opts \\ []) do
    PhotoQuery.base()
    |> apply_filters(opts)
    |> Repo.all()
  end

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
    # Utilise apply_filters pour une gestion cohérente des preloads
    opts_with_album = Keyword.put(opts, :album_id, album_id)

    PhotoQuery.base()
    |> PhotoQuery.order_by_display_order()
    |> apply_filters(opts_with_album)
    |> Repo.all()
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
    base_get_query(id)
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
    base_get_query(id)
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
        # Handle empty list edge case
        if Enum.empty?(photo_ids) do
          {:ok, 0}
        else
          # Optimized: Single UPDATE query using CASE WHEN instead of N queries
          # 100 photos: 100 UPDATE queries → 1 UPDATE query
          now = DateTime.utc_now()

          # Convert UUIDs to binary format for Postgrex
          binary_photo_ids = Enum.map(photo_ids, &Ecto.UUID.dump!/1)

          # Build CASE WHEN clauses for display_order
          case_whens =
            photo_ids
            |> Enum.with_index()
            |> Enum.map_join(" ", fn {_id, idx} ->
              "WHEN id = $#{idx + 2}::uuid THEN #{idx}"
            end)

          # Build parameterized query
          query = """
          UPDATE photos
          SET
            display_order = CASE #{case_whens} END,
            updated_at = $1
          WHERE id = ANY($#{length(photo_ids) + 2}::uuid[])
          """

          # Parameters: [updated_at, photo_id1_binary, ..., photo_idN_binary, array_of_photo_ids_binary]
          params = [now] ++ binary_photo_ids ++ [binary_photo_ids]

          case repo.query(query, params) do
            {:ok, %{num_rows: count}} -> {:ok, count}
            {:error, reason} -> {:error, reason}
          end
        end
      end)

    case Repo.transaction(multi) do
      {:ok, %{reorder_photos: count}} -> {:ok, count}
      {:error, :validate_photos, :invalid_photos, _changes} -> {:error, :invalid_photos}
      {:error, _failed_operation, reason, _changes} -> {:error, reason}
    end
  end

  @doc """
  Compte le nombre de photos dans un album.

  ## Exemples

      iex> count_by_album(album_id)
      42
  """
  @spec count_by_album(Ecto.UUID.t()) :: non_neg_integer()
  def count_by_album(album_id) do
    from(p in Photo, where: p.album_id == ^album_id)
    |> Repo.aggregate(:count)
  end

  @doc """
  Compte le nombre total de photos dans tous les albums.

  Utilise une seule requête SQL optimisée au lieu de compter album par album.

  ## Exemples

      iex> count_all()
      42
  """
  @spec count_all() :: non_neg_integer()
  def count_all do
    Repo.aggregate(Photo, :count)
  end

  # Construit la requête de base pour récupérer une photo par ID
  defp base_get_query(id) do
    from p in Photo, where: p.id == ^id
  end

  # Applique les preloads à la query en utilisant PhotoQuery
  @spec apply_preload(Ecto.Query.t(), nil | atom() | [atom()]) :: Ecto.Query.t()
  defp apply_preload(query, nil), do: query
  defp apply_preload(query, []), do: query

  defp apply_preload(query, preloads) do
    PhotoQuery.with_preload(query, preloads)
  end

  # Applique les filtres à la query
  defp apply_filters(query, []), do: query

  defp apply_filters(query, [{:album_id, album_id} | rest]) do
    query
    |> PhotoQuery.by_album(album_id)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:preload, preloads} | rest]) do
    query
    |> apply_preload(preloads)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:limit, limit} | rest]) when is_integer(limit) do
    query
    |> limit(^limit)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:offset, offset} | rest]) when is_integer(offset) do
    query
    |> offset(^offset)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [{:order_by, order_spec} | rest]) when is_list(order_spec) do
    query
    |> order_by(^order_spec)
    |> apply_filters(rest)
  end

  defp apply_filters(query, [_other | rest]) do
    apply_filters(query, rest)
  end
end
