defmodule Portfolio.Photography.Photo do
  @moduledoc """
  Photo Entity - Représente une photo membre d'un album.

  Une Photo est une entité enfant de l'agrégat Album. Elle ne peut exister
  sans un Album parent et est toujours manipulée dans le contexte de son Album.

  ## Invariants

  - Une photo DOIT appartenir à un album (album_id requis)
  - Une photo DOIT avoir un fichier original (original_filename, file_path requis)
  - Le slug DOIT être unique dans le contexte de son album
  - Le hash DOIT être unique globalement (évite les doublons)
  - L'ordre d'affichage DOIT être >= 0
  - Si published = false, la photo n'est pas visible publiquement

  ## Types

  - `id`: Identifiant unique UUID
  - `album_id`: Référence à l'album parent (clé étrangère)
  - `title`: Titre optionnel de la photo (max 200 caractères)
  - `description`: Description optionnelle (max 2000 caractères)
  - `slug`: Identifiant URL-friendly unique dans l'album
  - `display_order`: Ordre d'affichage dans l'album (défaut: 0)
  - `taken_at`: Date de prise de vue optionnelle
  - `published`: État de publication (défaut: true)
  - `original_filename`: Nom du fichier original
  - `file_path`: Chemin du fichier stocké
  - `hash`: Hash SHA256 du fichier pour déduplication
  - `mime_type`: Type MIME du fichier (ex: "image/jpeg")
  - `exif_data`: Métadonnées EXIF extraites (map JSON)
  - `variants`: Map contenant les URLs des variantes générées (thumbnail, small, medium, large)
  - `processing_status`: État du traitement des variantes (pending, processing, completed, failed)

  ## Exemple

      iex> changeset = Photo.changeset(%Photo{}, %{
      ...>   album_id: "550e8400-e29b-41d4-a716-446655440000",
      ...>   original_filename: "IMG_1234.jpg",
      ...>   file_path: "/uploads/photos/2024/img_1234.jpg",
      ...>   title: "Coucher de soleil",
      ...>   display_order: 1
      ...> })
      iex> changeset.valid?
      true

  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolio.Photography.Album
  alias Portfolio.Photography.ValueObjects.Slug

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          album_id: Ecto.UUID.t(),
          album: Album.t() | Ecto.Association.NotLoaded.t() | nil,
          title: String.t() | nil,
          description: String.t() | nil,
          slug: String.t() | nil,
          display_order: integer(),
          taken_at: Date.t() | nil,
          published: boolean(),
          original_filename: String.t(),
          file_path: String.t(),
          hash: String.t() | nil,
          mime_type: String.t() | nil,
          exif_data: map(),
          variants: map(),
          processing_status: String.t(),
          # EXIF metadata fields (ADR-011 Phase 3)
          captured_at: DateTime.t() | nil,
          camera: String.t() | nil,
          lens: String.t() | nil,
          iso: integer() | nil,
          aperture: String.t() | nil,
          focal_length: String.t() | nil,
          shutter_speed: String.t() | nil,
          gps_latitude: float() | nil,
          gps_longitude: float() | nil,
          inserted_at: NaiveDateTime.t() | nil,
          updated_at: NaiveDateTime.t() | nil
        }

  schema "photos" do
    belongs_to :album, Album

    field :title, :string
    field :description, :string
    field :slug, :string
    field :display_order, :integer, default: 0
    field :taken_at, :date
    field :published, :boolean, default: true
    field :original_filename, :string
    field :file_path, :string
    field :hash, :string
    field :mime_type, :string
    field :exif_data, :map, default: %{}
    field :variants, :map, default: %{}
    field :processing_status, :string, default: "pending"

    # EXIF metadata fields (ADR-011 Phase 3)
    field :captured_at, :utc_datetime
    field :camera, :string
    field :lens, :string
    field :iso, :integer
    field :aperture, :string
    field :focal_length, :string
    field :shutter_speed, :string
    field :gps_latitude, :float
    field :gps_longitude, :float

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset pour la création et modification d'une Photo.

  ## Champs requis

  - `:album_id` - L'album parent
  - `:original_filename` - Nom du fichier original
  - `:file_path` - Chemin du fichier stocké

  ## Validations

  - `title`: max 200 caractères
  - `description`: max 2000 caractères
  - `display_order`: doit être >= 0
  - `slug`: unique dans l'album, généré automatiquement depuis le title si présent
  - `hash`: unique globalement
  - `taken_at`: ne peut pas être dans le futur

  ## Exemples

      iex> changeset = Photo.changeset(%Photo{}, %{album_id: album_id, original_filename: "test.jpg", file_path: "/test.jpg"})
      iex> changeset.valid?
      true

      iex> changeset = Photo.changeset(%Photo{}, %{original_filename: "test.jpg"})
      iex> changeset.valid?
      false

  """
  @valid_processing_statuses ~w(pending processing completed failed)

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(photo, attrs) do
    photo
    |> cast(attrs, [
      :album_id,
      :title,
      :description,
      :slug,
      :display_order,
      :taken_at,
      :published,
      :original_filename,
      :file_path,
      :hash,
      :mime_type,
      :exif_data,
      :variants,
      :processing_status,
      # EXIF metadata fields
      :captured_at,
      :camera,
      :lens,
      :iso,
      :aperture,
      :focal_length,
      :shutter_speed,
      :gps_latitude,
      :gps_longitude
    ])
    |> validate_required([:album_id, :original_filename, :file_path])
    |> validate_length(:title, max: 200)
    |> validate_length(:description, max: 2000)
    |> validate_number(:display_order, greater_than_or_equal_to: 0)
    |> validate_date_not_future(:taken_at)
    |> validate_inclusion(:processing_status, @valid_processing_statuses)
    |> generate_slug()
    |> foreign_key_constraint(:album_id)
    |> unique_constraint(:hash)
    |> unique_constraint([:album_id, :slug], name: :photos_album_id_slug_index)
  end

  # Génère un slug URL-friendly depuis le titre s'il est présent en utilisant le Value Object Slug
  @spec generate_slug(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp generate_slug(changeset) do
    case get_change(changeset, :title) do
      nil ->
        changeset

      title ->
        case Slug.new(title) do
          {:ok, slug} ->
            put_change(changeset, :slug, to_string(slug))

          {:error, :too_long} ->
            # Si le titre est trop long pour un slug, on laisse la validation de length gérer l'erreur
            changeset

          {:error, _} ->
            add_error(changeset, :title, "ne peut pas être converti en slug valide")
        end
    end
  end

  @doc """
  Vérifie si la photo est en cours de traitement (pending ou processing).

  ## Exemples

      iex> photo = %Photo{processing_status: "pending"}
      iex> Photo.processing?(photo)
      true

      iex> photo = %Photo{processing_status: "completed"}
      iex> Photo.processing?(photo)
      false

  """
  @spec processing?(t()) :: boolean()
  def processing?(%__MODULE__{processing_status: status})
      when status in ["pending", "processing"],
      do: true

  def processing?(%__MODULE__{}), do: false

  @doc """
  Vérifie si le traitement de la photo a échoué.

  ## Exemples

      iex> photo = %Photo{processing_status: "failed"}
      iex> Photo.failed?(photo)
      true

      iex> photo = %Photo{processing_status: "completed"}
      iex> Photo.failed?(photo)
      false

  """
  @spec failed?(t()) :: boolean()
  def failed?(%__MODULE__{processing_status: "failed"}), do: true
  def failed?(%__MODULE__{}), do: false

  # Valide qu'une date n'est pas dans le futur
  @spec validate_date_not_future(Ecto.Changeset.t(), atom()) :: Ecto.Changeset.t()
  defp validate_date_not_future(changeset, field) do
    validate_change(changeset, field, fn ^field, date ->
      if Date.compare(date, Date.utc_today()) == :gt do
        [{field, "ne peut pas être dans le futur"}]
      else
        []
      end
    end)
  end
end
