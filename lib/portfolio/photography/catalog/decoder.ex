defmodule Portfolio.Photography.Catalog.Decoder do
  @moduledoc """
  Traduit les charges utiles JSON du catalogue distant en structures du
  domaine.

  C'est la frontière de confiance du portfolio : tout ce qui entre par le
  réseau passe ici, et rien n'en ressort qui ne respecte pas le contrat. Le
  décodeur échoue franchement (`{:error, :invalid_payload}`) plutôt que de
  fabriquer une valeur de remplacement, parce qu'une réponse hors contrat est
  une panne de la plateforme : l'échelle de dégradation sait quoi en faire,
  alors qu'un album a moitié décode s'afficherait casse sans que personne ne
  le sache.

  Le même décodeur sert aux réponses HTTP et à la relecture de l'instantané
  sur disque : un seul chemin de validation, donc une seule chose a garder
  juste.
  """

  alias Portfolio.Photography.Catalog.Album
  alias Portfolio.Photography.Catalog.Photo
  alias Portfolio.Photography.Catalog.Source
  alias Portfolio.Photography.Catalog.Theme

  @type page :: %{albums: [Album.t()], meta: map()}

  @doc """
  Décode la réponse de la liste d'albums.
  """
  @spec decode_album_list(map()) :: {:ok, page()} | {:error, :invalid_payload}
  def decode_album_list(%{"data" => data} = payload) when is_list(data) do
    with {:ok, albums} <- map_ok(data, &decode_album_summary/1) do
      {:ok, %{albums: albums, meta: decode_list_meta(Map.get(payload, "meta"))}}
    end
  end

  def decode_album_list(_payload), do: {:error, :invalid_payload}

  @doc """
  Décode la réponse d'un album complet, photos triées par position croissante.
  """
  @spec decode_album(map()) :: {:ok, Album.t()} | {:error, :invalid_payload}
  def decode_album(%{"data" => data}) when is_map(data) do
    with {:ok, album} <- decode_album_summary(data),
         {:ok, photos} <- map_ok(Map.get(data, "photos", []), &decode_photo/1) do
      {:ok, %{album | photos: Enum.sort_by(photos, &(&1.position || 0))}}
    end
  end

  def decode_album(_payload), do: {:error, :invalid_payload}

  @doc """
  Décode la réponse de la liste des thèmes, ordonnee par position.
  """
  @spec decode_theme_list(map()) :: {:ok, [Theme.t()]} | {:error, :invalid_payload}
  def decode_theme_list(%{"data" => data}) when is_list(data) do
    with {:ok, themes} <- map_ok(data, &decode_theme/1) do
      {:ok, Enum.sort_by(themes, &(&1.position || 0))}
    end
  end

  def decode_theme_list(_payload), do: {:error, :invalid_payload}

  # ============================================================================
  # Décodage élément par élément
  # ============================================================================

  defp decode_album_summary(%{} = data) do
    with {:ok, slug} <- required_string(data, "slug"),
         {:ok, title} <- required_string(data, "title"),
         {:ok, canonical_url} <- required_string(data, "canonical_url"),
         {:ok, shoot_date} <- optional_date(data, "shoot_date"),
         {:ok, shoot_end_date} <- optional_date(data, "shoot_end_date"),
         {:ok, published_at} <- optional_datetime(data, "published_at"),
         {:ok, updated_at} <- optional_datetime(data, "updated_at"),
         {:ok, theme} <- optional_theme(Map.get(data, "theme")),
         {:ok, cover} <- optional_photo(Map.get(data, "cover")) do
      {:ok,
       %Album{
         slug: slug,
         title: title,
         description: optional_string(data, "description"),
         location: optional_string(data, "location"),
         shoot_date: shoot_date,
         shoot_end_date: shoot_end_date,
         reference_url: optional_string(data, "reference_url"),
         published_at: published_at,
         updated_at: updated_at,
         theme: theme,
         photo_count: optional_integer(data, "photo_count"),
         canonical_url: canonical_url,
         cover: cover,
         photos: []
       }}
    end
  end

  defp decode_album_summary(_), do: {:error, :invalid_payload}

  defp decode_photo(%{} = data) do
    with {:ok, id} <- required_string(data, "id"),
         {:ok, alt} <- required_string(data, "alt"),
         {:ok, sources} <- map_ok(Map.get(data, "sources", []), &decode_source/1),
         {:ok, sources} <- reject_empty(sources) do
      {:ok,
       %Photo{
         id: id,
         position: optional_integer(data, "position"),
         alt: alt,
         caption: optional_string(data, "caption"),
         credit: optional_string(data, "credit"),
         blurhash: optional_string(data, "blurhash"),
         width: optional_integer(data, "width"),
         height: optional_integer(data, "height"),
         sources: sources
       }}
    end
  end

  defp decode_photo(_), do: {:error, :invalid_payload}

  defp decode_source(%{} = data) do
    with {:ok, preset} <- required_string(data, "preset"),
         {:ok, format} <- required_string(data, "format"),
         {:ok, url} <- required_string(data, "url"),
         {:ok, width} <- required_integer(data, "width"),
         {:ok, height} <- required_integer(data, "height") do
      {:ok,
       %Source{
         preset: preset,
         format: format,
         url: url,
         width: width,
         height: height,
         bytes: optional_integer(data, "bytes")
       }}
    end
  end

  defp decode_source(_), do: {:error, :invalid_payload}

  defp decode_theme(%{} = data) do
    with {:ok, slug} <- required_string(data, "slug"),
         {:ok, name} <- required_string(data, "name") do
      {:ok,
       %Theme{
         slug: slug,
         name: name,
         description: optional_string(data, "description"),
         position: optional_integer(data, "position"),
         album_count: optional_integer(data, "album_count")
       }}
    end
  end

  defp decode_theme(_), do: {:error, :invalid_payload}

  defp decode_list_meta(%{} = meta) do
    %{
      total: optional_integer(meta, "total"),
      limit: optional_integer(meta, "limit"),
      offset: optional_integer(meta, "offset"),
      locale: optional_string(meta, "locale"),
      generated_at: optional_string(meta, "generated_at")
    }
  end

  defp decode_list_meta(_),
    do: %{total: nil, limit: nil, offset: nil, locale: nil, generated_at: nil}

  # ============================================================================
  # Extraction de champs
  # ============================================================================

  defp required_string(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> {:error, :invalid_payload}
          _ -> {:ok, value}
        end

      _ ->
        {:error, :invalid_payload}
    end
  end

  defp optional_string(data, key) do
    case Map.get(data, key) do
      value when is_binary(value) -> value
      _ -> nil
    end
  end

  defp required_integer(data, key) do
    case Map.get(data, key) do
      value when is_integer(value) -> {:ok, value}
      _ -> {:error, :invalid_payload}
    end
  end

  defp optional_integer(data, key) do
    case Map.get(data, key) do
      value when is_integer(value) -> value
      _ -> nil
    end
  end

  defp optional_date(data, key) do
    case Map.get(data, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case Date.from_iso8601(value) do
          {:ok, date} -> {:ok, date}
          {:error, _reason} -> {:error, :invalid_payload}
        end

      _ ->
        {:error, :invalid_payload}
    end
  end

  defp optional_datetime(data, key) do
    case Map.get(data, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        case DateTime.from_iso8601(value) do
          {:ok, datetime, _offset} -> {:ok, datetime}
          {:error, _reason} -> {:error, :invalid_payload}
        end

      _ ->
        {:error, :invalid_payload}
    end
  end

  defp optional_theme(nil), do: {:ok, nil}
  defp optional_theme(data), do: decode_theme(data)

  defp optional_photo(nil), do: {:ok, nil}
  defp optional_photo(data), do: decode_photo(data)

  defp reject_empty([]), do: {:error, :invalid_payload}
  defp reject_empty(list), do: {:ok, list}

  # Applique `fun` à chaque élément et s'arrête au premier échec.
  defp map_ok(list, fun) when is_list(list) do
    Enum.reduce_while(list, {:ok, []}, fn element, {:ok, acc} ->
      case fun.(element) do
        {:ok, decoded} -> {:cont, {:ok, [decoded | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp map_ok(_list, _fun), do: {:error, :invalid_payload}
end
