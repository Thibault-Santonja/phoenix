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

  # warn: false suppresses unused import warnings - query macros are used dynamically
  import Ecto.Query, warn: false
  import Portfolio.Repo.QueryHelpers

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
    fetch_one(id, opts)
    |> wrap_result()
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
    |> apply_preload_if_present(opts[:preload])
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
    multi =
      Multi.new()
      |> Multi.run(:validate_photos, fn _repo, _changes ->
        validate_photos_belong_to_album(album_id, photo_ids)
      end)
      |> Multi.run(:reorder_photos, fn repo, %{validate_photos: _photos} ->
        execute_reorder_query(repo, photo_ids)
      end)

    handle_reorder_transaction_result(Repo.transaction(multi))
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

  @doc """
  Liste les photos par statut de traitement.

  ## Paramètres

  - `status` - Le statut de traitement (pending, processing, completed, failed)

  ## Options

  - `:limit` - Nombre maximum de résultats (défaut: 100)
  - `:preload` - Associations à précharger

  ## Exemples

      iex> list_by_processing_status("pending", limit: 10)
      [%Photo{processing_status: "pending"}]

      iex> list_by_processing_status("failed", preload: [:album])
      [%Photo{processing_status: "failed", album: %Album{}}]
  """
  @spec list_by_processing_status(String.t(), keyword()) :: [Photo.t()]
  def list_by_processing_status(status, opts \\ []) do
    limit = Keyword.get(opts, :limit, 100)
    preload = Keyword.get(opts, :preload, [])

    from(p in Photo, where: p.processing_status == ^status, order_by: [desc: p.inserted_at])
    |> limit(^limit)
    |> apply_preload_if_present(preload)
    |> Repo.all()
  end

  @doc """
  Compte les photos par statut de traitement.

  Retourne une map avec les compteurs pour chaque statut.

  ## Exemples

      iex> count_by_processing_status()
      %{
        pending: 12,
        processing: 3,
        completed: 1247,
        failed: 5,
        total: 1267
      }
  """
  @spec count_by_processing_status() :: %{
          pending: non_neg_integer(),
          processing: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          total: non_neg_integer()
        }
  def count_by_processing_status do
    query =
      from p in Photo,
        select: {p.processing_status, count(p.id)},
        group_by: p.processing_status

    results = Repo.all(query)

    counts = %{
      pending: 0,
      processing: 0,
      completed: 0,
      failed: 0
    }

    counts =
      Enum.reduce(results, counts, fn {status, count}, acc ->
        # Safe mapping with explicit fallback for unknown statuses
        # This prevents crashes if a new status is added to DB before code update
        status_atom = safe_status_to_atom(status)

        if Map.has_key?(acc, status_atom) do
          Map.put(acc, status_atom, count)
        else
          # Unknown status - log and skip (don't crash)
          acc
        end
      end)

    total = Enum.reduce(Map.values(counts), 0, &(&1 + &2))
    Map.put(counts, :total, total)
  end

  @doc """
  Récupère la photo la plus ancienne par statut de traitement.

  Utile pour détecter les jobs bloqués.

  ## Exemples

      iex> get_oldest_by_processing_status("pending")
      {:ok, %Photo{}}

      iex> get_oldest_by_processing_status("pending")
      {:error, :not_found}
  """
  @spec get_oldest_by_processing_status(String.t()) :: {:ok, Photo.t()} | {:error, :not_found}
  def get_oldest_by_processing_status(status) do
    from(p in Photo,
      where: p.processing_status == ^status,
      order_by: [asc: p.inserted_at],
      limit: 1
    )
    |> Repo.one()
    |> wrap_result()
  end

  # Valide que toutes les photos de la liste appartiennent à l'album spécifié
  # Utilise une requête SQL optimisée au lieu de charger toutes les photos
  defp validate_photos_belong_to_album(_album_id, []), do: {:ok, []}

  defp validate_photos_belong_to_album(album_id, photo_ids) do
    existing_count =
      from(p in Photo,
        where: p.album_id == ^album_id and p.id in ^photo_ids
      )
      |> Repo.aggregate(:count)

    if existing_count == length(photo_ids) do
      {:ok, photo_ids}
    else
      {:error, :invalid_photos}
    end
  end

  # Exécute la requête SQL optimisée de réorganisation
  defp execute_reorder_query(_repo, []), do: {:ok, 0}

  defp execute_reorder_query(repo, photo_ids) do
    query = build_reorder_sql_query(photo_ids)
    params = build_reorder_query_params(photo_ids)

    case repo.query(query, params) do
      {:ok, %{num_rows: count}} -> {:ok, count}
      {:error, reason} -> {:error, reason}
    end
  end

  # Construit la requête SQL avec CASE WHEN pour une mise à jour atomique
  defp build_reorder_sql_query(photo_ids) do
    case_whens = build_case_when_clauses(photo_ids)

    """
    UPDATE photos
    SET
      display_order = CASE #{case_whens} END,
      updated_at = $1
    WHERE id = ANY($#{length(photo_ids) + 2}::uuid[])
    """
  end

  # Construit les clauses CASE WHEN pour associer chaque ID à son index
  defp build_case_when_clauses(photo_ids) do
    photo_ids
    |> Enum.with_index()
    |> Enum.map_join(" ", fn {_id, idx} ->
      "WHEN id = $#{idx + 2}::uuid THEN #{idx}"
    end)
  end

  # Prépare les paramètres de la requête avec les UUIDs au format binaire
  defp build_reorder_query_params(photo_ids) do
    now = DateTime.utc_now()
    binary_photo_ids = Enum.map(photo_ids, &Ecto.UUID.dump!/1)

    # [updated_at, photo_id1_binary, ..., photo_idN_binary, array_of_all_ids]
    [now] ++ binary_photo_ids ++ [binary_photo_ids]
  end

  # Gère le résultat de la transaction de réorganisation
  defp handle_reorder_transaction_result({:ok, %{reorder_photos: count}}), do: {:ok, count}

  defp handle_reorder_transaction_result({:error, :validate_photos, :invalid_photos, _changes}),
    do: {:error, :invalid_photos}

  defp handle_reorder_transaction_result({:error, _failed_operation, reason, _changes}),
    do: {:error, reason}

  # Construit la requête de base pour récupérer une photo par ID
  defp base_get_query(id) do
    from p in Photo, where: p.id == ^id
  end

  # Récupère une photo avec preload optionnel (retourne nil si non trouvée)
  defp fetch_one(id, opts) do
    base_get_query(id)
    |> apply_preload_if_present(opts[:preload])
    |> Repo.one()
  end

  # Applique les preloads à la query en utilisant PhotoQuery
  @spec apply_preload_if_present(Ecto.Query.t(), nil | atom() | [atom()]) :: Ecto.Query.t()
  defp apply_preload_if_present(query, nil), do: query
  defp apply_preload_if_present(query, []), do: query

  defp apply_preload_if_present(query, preloads) do
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
    |> apply_preload_if_present(preloads)
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

  # Safely converts processing status string to atom
  # Uses explicit mapping to prevent crashes from unknown statuses
  # (e.g., if a new status is added to DB before code update)
  @valid_statuses %{
    "pending" => :pending,
    "processing" => :processing,
    "completed" => :completed,
    "failed" => :failed
  }

  defp safe_status_to_atom(status) when is_atom(status), do: status

  defp safe_status_to_atom(status) when is_binary(status) do
    Map.get(@valid_statuses, status, :unknown)
  end

  defp safe_status_to_atom(_), do: :unknown
end
