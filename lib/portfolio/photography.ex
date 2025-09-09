defmodule Portfolio.Photography do
  @moduledoc """
  Photography Bounded Context - Gestion des albums photo et médias du portfolio.

  Ce contexte encapsule toute la logique métier liée à la photographie :
  - Gestion des albums photo (création, édition, publication)
  - Gestion des photos (upload, organisation, métadonnées)
  - Organisation par types (couples, wedding, music, reenactment, etc.)

  ## Ubiquitous Language

  - **Album** : Collection cohérente de photos autour d'un événement photographique
  - **Photo** : Image individuelle membre d'un album
  - **Published** : État d'un album visible publiquement (vs brouillon)
  - **Cover Photo** : Photo représentative d'un album (utilisée dans la timeline)
  - **Display Order** : Ordre d'affichage des photos au sein d'un album
  - **Type** : Catégorie métier de l'album (couples, wedding, music, etc.)
  - **Slug** : Identifiant URL-friendly unique généré depuis le titre

  ## Architecture

  Ce context suit les principes DDD et Clean Architecture :

  - **Domain Layer** : Entités (Album, Photo), Services métier
  - **Application Layer** : Ce module (API publique, orchestration)
  - **Infrastructure Layer** : Repositories, FileStorage

  ## Exemples

      # Lister tous les albums publiés groupés par année
      {:ok, albums_by_year} = Photography.list_published_albums_by_year()

      # Créer un nouvel album
      {:ok, album} = Photography.create_album(%{
        title: "Mariage de Claire & Damien",
        type: :wedding,
        date_prise_vue: ~D[2024-06-15],
        location: "Château de Coucy"
      })

      # Uploader des photos dans un album
      {:ok, photos} = Photography.upload_photos(album, uploads)

      # Publier un album
      {:ok, published_album} = Photography.publish_album(album)
  """

  alias Portfolio.DomainEvents
  alias Portfolio.Photography.{Album, Photo}
  alias Portfolio.Photography.Events.{AlbumPublished, PhotoUploaded}
  alias Portfolio.Photography.Repositories.{AlbumRepository, PhotoRepository}

  # =============================================================================
  # Album API
  # =============================================================================

  @doc """
  Liste tous les albums avec filtres optionnels.

  ## Options

  - `:type` - Filtre par type d'album
  - `:published` - Filtre par statut de publication
  - `:preload` - Associations à précharger

  ## Exemples

      iex> list_albums()
      [%Album{}, %Album{}]

      iex> list_albums(published: true)
      [%Album{published: true}]
  """
  @spec list_albums(keyword()) :: [Album.t()]
  def list_albums(opts \\ []), do: AlbumRepository.list(opts)

  @doc """
  Récupère un album par son ID.

  ## Exemples

      iex> get_album(id)
      {:ok, %Album{}}

      iex> get_album("invalid")
      {:error, :not_found}
  """
  @spec get_album(Ecto.UUID.t(), keyword()) :: {:ok, Album.t()} | {:error, :not_found}
  def get_album(id, opts \\ []), do: AlbumRepository.get(id, opts)

  @doc """
  Récupère un album par son ID, lève une exception si non trouvé.
  """
  @spec get_album!(Ecto.UUID.t(), keyword()) :: Album.t()
  def get_album!(id, opts \\ []), do: AlbumRepository.get!(id, opts)

  @doc """
  Crée un nouvel album.

  Émet un événement telemetry `[:portfolio, :photography, :album, :created]` avec
  la durée et le résultat de l'opération.

  ## Exemples

      iex> create_album(%{title: "Mon Album", type: :wedding, date_prise_vue: ~D[2024-01-01]})
      {:ok, %Album{}}
  """
  @spec create_album(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def create_album(attrs) do
    start_time = System.monotonic_time()

    result = AlbumRepository.insert(attrs)

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :photography, :album, :created],
      %{duration: duration},
      %{result: elem(result, 0)}
    )

    result
  end

  @doc """
  Met à jour un album existant.

  ## Exemples

      iex> update_album(album, %{title: "Nouveau titre"})
      {:ok, %Album{}}
  """
  @spec update_album(Album.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def update_album(album, attrs), do: AlbumRepository.update(album, attrs)

  @doc """
  Supprime un album et toutes ses photos (CASCADE).

  ## Exemples

      iex> delete_album(album)
      {:ok, %Album{}}
  """
  @spec delete_album(Album.t()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def delete_album(album), do: AlbumRepository.delete(album)

  @doc """
  Liste les albums publiés groupés par année.

  Retourne une map avec les années comme clés et les albums comme valeurs.

  ## Exemples

      iex> list_published_albums_by_year()
      %{2024 => [%Album{}], 2023 => [%Album{}]}
  """
  @spec list_published_albums_by_year(keyword()) :: %{integer() => [Album.t()]}
  def list_published_albums_by_year(opts \\ []), do: AlbumRepository.list_published_by_year(opts)

  @doc """
  Publie un album en le rendant visible publiquement.

  Émet un événement `AlbumPublished` pour permettre à d'autres contextes
  de réagir à la publication (notifications, indexation, etc.).

  ## Paramètres

  - `album` - L'album à publier
  - `user_id` - L'ID de l'utilisateur qui publie l'album (optionnel)

  ## Exemples

      iex> publish_album(album)
      {:ok, %Album{published: true}}

      iex> publish_album(album, user_id)
      {:ok, %Album{published: true}}
  """
  @spec publish_album(Album.t(), Ecto.UUID.t() | nil) ::
          {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def publish_album(%Album{} = album, user_id \\ nil) do
    with {:ok, album} <- AlbumRepository.update(album, %{published: true}) do
      # Émettre l'événement de domaine
      DomainEvents.publish(:album_published, %AlbumPublished{
        album_id: album.id,
        title: album.title,
        slug: album.slug,
        published_at: DateTime.utc_now(),
        user_id: user_id
      })

      {:ok, album}
    end
  end

  # =============================================================================
  # Photo API
  # =============================================================================

  @doc """
  Liste toutes les photos d'un album.

  ## Exemples

      iex> list_photos_by_album(album_id)
      [%Photo{}, %Photo{}]
  """
  @spec list_photos_by_album(Ecto.UUID.t(), keyword()) :: [Photo.t()]
  def list_photos_by_album(album_id, opts \\ []),
    do: PhotoRepository.list_by_album(album_id, opts)

  @doc """
  Récupère une photo par son ID.
  """
  @spec get_photo(Ecto.UUID.t(), keyword()) :: {:ok, Photo.t()} | {:error, :not_found}
  def get_photo(id, opts \\ []), do: PhotoRepository.get(id, opts)

  @doc """
  Récupère une photo par son ID, lève une exception si non trouvée.
  """
  @spec get_photo!(Ecto.UUID.t(), keyword()) :: Photo.t()
  def get_photo!(id, opts \\ []), do: PhotoRepository.get!(id, opts)

  @doc """
  Crée une nouvelle photo dans un album.

  Émet un événement `PhotoUploaded` après la création réussie de la photo.

  ## Exemples

      iex> create_photo(%{album_id: album_id, original_filename: "test.jpg", file_path: "/test.jpg"})
      {:ok, %Photo{}}
  """
  @spec create_photo(map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def create_photo(attrs) do
    with {:ok, photo} <- PhotoRepository.insert(attrs) do
      # Émettre l'événement de domaine
      DomainEvents.publish(:photo_uploaded, %PhotoUploaded{
        photo_id: photo.id,
        album_id: photo.album_id,
        file_path: photo.file_path,
        hash: photo.hash,
        uploaded_at: photo.inserted_at
      })

      {:ok, photo}
    end
  end

  @doc """
  Met à jour une photo existante.
  """
  @spec update_photo(Photo.t(), map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def update_photo(photo, attrs), do: PhotoRepository.update(photo, attrs)

  @doc """
  Supprime une photo ainsi que son fichier sur le disque.

  Cette opération supprime à la fois :
  - L'enregistrement en base de données
  - Le fichier physique via le FileStorage service

  ## Exemples

      iex> delete_photo(photo)
      {:ok, %Photo{}}

      iex> delete_photo(photo_with_invalid_file)
      {:error, :file_not_found}
  """
  @spec delete_photo(Photo.t()) :: {:ok, Photo.t()} | {:error, term()}
  def delete_photo(%Photo{} = photo) do
    # Supprimer le fichier via FileStorage
    case storage().delete_photo(photo.file_path) do
      :ok ->
        # Si le fichier est supprimé, supprimer l'enregistrement DB
        PhotoRepository.delete(photo)

      {:error, :not_found} ->
        # Si le fichier n'existe pas, supprimer quand même l'enregistrement DB
        # (cas de données orphelines)
        PhotoRepository.delete(photo)

      {:error, reason} ->
        # Autre erreur de suppression fichier
        {:error, reason}
    end
  end

  @doc """
  Upload des photos dans un album.

  Stocke les fichiers via FileStorage et crée les enregistrements en base.

  Émet un événement telemetry `[:portfolio, :photography, :photos, :uploaded]` avec
  la durée, le nombre de photos, et le résultat de l'opération.

  ## Paramètres

  - `album_slug` - Le slug de l'album (pour l'organisation des fichiers)
  - `uploads` - Liste d'uploads avec :path, :client_name, :client_type

  ## Retour

  - `{:ok, [%Photo{}]}` - Liste des photos créées
  - `{:error, reason}` - Erreur lors du stockage ou création

  ## Exemples

      iex> upload_photos("mariage-2024", uploads)
      {:ok, [%Photo{}, %Photo{}]}
  """
  @spec upload_photos(String.t(), [map()]) :: {:ok, [map()]} | {:error, term()}
  def upload_photos(album_slug, uploads) when is_list(uploads) do
    start_time = System.monotonic_time()
    count = length(uploads)

    # Pour chaque upload, stocker le fichier
    results =
      Enum.map(uploads, fn upload ->
        storage().store_photo(album_slug, upload)
      end)

    # Vérifier si toutes les opérations ont réussi
    result =
      if Enum.all?(results, &match?({:ok, _}, &1)) do
        photos_metadata = Enum.map(results, fn {:ok, meta} -> meta end)
        {:ok, photos_metadata}
      else
        # Récupérer la première erreur
        error = Enum.find(results, &match?({:error, _}, &1))
        error
      end

    duration = System.monotonic_time() - start_time

    :telemetry.execute(
      [:portfolio, :photography, :photos, :uploaded],
      %{duration: duration, count: count},
      %{album_slug: album_slug, result: elem(result, 0)}
    )

    result
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  defp storage do
    Application.get_env(:portfolio, :file_storage)[:backend] ||
      Portfolio.Photography.Storage.LocalStorage
  end

  @doc """
  Réorganise l'ordre d'affichage des photos d'un album.

  ## Exemples

      iex> reorder_photos(album_id, [photo1_id, photo2_id, photo3_id])
      {:ok, 3}
  """
  @spec reorder_photos(Ecto.UUID.t(), [Ecto.UUID.t()]) ::
          {:ok, integer()} | {:error, :invalid_photos}
  def reorder_photos(album_id, photo_ids), do: PhotoRepository.reorder(album_id, photo_ids)

  # =============================================================================
  # Helper Functions
  # =============================================================================

  @doc """
  Retourne la liste des types d'albums disponibles.

  ## Exemples

      iex> list_album_types()
      [:couples, :wedding, :motherhood, :events, :landscape, :street, :music, :reenactment, :amvcc, :china, :japan, :taiwan]
  """
  @spec list_album_types() :: [atom()]
  def list_album_types do
    [
      :couples,
      :wedding,
      :motherhood,
      :events,
      :landscape,
      :street,
      :music,
      :reenactment,
      :amvcc,
      :china,
      :japan,
      :taiwan
    ]
  end
end
