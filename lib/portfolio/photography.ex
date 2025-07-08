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

  alias Portfolio.Photography.{Album, Photo}
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

  ## Exemples

      iex> create_album(%{title: "Mon Album", type: :wedding, date_prise_vue: ~D[2024-01-01]})
      {:ok, %Album{}}
  """
  @spec create_album(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}
  def create_album(attrs), do: AlbumRepository.insert(attrs)

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

  ## Exemples

      iex> create_photo(%{album_id: album_id, original_filename: "test.jpg", file_path: "/test.jpg"})
      {:ok, %Photo{}}
  """
  @spec create_photo(map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def create_photo(attrs), do: PhotoRepository.insert(attrs)

  @doc """
  Met à jour une photo existante.
  """
  @spec update_photo(Photo.t(), map()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def update_photo(photo, attrs), do: PhotoRepository.update(photo, attrs)

  @doc """
  Supprime une photo.
  """
  @spec delete_photo(Photo.t()) :: {:ok, Photo.t()} | {:error, Ecto.Changeset.t()}
  def delete_photo(photo), do: PhotoRepository.delete(photo)

  @doc """
  Réorganise l'ordre d'affichage des photos d'un album.

  ## Exemples

      iex> reorder_photos(album_id, [photo1_id, photo2_id, photo3_id])
      :ok
  """
  @spec reorder_photos(Ecto.UUID.t(), [Ecto.UUID.t()]) :: :ok | {:error, :invalid_photos}
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
