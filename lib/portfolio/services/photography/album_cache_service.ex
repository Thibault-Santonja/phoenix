defmodule Portfolio.Services.Photography.AlbumCacheService do
  @moduledoc """
  Service responsable du cache des albums publiés.

  Ce service encapsule la logique de cache pour le contexte Photography :
  - Gestion du cache des albums publiés par année
  - Invalidation du cache lors de publications/dépublications
  - Fallback vers la base de données en cas de cache miss

  ## Stratégie de Cache

  - **Clé de cache** : `{:published_albums_by_year, preloads}`
  - **TTL** : 1 heure
  - **Invalidation** : Lors de la publication/dépublication d'un album

  ## Mode Test

  En environnement test, le cache est automatiquement désactivé
  pour éviter la pollution entre tests.
  """

  alias Portfolio.Services.Photography.AlbumService

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
    alias Portfolio.Config.CacheConfig

    _ = Cachex.del(:portfolio_cache, CacheConfig.published_albums_key())
    _ = Cachex.del(:portfolio_cache, CacheConfig.published_albums_key(preloads: [:photos]))
    :ok
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  # En test, toujours skip le cache pour éviter la pollution entre tests
  if Mix.env() == :test do
    defp fetch_from_cache_or_db(opts) do
      AlbumService.fetch_published_albums_by_year(opts)
    end
  else
    alias Portfolio.Config.CacheConfig

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
  end
end
