defmodule Portfolio.Photography.Services.AlbumCacheService do
  @moduledoc """
  Service responsable du cache des albums publiés.

  Ce service encapsule la logique de cache pour le contexte Photography :
  - Gestion du cache des albums publiés par année
  - Gestion du cache des albums individuels par slug
  - Invalidation du cache lors de publications/dépublications
  - Fallback vers la base de données en cas de cache miss

  ## Stratégie de Cache

  - **Clé albums par année** : `{:published_albums_by_year, preloads}` - TTL 1h
  - **Clé album par slug** : `{:album, slug, preloads}` - TTL 1h
  - **Invalidation** : Lors de la publication/dépublication/modification d'un album

  ## Mode Test

  En environnement test, le cache est automatiquement désactivé
  pour éviter la pollution entre tests.
  """

  alias Portfolio.Config.CacheConfig
  alias Portfolio.Photography.Services.AlbumService

  @doc """
  Liste les albums publiés groupés par année avec cache.

  Utilise Cachex pour mettre en cache les résultats.

  ## Options

  - `:preload` - Associations à précharger
  - `:skip_cache` - Ignorer le cache (défaut: false)

  ## Exemples

      iex> list_published_albums_by_year()
      %{2024 => [%Album{}], 2023 => [%Album{}]}
  """
  @spec list_published_albums_by_year(keyword()) ::
          %{integer() => [Portfolio.Photography.Album.t()]}
  def list_published_albums_by_year(opts \\ []) do
    if Keyword.get(opts, :skip_cache, false) do
      AlbumService.fetch_published_albums_by_year(opts)
    else
      fetch_from_cache_or_db(opts)
    end
  end

  @doc """
  Liste tous les albums publiés (liste plate pour sitemap, etc.).

  ## Options

  - `:preload` - Associations à précharger (défaut: aucune)

  ## Exemples

      iex> list_published_albums()
      [%Album{}, %Album{}]
  """
  @spec list_published_albums(keyword()) :: [Portfolio.Photography.Album.t()]
  def list_published_albums(opts \\ []) do
    list_published_albums_by_year(opts)
    |> Map.values()
    |> List.flatten()
  end

  @doc """
  Récupère un album par son slug avec cache.

  ## Options

  - `:preload` - Associations à précharger
  - `:skip_cache` - Ignorer le cache (défaut: false)

  ## Exemples

      iex> get_album_by_slug("wedding-2024")
      {:ok, %Album{}}

      iex> get_album_by_slug("nonexistent")
      {:error, :not_found}
  """
  @spec get_album_by_slug(String.t(), keyword()) ::
          {:ok, Portfolio.Photography.Album.t()} | {:error, :not_found}
  def get_album_by_slug(slug, opts \\ []) do
    if Keyword.get(opts, :skip_cache, false) do
      AlbumService.get_album_by_slug(slug, opts)
    else
      fetch_album_from_cache_or_db(slug, opts)
    end
  end

  @doc """
  Invalide tous les caches liés aux albums publiés.

  Doit être appelée après toute opération affectant les albums publiés :
  - Publication d'un album
  - Dépublication d'un album
  - Mise à jour d'un album publié
  - Suppression d'un album publié

  ## Exemples

      iex> invalidate_cache()
      :ok
  """
  @spec invalidate_cache() :: :ok
  def invalidate_cache do
    _ = Cachex.del(:portfolio_cache, CacheConfig.published_albums_key())
    _ = Cachex.del(:portfolio_cache, CacheConfig.published_albums_key(preloads: [:photos]))
    :ok
  end

  @doc """
  Invalide le cache pour un album spécifique par son slug.

  ## Exemples

      iex> invalidate_album_cache("wedding-2024")
      :ok
  """
  @spec invalidate_album_cache(String.t()) :: :ok
  def invalidate_album_cache(slug) when is_binary(slug) do
    _ = Cachex.del(:portfolio_cache, CacheConfig.album_key(slug))
    _ = Cachex.del(:portfolio_cache, CacheConfig.album_key(slug, preloads: [:photos]))
    # Also invalidate the year listings since they may contain this album
    invalidate_cache()
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  # En test, toujours skip le cache pour éviter la pollution entre tests
  if Mix.env() == :test do
    defp fetch_from_cache_or_db(opts) do
      AlbumService.fetch_published_albums_by_year(opts)
    end

    defp fetch_album_from_cache_or_db(slug, opts) do
      AlbumService.get_album_by_slug(slug, opts)
    end
  else
    defp fetch_from_cache_or_db(opts) do
      cache_key = CacheConfig.published_albums_key(preloads: opts[:preload] || [])

      case Cachex.fetch(:portfolio_cache, cache_key, fn ->
             result = AlbumService.fetch_published_albums_by_year(opts)
             {:commit, result, ttl: CacheConfig.albums_ttl()}
           end) do
        {:ok, albums} -> albums
        {:commit, albums} -> albums
        {:ignore, albums} -> albums
        {:error, _reason} -> AlbumService.fetch_published_albums_by_year(opts)
      end
    end

    defp fetch_album_from_cache_or_db(slug, opts) do
      cache_key = CacheConfig.album_key(slug, preloads: opts[:preload] || [])

      case Cachex.fetch(:portfolio_cache, cache_key, &compute_album_value(slug, opts, &1)) do
        {:ok, result} -> result
        {:commit, result} -> result
        {:ignore, result} -> result
        {:error, _reason} -> AlbumService.get_album_by_slug(slug, opts)
      end
    end

    defp compute_album_value(slug, opts, _key) do
      case AlbumService.get_album_by_slug(slug, opts) do
        {:ok, album} -> {:commit, {:ok, album}, ttl: CacheConfig.album_ttl()}
        {:error, :not_found} -> {:ignore, {:error, :not_found}}
      end
    end
  end
end
