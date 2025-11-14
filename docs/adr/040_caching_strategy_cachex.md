# ADR-040: Stratégie de Cache avec Cachex

Statut: Accepté  
Date: 2025-11-11

## Contexte

Dans une application web de portfolio photography, certaines requêtes sont coûteuses et exécutées fréquemment, notamment la liste des albums publiés groupés par année. Ces requêtes impliquent des jointures SQL, des aggregations et du tri, ce qui peut impacter les performances sous charge.

### Problématique

Le serveur Hetzner VPS dispose de ressources limitées :
- 4 Go de RAM totale
- Partagée entre : Application Elixir, PostgreSQL, Service de conversion d'images
- Budget mémoire application : 1-2 Go maximum

**Voir aussi** : 
- ADR-042 (Telemetry) pour le monitoring de la consommation mémoire du cache
- ADR-030 (Domain Events) pour l'invalidation du cache via événements

Les requêtes fréquentes identifiées :
- Liste des albums publiés par année (page d'accueil, timeline)
- Détails d'un album spécifique (galerie)
- Statistiques globales (dashboard admin)

Sans système de cache :
- Chaque visite de la page d'accueil exécute une requête SQL complexe
- Pics de charge lors de partages sur réseaux sociaux
- Latence perceptible (200-500ms par requête complexe)
- Charge DB inutile pour du contenu qui change rarement

### Contraintes

- Mémoire limitée : Budget application 1-2 Go
- Contenu photo change rarement (quelques publications/mois)
- Invalidation précise nécessaire lors de publication/dépublication
- Solution simple sans infrastructure externe (pas de Redis)
- Support du mode test (cache désactivé pour isolation des tests)

## Options considérées

### Option 1: Pas de Cache (Status Quo Hypothétique)

Description:

Exécuter toutes les requêtes directement contre PostgreSQL sans couche de cache intermédiaire.

```elixir
def list_published_albums_by_year(opts \\ []) do
  # Toujours query DB
  AlbumRepository.list_published_by_year()
  |> Enum.group_by(&(&1.date_prise_vue.year))
end
```

Avantages :
- Simplicité maximale : Pas de gestion de cache
- Pas de consommation mémoire supplémentaire
- Données toujours fraîches (pas de stale data)
- Pas de complexité d'invalidation

Inconvénients :
- Requêtes SQL coûteuses répétées inutilement
- Latence perceptible (200-500ms) sur chaque visite
- Charge DB élevée pour contenu statique
- Pics de charge lors de partages viraux
- Mauvaise expérience utilisateur (pages lentes)

Effort estimé : Aucun (status quo)

Risques :
- Performance dégradée sous charge [Probabilité: Élevée, Impact: Élevé]
- Coûts serveur supérieurs (upgrade nécessaire) [Probabilité: Moyenne, Impact: Moyen]

### Option 2: ETS Direct (Cache Elixir Natif)

Description:

Utiliser ETS (Erlang Term Storage) directement pour stocker les résultats de requêtes. ETS est un système de tables mémoire natif Erlang/Elixir.

```elixir
def list_published_albums_by_year(opts \\ []) do
  case :ets.lookup(:albums_cache, :published_by_year) do
    [{:published_by_year, albums, timestamp}] ->
      if fresh?(timestamp), do: albums, else: fetch_and_cache()
    [] ->
      fetch_and_cache()
  end
end

defp fetch_and_cache do
  albums = AlbumRepository.list_published_by_year()
  :ets.insert(:albums_cache, {:published_by_year, albums, DateTime.utc_now()})
  albums
end
```

Avantages :
- Pas de dépendance externe (ETS natif)
- Performance maximale (accès mémoire in-process)
- Pas de coût réseau
- Très faible overhead

Inconvénients :
- API bas niveau et verbeuse
- Pas de gestion automatique de TTL
- Pas de limite de taille (risque memory leak)
- Pas de statistiques (hits, misses) out-of-the-box
- Code boilerplate à écrire (TTL, éviction, invalidation)
- Difficulté de debug (inspection manuelle)

Effort estimé : Moyen (infrastructure custom à écrire)

Risques :
- Memory leak si mauvaise gestion [Probabilité: Moyenne, Impact: Élevé]
- Complexité maintenance [Probabilité: Élevée, Impact: Moyen]

### Option 3: Redis Externe

Description:

Déployer un serveur Redis séparé pour gérer le cache de l'application. Redis offre un cache distribué avec persistence, TTL automatique et monitoring.

```elixir
def list_published_albums_by_year(opts \\ []) do
  case Redix.command(:redix, ["GET", "albums:published_by_year"]) do
    {:ok, nil} ->
      fetch_and_cache_redis()
    {:ok, cached} ->
      :erlang.binary_to_term(cached)
  end
end
```

Avantages :
- Cache distribué (plusieurs instances app)
- Persistence optionnelle (survit aux redémarrages)
- Monitoring riche (Redis CLI, RedisInsight)
- TTL automatique
- Statistiques détaillées

Inconvénients :
- Infrastructure supplémentaire à gérer
- Consommation mémoire additionnelle (Redis = 30-50 Mo minimum)
- Coût serveur additionnel ou partage des 4 Go avec Redis
- Complexité opérationnelle (monitoring, backup, failover)
- Latence réseau (même si localhost)
- Over-engineering pour un seul serveur

Effort estimé : Élevé

Risques :
- Consommation mémoire excessive [Probabilité: Élevée, Impact: Élevé]
- Point de défaillance unique [Probabilité: Moyenne, Impact: Élevé]
- Over-engineering [Probabilité: Très élevée, Impact: Moyen]

### Option 4: Cachex (Cache Elixir avec Features)

Description:

Utiliser **Cachex**, une bibliothèque Elixir qui encapsule ETS avec des fonctionnalités avancées (TTL, limites, statistiques, hooks). Cachex offre une API simple tout en restant in-process.

Architecture :

```
Request
   ↓
Photography Context
   ↓
Cachex.get(key)
   ↓
Hit? → Return cached ← Miss? → Query DB → Cache → Return
                                   ↓
                            AlbumRepository
                                   ↓
                              PostgreSQL
```

Implémentation :

```elixir
# Application.ex - Configuration
{Cachex, name: :portfolio_cache, limit: 1000}

# Photography.ex - Utilisation
defp list_published_albums_by_year_impl(opts) do
  preloads = Keyword.get(opts, :preload, [])
  cache_key = cache_key(:published_albums_by_year, preloads)
  
  case Cachex.fetch(:portfolio_cache, cache_key, fn ->
    albums = AlbumRepository.list_published_by_year(preloads)
    {:commit, albums, ttl: :timer.hours(1)}
  end) do
    {:ok, albums} -> {:ok, albums}
    {:commit, albums} -> {:ok, albums}
    {:error, reason} -> {:error, reason}
  end
end

# Invalidation
defp invalidate_albums_cache do
  Cachex.del(:portfolio_cache, cache_key(:published_albums_by_year, []))
  Cachex.del(:portfolio_cache, cache_key(:published_albums_by_year, [:photos]))
  :ok
end
```

Avantages :
- API simple et idiomatique Elixir
- TTL automatique (pas de gestion manuelle)
- Limite de taille configurée (protection memory leak)
- Statistiques intégrées (hits, misses, evictions)
- Hooks pour observabilité
- Support transactions (get + set atomique)
- In-process (pas de latence réseau)
- Bien documenté et maintenu
- Mode test facile (skip_cache option)

Inconvénients :
- Dépendance externe (mais Elixir pure)
- Légèrement plus lourd qu'ETS direct
- Cache non distribué (limité à un nœud)

Effort estimé : Faible

Risques :
- Pas de risque majeur identifié [Probabilité: Faible, Impact: Faible]

## Décision

L'option choisie est: Option 4 - Cachex

### Justification de la décision

Cachex offre le meilleur compromis entre simplicité, fonctionnalités et contraintes de ressources pour un serveur mono-instance. Cette solution :

1. Respecte le budget mémoire : Limite de 1000 entrées configurable, consommation estimée < 100 Mo
2. API simple : Moins de code boilerplate qu'ETS direct
3. Pas d'infrastructure externe : Évite Redis et sa consommation mémoire
4. TTL automatique : Pas de gestion manuelle d'expiration
5. Observabilité : Statistiques intégrées pour monitoring
6. Testabilité : Mode test avec cache désactivé

Le principal compromis accepté est l'absence de distribution (cache mono-nœud), mais ce n'est pas un problème pour l'architecture actuelle mono-serveur.

## Conséquences

### Positives

- Réduction latence : 200-500ms → 1-5ms pour requêtes cachées (98% plus rapide)
- Charge DB réduite : 90% des requêtes albums servies depuis cache
- Budget mémoire respecté : ~50-100 Mo utilisés sur 1-2 Go disponibles
- Expérience utilisateur améliorée : Pages instantanées
- Simplicité opérationnelle : Pas de service externe à gérer
- Observabilité : Statistiques cache accessibles (hits, misses)

### Négatives

- Stale data possible : Jusqu'à 1h si invalidation échoue (acceptable pour contenu photo)
- Consommation mémoire : 50-100 Mo supplémentaires
- Cache perdu au redémarrage : Warmup nécessaire après déploiement

### Neutres

- Cache mono-nœud : Adapté à l'architecture actuelle mono-serveur
- TTL fixe 1h : Peut nécessiter ajustement selon usage réel

## Stratégie de Cache Détaillée

### Données Cachées

Clé de cache | TTL | Taille estimée | Invalidation
---|---|---|---
`{:published_albums_by_year, []}` | 1h | ~10 Ko | Album publish/unpublish
`{:published_albums_by_year, [:photos]}` | 1h | ~500 Ko | Album publish/unpublish
`{:session, session_token}` | Session lifetime | ~1 Ko | Logout, expiration

Estimation mémoire totale :
- Albums cachés : ~510 Ko
- Sessions (max 100 concurrentes) : ~100 Ko
- Overhead Cachex : ~10 Mo
- Total : ~50-100 Mo

### Configuration Cachex

```elixir
# config/config.exs
config :portfolio, :cache,
  name: :portfolio_cache,
  limit: 1000,           # Max 1000 entrées (protection memory leak)
  stats: true            # Statistiques pour monitoring
```

Justification limite 1000 :
- Albums publiés : ~50 entrées max (avec/sans preload)
- Sessions : ~100 utilisateurs concurrents max
- Requêtes diverses : ~850 entrées restantes
- Marge confortable sans risque de saturation

### Politique de TTL

Type de donnée | TTL | Justification
---|---|---
Albums publiés | 1 heure | Contenu change rarement (quelques publications/mois)
Sessions | Variable (1-7j) | Durée de vie session configurée
Stats temporaires | 5 minutes | Données volatiles, rafraîchissement fréquent

TTL de 1h pour albums :
- Compromis entre fraîcheur et performance
- Contenu photo change typiquement < 1 fois/semaine
- Invalidation manuelle en cas de publication immédiate
- Réduction possible à 30 min si nécessaire

### Stratégie d'Invalidation

Invalidation ciblée (recommandée) :

```elixir
defp invalidate_albums_cache do
  Cachex.del(:portfolio_cache, {:published_albums_by_year, []})
  Cachex.del(:portfolio_cache, {:published_albums_by_year, [:photos]})
  :ok
end
```

Déclencheurs d'invalidation :
1. Publication d'un album (`publish_album/2`)
2. Dépublication d'un album (`unpublish_album/2`)
3. Modification d'un album publié (`update_album/2`)
4. Suppression d'un album (`delete_album/1`)

Événements domaine :
- `AlbumPublished` → Invalide cache albums
- `AlbumUnpublished` → Invalide cache albums
- `AlbumDeleted` → Invalide cache albums

### Mode Test

En environnement test, le cache est désactivé via l'option `:skip_cache` pour éviter la pollution entre tests :

```elixir
def list_published_albums_by_year(opts \\ []) do
  if Keyword.get(opts, :skip_cache, Mix.env() == :test) do
    # Bypass cache en test
    list_published_albums_by_year_impl(opts)
  else
    # Utilise cache en dev/prod
    fetch_from_cache(opts)
  end
end
```

## Dette Technique Identifiée

### Bug : Cache Name Incohérent

Fichier : `lib/portfolio/photography/event_handlers/album_published_handler.ex:124`

Problème actuel :
```elixir
# AlbumPublishedHandler.ex - ERREUR
defp clear_albums_cache do
  case Cachex.clear(:albums_cache) do  # Cache inexistant !
    {:ok, _} -> :ok
    {:error, reason} -> {:error, reason}
  end
end
```

Le cache est nommé `:portfolio_cache` dans `Application.ex` mais le handler utilise `:albums_cache` qui n'existe pas. Cette fonction échoue silencieusement sans invalider le cache.

Correction recommandée :
```elixir
defp clear_albums_cache do
  # Option A : Invalidation ciblée (recommandée)
  Cachex.del(:portfolio_cache, {:published_albums_by_year, []})
  Cachex.del(:portfolio_cache, {:published_albums_by_year, [:photos]})
  :ok
  
  # Option B : Invalidation globale (si nécessaire)
  # Cachex.clear(:portfolio_cache)
end
```

Recommandation : Utiliser l'invalidation ciblée (Option A) car :
- Plus performant : Ne supprime que les clés affectées
- Préserve autres caches : Sessions, stats futures
- Cohérent avec le code existant dans `AlbumPublicationService.ex:91-93`

## Monitoring et Observabilité

### Métriques à Surveiller

Métrique | Seuil Alerte | Action
---|---|---
Cache hit rate | < 70% | Revoir stratégie TTL ou clés cachées
Mémoire utilisée | > 150 Mo | Réduire limite ou ajuster TTL
Evictions/minute | > 10 | Limite trop basse, augmenter
Invalidations/jour | > 100 | Vérifier logique invalidation

### Accès aux Statistiques

```elixir
# Dashboard admin ou iex
{:ok, stats} = Cachex.stats(:portfolio_cache)

%{
  hit_rate: 0.89,        # 89% de hits
  hits: 1245,
  misses: 155,
  evictions: 23,
  expirations: 45,
  operations: 1400
}
```

### Logging

Les invalidations de cache sont loggées avec contexte :

```elixir
Logger.debug("Cache invalidated",
  keys: [:published_albums_by_year],
  reason: :album_published
)
```

## Plan d'action

### Phase 1: Correction Bug Cache Name (Priorité: CRITIQUE)

Tâches :
1. Corriger `AlbumPublishedHandler.clear_albums_cache/0`
2. Remplacer `:albums_cache` par `:portfolio_cache`
3. Utiliser invalidation ciblée (del keys spécifiques)
4. Tester l'invalidation après publication album
5. Vérifier logs pour confirmer invalidation

Critères de succès :
- Cache correctement invalidé après publication
- Logs montrent "Albums cache cleared"
- Tests passent avec cache invalidé

Estimation : 0.5 jour

### Phase 2: Monitoring Cache (Priorité: HAUTE)

Tâches :
1. Ajouter dashboard admin avec statistiques Cachex
2. Afficher : hit rate, hits, misses, memory usage
3. Configurer alertes si hit rate < 70%
4. Documenter comment accéder aux stats en production

Critères de succès :
- Dashboard admin affiche stats cache
- Alertes configurées pour métriques critiques

Estimation : 1 jour

### Phase 3: Optimisation TTL (Priorité: MOYENNE)

Tâches :
1. Collecter métriques hit rate sur 1 mois
2. Analyser fréquence de publication albums
3. Ajuster TTL si nécessaire (30 min vs 1h vs 2h)
4. A/B test différentes valeurs TTL

Critères de succès :
- Hit rate > 85%
- TTL optimal identifié

Estimation : 1 semaine (collecte données)

### Phase 4: Cache Additionnel (Priorité: BASSE)

Identifier autres requêtes candidates au cache :
- Stats dashboard admin (count albums, photos)
- Détails album individuel (si trafic élevé)
- User sessions (déjà partiellement implémenté)

Tâches :
1. Profiler requêtes lentes (> 100ms)
2. Identifier candidates (fréquence > 10/min, données stables)
3. Implémenter cache si justifié
4. Mesurer impact performance

Critères de succès :
- Latence P95 < 100ms sur toutes les pages
- Charge DB réduite de 90%+

Estimation : 2 jours

## Alternatives Futures

### Si Scale Horizontal Nécessaire

Si le projet évolue vers plusieurs instances (load balancing) :

Option : Migrer vers Redis
- Cache distribué entre instances
- Invalidation synchronisée
- Coût mémoire : +50-100 Mo

Déclencheur : Trafic > 10k visiteurs/jour nécessitant scale horizontal

### Si Mémoire Insuffisante

Si consommation mémoire Cachex dépasse 150 Mo :

Actions possibles :
1. Réduire limite : 1000 → 500 entrées
2. Réduire TTL : 1h → 30 min
3. Cache sélectif : Uniquement page d'accueil
4. Upgrade serveur : 4 Go → 8 Go RAM

## Références

- Cachex Documentation : https://hexdocs.pm/cachex/
- Cachex GitHub : https://github.com/whitfin/cachex
- ETS Documentation : https://www.erlang.org/doc/man/ets.html
- Code source :
  - `lib/portfolio/application.ex:26` : Configuration Cachex
  - `lib/portfolio/photography.ex:771-774` : Invalidation cache
  - `lib/portfolio/photography/event_handlers/album_published_handler.ex:124` : Bug cache name

## Notes

### Pourquoi Pas ConCache ?

ConCache est une alternative à Cachex avec des fonctionnalités similaires. Non retenu car :
- Communauté plus petite (moins de maintenance)
- Documentation moins complète
- Cachex plus idiomatique Elixir
- Cachex mieux intégré avec écosystème Phoenix

### Warmup Cache au Démarrage ?

Le cache se remplit naturellement au premier accès (lazy loading). Un warmup proactif au démarrage n'est pas nécessaire car :
- Première requête post-déploiement = 200-500ms (acceptable)
- Warmup complexifie le démarrage
- Risque de timeout si DB lente au démarrage

Si nécessaire à l'avenir, implémenter via Task dans Application.start/2.

### Cache et Cohérence Éventuelle

L'invalidation de cache via événements domaine introduit une cohérence éventuelle (eventual consistency) :
- Publication album → Événement → Handler → Invalidation (quelques ms)
- Pendant ces millisecondes, le cache peut servir des données obsolètes

Impact : Négligeable car :
- Latence invalidation < 50ms
- Contenu photo non critique (pas de transactions financières)
- TTL 1h garantit fraîcheur maximale

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
