defmodule Portfolio.Photography.Catalog.Source do
  @moduledoc """
  Une variante d'image servie par le stockage objet de la plateforme photo.

  Les images ne transitent jamais par le portfolio : `url` est absolue et
  pointe vers le prefixe public du stockage. Les dimensions sont portees par
  la source pour que le gabarit pose un `aspect-ratio` sans attendre le
  chargement, et n'introduise donc aucun decalage de mise en page.
  """

  @derive Jason.Encoder
  @enforce_keys [:preset, :format, :url, :width, :height]
  defstruct [:preset, :format, :url, :width, :height, :bytes]

  @type t :: %__MODULE__{
          preset: String.t(),
          format: String.t(),
          url: String.t(),
          width: pos_integer(),
          height: pos_integer(),
          bytes: non_neg_integer() | nil
        }
end
