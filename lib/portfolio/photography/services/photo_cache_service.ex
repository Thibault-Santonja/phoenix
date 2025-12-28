defmodule Portfolio.Photography.Services.PhotoCacheService do
  @moduledoc """
  Service responsable du cache des statistiques de photos.

  Ce service encapsule la logique de cache pour les opérations photos :
  - Statistiques de traitement (pending, completed, failed)

  ## Stratégie de Cache

  - **Clé stats** : `:photo_processing_stats` - TTL 5min
  - **Invalidation** : Après traitement d'une photo

  ## Mode Test

  En environnement test, le cache est automatiquement désactivé
  pour éviter la pollution entre tests.
  """

  alias Portfolio.Config.CacheConfig
  alias Portfolio.Photography.Services.PhotoService

  @doc """
  Récupère les statistiques de traitement des photos avec cache.

  Les statistiques sont mises en cache pendant 5 minutes car elles
  changent fréquemment lors du traitement.

  ## Options

  - `:skip_cache` - Ignorer le cache (défaut: false)

  ## Exemples

      iex> get_processing_stats()
      %{pending: 5, completed: 100, failed: 2, total: 107}
  """
  @spec get_processing_stats(keyword()) :: %{
          pending: non_neg_integer(),
          completed: non_neg_integer(),
          failed: non_neg_integer(),
          total: non_neg_integer()
        }
  def get_processing_stats(opts \\ []) do
    if Keyword.get(opts, :skip_cache, false) do
      PhotoService.get_processing_stats()
    else
      fetch_stats_from_cache_or_db()
    end
  end

  @doc """
  Invalide le cache des statistiques de traitement.

  Doit être appelée après toute opération affectant les statistiques :
  - Traitement d'une photo (succès ou échec)
  - Suppression d'une photo

  ## Exemples

      iex> invalidate_stats_cache()
      :ok
  """
  @spec invalidate_stats_cache() :: :ok
  def invalidate_stats_cache do
    _ = Cachex.del(:portfolio_cache, CacheConfig.processing_stats_key())
    :ok
  end

  # =============================================================================
  # Private Functions
  # =============================================================================

  # En test, toujours skip le cache pour éviter la pollution entre tests
  if Mix.env() == :test do
    defp fetch_stats_from_cache_or_db do
      PhotoService.get_processing_stats()
    end
  else
    defp fetch_stats_from_cache_or_db do
      cache_key = CacheConfig.processing_stats_key()

      case Cachex.fetch(:portfolio_cache, cache_key, fn ->
             result = PhotoService.get_processing_stats()
             {:commit, result, ttl: CacheConfig.processing_stats_ttl()}
           end) do
        {:ok, stats} -> stats
        {:commit, stats} -> stats
        {:ignore, stats} -> stats
        {:error, _reason} -> PhotoService.get_processing_stats()
      end
    end
  end
end
