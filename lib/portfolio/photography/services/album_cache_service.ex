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

  ## Architecture

  Ce service utilise le module `Portfolio.Cache` qui délègue à la stratégie
  configurée (CachexStrategy en production, NoOpStrategy en test).
  """

  alias Portfolio.Cache
  alias Portfolio.Config.CacheConfig
  alias Portfolio.Photography.Services.AlbumService

  @doc """
  Liste les albums publiés groupés par année avec cache.

  Utilise la stratégie de cache configurée pour mettre en cache les résultats.

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
      cache_key = CacheConfig.published_albums_key(preloads: opts[:preload] || [])

      Cache.fetch(
        cache_key,
        fn -> AlbumService.fetch_published_albums_by_year(opts) end,
        ttl: CacheConfig.albums_ttl()
      )
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
      cache_key = CacheConfig.album_key(slug, preloads: opts[:preload] || [])

      Cache.fetch(
        cache_key,
        fn -> AlbumService.get_album_by_slug(slug, opts) end,
        ttl: CacheConfig.album_ttl()
      )
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
    :ok = Cache.invalidate(CacheConfig.published_albums_key())
    :ok = Cache.invalidate(CacheConfig.published_albums_key(preloads: [:photos]))
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
    :ok = Cache.invalidate(CacheConfig.album_key(slug))
    :ok = Cache.invalidate(CacheConfig.album_key(slug, preloads: [:photos]))
    # Also invalidate the year listings since they may contain this album
    invalidate_cache()
  end
end
