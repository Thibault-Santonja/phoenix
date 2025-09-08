defmodule Portfolio.Photography.Album do
  @moduledoc """
  Album Aggregate Root - Représente un album photo du portfolio.

  Un album est une collection cohérente de photos autour d'un événement photographique
  (mariage, concert, reconstitution historique, etc.). C'est l'aggregate root du
  bounded context Photography.

  ## Invariants

  - Un album DOIT avoir un titre (3-200 caractères)
  - Un album DOIT avoir un type valide parmi les types définis
  - Un album DOIT avoir une date de début de prise de vue (≤ aujourd'hui)
  - Un album PEUT avoir une date de fin de prise de vue (optionnel, doit être ≥ date de début et ≤ aujourd'hui)
  - Le slug DOIT être unique globalement
  - La photo de couverture est toujours la première photo triée par display_order

  ## Types Valides

  - `:couples` - Séances photos de couples
  - `:wedding` - Mariages
  - `:motherhood` - Maternité et familles
  - `:events` - Événements divers
  - `:landscape` - Paysages
  - `:street` - Photographie de rue
  - `:music` - Concerts et musique
  - `:reenactment` - Reconstitution historique
  - `:amvcc` - Association AMVCC
  - `:china` - Voyage en Chine
  - `:japan` - Voyage au Japon
  - `:taiwan` - Voyage à Taïwan

  ## Exemples

      # Créer un nouvel album
      iex> changeset = Album.changeset(%Album{}, %{
      ...>   title: "Mariage de Claire & Damien",
      ...>   type: :wedding,
      ...>   date_prise_vue: ~D[2024-06-15],
      ...>   location: "Château de Coucy"
      ...> })
      iex> changeset.valid?
      true

      # Le slug est généré automatiquement
      iex> Ecto.Changeset.get_change(changeset, :slug)
      "mariage-de-claire-damien"

      # Validation des dates futures
      iex> future_date = Date.add(Date.utc_today(), 1)
      iex> changeset = Album.changeset(%Album{}, %{
      ...>   title: "Album futur",
      ...>   type: :wedding,
      ...>   date_prise_vue: future_date
      ...> })
      iex> changeset.valid?
      false
  """

  use Ecto.Schema
  import Ecto.Changeset

  alias Portfolio.Photography.Photo
  alias Portfolio.Photography.ValueObjects.Slug

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @type t :: %__MODULE__{
          id: Ecto.UUID.t() | nil,
          title: String.t(),
          slug: String.t(),
          type: atom(),
          description: String.t() | nil,
          location: String.t() | nil,
          date_prise_vue: Date.t(),
          date_fin_prise_vue: Date.t() | nil,
          published: boolean(),
          reference_link: String.t() | nil,
          photos: [Photo.t()] | Ecto.Association.NotLoaded.t(),
          exif_data: map(),
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @album_types ~w(couples wedding motherhood events landscape street music reenactment amvcc china japan taiwan)a

  schema "albums" do
    field :title, :string
    field :slug, :string
    field :type, Ecto.Enum, values: @album_types
    field :description, :string
    field :location, :string
    field :date_prise_vue, :date
    field :date_fin_prise_vue, :date
    field :published, :boolean, default: false
    field :reference_link, :string
    field :exif_data, :map, default: %{}

    has_many :photos, Photo

    timestamps(type: :utc_datetime)
  end

  @doc """
  Crée un changeset pour un album.

  ## Validations

  - `title` : requis, longueur entre 3 et 200 caractères
  - `type` : requis, doit être un type valide
  - `date_prise_vue` : requis, ne peut pas être dans le futur
  - `date_fin_prise_vue` : optionnel, ne peut pas être dans le futur, doit être ≥ date_prise_vue
  - `description` : optionnel, max 5000 caractères
  - `slug` : généré automatiquement depuis le titre, unique

  ## Exemples

      iex> Album.changeset(%Album{}, %{title: "Mon Album", type: :wedding, date_prise_vue: ~D[2024-01-01]})
      %Ecto.Changeset{valid?: true}

      iex> Album.changeset(%Album{}, %{title: "AB"})  # Titre trop court
      %Ecto.Changeset{valid?: false}
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(album, attrs) do
    album
    |> cast(attrs, [
      :title,
      :type,
      :description,
      :location,
      :date_prise_vue,
      :date_fin_prise_vue,
      :published,
      :reference_link,
      :exif_data
    ])
    |> validate_required([:title, :type, :date_prise_vue])
    |> validate_length(:title, min: 3, max: 200)
    |> validate_length(:description, max: 5000)
    |> validate_date_not_future(:date_prise_vue)
    |> validate_date_not_future(:date_fin_prise_vue)
    |> validate_date_range()
    |> generate_slug()
    |> unique_constraint(:slug)
  end

  # Génère un slug URL-friendly depuis le titre en utilisant le Value Object Slug
  @spec generate_slug(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp generate_slug(changeset) do
    case get_change(changeset, :title) do
      nil ->
        changeset

      title ->
        case Slug.new(title) do
          {:ok, slug} ->
            put_change(changeset, :slug, to_string(slug))

          {:error, _} ->
            add_error(changeset, :title, "ne peut pas être converti en slug valide")
        end
    end
  end

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

  # Valide que la date de fin est après la date de début
  @spec validate_date_range(Ecto.Changeset.t()) :: Ecto.Changeset.t()
  defp validate_date_range(changeset) do
    date_debut = get_field(changeset, :date_prise_vue)
    date_fin = get_field(changeset, :date_fin_prise_vue)

    if date_debut && date_fin && Date.compare(date_fin, date_debut) == :lt do
      add_error(changeset, :date_fin_prise_vue, "doit être après ou égale à la date de début")
    else
      changeset
    end
  end
end
