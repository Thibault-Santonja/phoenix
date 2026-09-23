defmodule Portfolio.Photography.Catalog.Photo do
  @moduledoc """
  Une photo publiée, telle que le catalogue distant l'expose.

  `id` est l'identifiant opaque de la jointure album-photo côté plateforme :
  il ne sert qu'a identifier l'élément dans un flux LiveView, jamais a
  reconstruire une URL. `alt` n'est jamais vide, la plateforme le garantit et
  le décodeur le vérifie : une image sans texte alternatif est inaccessible et
  n'a pas sa place sur une page publique.
  """

  alias Portfolio.Photography.Catalog.Source

  @derive Jason.Encoder
  @enforce_keys [:id, :alt, :sources]
  defstruct [:id, :position, :alt, :caption, :credit, :blurhash, :width, :height, sources: []]

  @type t :: %__MODULE__{
          id: String.t(),
          position: integer() | nil,
          alt: String.t(),
          caption: String.t() | nil,
          credit: String.t() | nil,
          blurhash: String.t() | nil,
          width: pos_integer() | nil,
          height: pos_integer() | nil,
          sources: [Source.t()]
        }

  @doc """
  Retourne la source du preset demandé, dans le premier format disponible
  parmi `formats`, ou `nil` si aucune ne convient.

  L'ordre de `formats` est celui de la préférence : le gabarit demande l'AVIF
  puis retombe sur le WebP, comme le veut la règle de performance du dépôt.
  """
  @spec source(t(), String.t(), [String.t()]) :: Source.t() | nil
  def source(%__MODULE__{sources: sources}, preset, formats) do
    Enum.find_value(formats, fn format ->
      Enum.find(sources, &(&1.preset == preset and &1.format == format))
    end)
  end

  @doc """
  Retourne l'URL à poser dans l'attribut `src`.

  Le `src` est le filet de sécurité des navigateurs qui ne comprennent ni
  `srcset` ni `<picture>` : il porte donc le format le plus universel
  disponible, le JPEG quand il existe, le WebP sinon.
  """
  @spec fallback_url(t(), String.t()) :: String.t() | nil
  def fallback_url(%__MODULE__{} = photo, preset) do
    case source(photo, preset, ["jpeg", "webp", "avif"]) do
      nil -> nil
      %Source{url: url} -> url
    end
  end

  @doc """
  Construit la valeur d'un attribut `srcset` pour un format donné.

  Retourne `nil` quand aucune source n'existe dans ce format, ce qui permet au
  gabarit d'omettre entierement la balise `<source>` correspondante.
  """
  @spec srcset(t(), String.t(), [String.t()]) :: String.t() | nil
  def srcset(%__MODULE__{sources: sources}, format, presets) do
    descriptors =
      for preset <- presets,
          source = Enum.find(sources, &(&1.preset == preset and &1.format == format)),
          do: "#{source.url} #{source.width}w"

    case descriptors do
      [] -> nil
      descriptors -> Enum.join(descriptors, ", ")
    end
  end
end
