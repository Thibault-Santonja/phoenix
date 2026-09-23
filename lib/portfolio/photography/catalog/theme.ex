defmodule Portfolio.Photography.Catalog.Theme do
  @moduledoc """
  Theme du catalogue distant : la categorie editoriale d'un album.

  Remplace la taxonomie de chapitres codee en dur dans les gabarits du
  portfolio. Le `slug` est la cle stable, c'est lui qui circule dans les URL.
  """

  @derive Jason.Encoder
  @enforce_keys [:slug, :name]
  defstruct [:slug, :name, :description, :position, :album_count]

  @type t :: %__MODULE__{
          slug: String.t(),
          name: String.t(),
          description: String.t() | nil,
          position: integer() | nil,
          album_count: non_neg_integer() | nil
        }
end
