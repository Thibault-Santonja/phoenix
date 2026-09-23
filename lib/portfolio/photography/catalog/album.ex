defmodule Portfolio.Photography.Catalog.Album do
  @moduledoc """
  Un album publie, tel que le catalogue distant l'expose.

  `canonical_url` est calculee par la plateforme photo et jamais reconstruite
  ici par concatenation : une reorganisation de ses URL ne demande alors aucun
  deploiement du portfolio.

  Un resume d'album (liste) porte `cover` et une liste `photos` vide ; un
  album complet (fiche) porte ses `photos` triees par position.
  """

  alias Portfolio.Photography.Catalog.Photo
  alias Portfolio.Photography.Catalog.Theme

  @derive Jason.Encoder
  @enforce_keys [:slug, :title, :canonical_url]
  defstruct [
    :slug,
    :title,
    :description,
    :location,
    :shoot_date,
    :shoot_end_date,
    :reference_url,
    :published_at,
    :updated_at,
    :theme,
    :photo_count,
    :canonical_url,
    :cover,
    photos: []
  ]

  @type t :: %__MODULE__{
          slug: String.t(),
          title: String.t(),
          description: String.t() | nil,
          location: String.t() | nil,
          shoot_date: Date.t() | nil,
          shoot_end_date: Date.t() | nil,
          reference_url: String.t() | nil,
          published_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil,
          theme: Theme.t() | nil,
          photo_count: non_neg_integer() | nil,
          canonical_url: String.t(),
          cover: Photo.t() | nil,
          photos: [Photo.t()]
        }
end
