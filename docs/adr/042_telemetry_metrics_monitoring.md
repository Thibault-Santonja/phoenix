# ADR-042: Telemetry, Métriques et Monitoring

Statut: Accepté  
Date: 2025-11-11

## Contexte

Dans une application web en production, l'observabilité est essentielle pour comprendre le comportement du système, diagnostiquer les problèmes et optimiser les performances. Sans monitoring, il est difficile de répondre à des questions critiques comme "Pourquoi l'application est-elle lente ?", "Combien de mémoire utilise-t-on ?", ou "Y a-t-il des erreurs silencieuses ?".

### Problématique

Le portfolio Photography nécessite une observabilité complète sur plusieurs dimensions :

Métriques techniques (priorité haute) :
- Consommation mémoire (budget 1-2 Go sur 4 Go disponibles) - voir ADR-043
- CPU usage (éviter throttling lors de génération d'images) - voir ADR-011
- Connexions DB PostgreSQL (limite pool Ecto)
- Cache hit rate Cachex (objectif > 70%) - voir ADR-040

**Voir aussi** :
- ADR-040 (Caching Strategy) pour les métriques de cache
- ADR-041 (Oban) pour les métriques des jobs asynchrones
- ADR-043 (Deployment) pour les contraintes infrastructure
- ADR-050 (Security) pour les métriques de sécurité

Métriques performance (priorité haute) :
- Durée requêtes HTTP (objectif P95 < 200ms)
- Durée traitement images (tracking progression)
- Durée uploads photos (identifier bottlenecks)

Métriques business (priorité moyenne) :
- Photos uploadées par jour
- Albums publiés par semaine
- Magic links envoyés vs vérifiés

Sans système d'observabilité :
- Impossible de diagnostiquer slowdowns en production
- Pas de visibilité sur consommation ressources
- Difficile d'optimiser performance sans données
- Débug réactif au lieu de proactif

### Contraintes

- Coût zéro ou minimal : Budget limité
- Simplicité : Pas d'infrastructure externe complexe (pas de Grafana, Prometheus)
- Elixir natif : Utiliser l'écosystème Elixir/Phoenix existant
- Logs structurés : Format JSON pour parsing futur
- Dashboard admin : Accessible sans service externe
- Extensibilité : Prévoir intégration future logging externe (Logflare, Papertrail)

## Options considérées

### Option 1: Logger Seul (Status Quo Partiel)

Description:

Utiliser uniquement le Logger Elixir pour capturer les événements et métriques sans framework de métriques dédié.

```elixir
Logger.info("Photo uploaded",
  photo_id: photo.id,
  duration_ms: duration,
  file_size_kb: size
)
```

Avantages :
- Pas de dépendance externe
- Très simple à utiliser
- Logs structurés disponibles
- Gratuit

Inconvénients :
- Pas de métriques agrégées (compteurs, distributions)
- Difficile d'extraire tendances (ex: durée moyenne uploads)
- Pas de dashboard visuel
- Grepping logs manuel fastidieux
- Pas de métriques VM automatiques (mémoire, CPU)

Effort estimé : Aucun (déjà utilisé)

Risques :
- Observabilité limitée [Probabilité: Élevée, Impact: Moyen]
- Difficile de diagnostiquer problèmes [Probabilité: Moyenne, Impact: Élevé]

### Option 2: APM Externe (New Relic, AppSignal, Scout)

Description:

Utiliser un service APM (Application Performance Monitoring) externe pour monitoring complet avec alerting, dashboards et tracing distribué.

Services disponibles :
- New Relic : $99/mois
- AppSignal : $49/mois
- Scout APM : $79/mois

Avantages :
- Dashboard riche out-of-the-box
- Alerting automatique
- Tracing distribué (queries DB, requêtes externes)
- Métriques VM complètes
- Support professionnel

Inconvénients :
- Coût mensuel élevé ($49-99/mois = $600-1200/an)
- Over-engineering pour petit projet solo
- Dépendance service externe
- Configuration complexe

Effort estimé : Moyen

Risques :
- Coût prohibitif pour budget limité [Probabilité: Très élevée, Impact: Critique]
- Over-engineering [Probabilité: Élevée, Impact: Moyen]

### Option 3: Prometheus + Grafana

Description:

Déployer Prometheus pour collecte métriques et Grafana pour visualisation. Stack monitoring standard pour applications cloud-native.

```elixir
# Exporter métriques Prometheus
defmodule MetricsExporter do
  use PromEx
end

# Grafana dashboard
# Nécessite déploiement Prometheus + Grafana
```

Avantages :
- Puissant et flexible
- Standard industrie
- Open-source (gratuit)
- Dashboards Grafana très riches

Inconvénients :
- Infrastructure additionnelle lourde (Prometheus + Grafana)
- Consommation mémoire : 200-300 Mo minimum
- Over-engineering pour mono-serveur
- Configuration complexe
- Maintenance overhead élevé

Effort estimé : Élevé (3-5 jours setup)

Risques :
- Consommation mémoire excessive [Probabilité: Élevée, Impact: Élevé]
- Over-engineering [Probabilité: Très élevée, Impact: Moyen]

### Option 4: Telemetry + LiveDashboard + Structured Logging

Description:

Utiliser Telemetry (natif Elixir) pour émettre métriques, LiveDashboard Phoenix (gratuit) pour visualisation en temps réel, et logs structurés JSON pour historique. Plan futur : Exporter logs vers Logflare/Papertrail si nécessaire.

Architecture :

```
Application Code
   ↓
:telemetry.execute(event, measurements, metadata)
   ↓
   ├─> Telemetry Handlers (Logging structuré)
   ├─> Telemetry.Metrics (Agrégations)
   └─> LiveDashboard (Visualisation temps réel)

Future :
Structured Logs → Logflare/Papertrail (agrégation externe)
```

Implémentation :

```elixir
# 1. Émettre événement Telemetry
:telemetry.execute(
  [:portfolio, :photography, :photo, :uploaded],
  %{duration: duration_ms, size: file_size},
  %{album_id: album.id, user_id: user.id}
)

# 2. Handler Telemetry pour logging structuré
def handle_photo_uploaded(_event, %{duration: duration}, metadata, _config) do
  Logger.info("Photo uploaded",
    album_id: metadata.album_id,
    user_id: metadata.user_id,
    duration_ms: duration,
    file_size_mb: metadata.size / 1_000_000
  )
end

# 3. Métriques Telemetry
def metrics do
  [
    counter("portfolio.photography.photo.uploaded.count"),
    distribution("portfolio.photography.photo.uploaded.duration",
      unit: {:native, :millisecond}
    ),
    last_value("vm.memory.total", unit: {:byte, :megabyte})
  ]
end

# 4. LiveDashboard Phoenix
# Accessible à /admin/dashboard avec auth admin
# Affiche métriques temps réel + processus + Oban
```

Avantages :
- Coût zéro : Tout inclus dans Phoenix
- Pas d'infrastructure externe
- LiveDashboard gratuit et puissant
- Telemetry natif Elixir (idiomatique)
- Logs structurés JSON pour export futur
- Extensible : Peut ajouter Logflare/Papertrail plus tard
- Métriques VM automatiques (mémoire, CPU, schedulers)
- Intégration Oban native

Inconvénients :
- Dashboard temps réel uniquement (pas d'historique long terme)
- Pas d'alerting automatique (peut être ajouté via Newsletter)
- Nécessite accès admin pour voir dashboard

Effort estimé : Faible (déjà partiellement implémenté)

Risques :
- Pas de risque majeur identifié [Probabilité: Faible, Impact: Faible]

## Décision

L'option choisie est: Option 4 - Telemetry + LiveDashboard + Structured Logging

### Justification de la décision

Cette solution offre le meilleur compromis entre observabilité, simplicité et coût pour un projet solo avec budget limité. Cette approche :

1. Coût zéro : Tout inclus dans Phoenix/Elixir
2. Puissante : LiveDashboard très complet pour debug
3. Extensible : Logs structurés préparés pour export futur
4. Idiomatique : Telemetry est le standard Elixir
5. Simple : Pas d'infrastructure externe à gérer

Le principal compromis accepté est l'absence d'historique long terme et d'alerting automatique, mais ces fonctionnalités peuvent être ajoutées progressivement selon les besoins.

## Conséquences

### Positives

- Observabilité immédiate : Dashboard temps réel accessible à /admin/dashboard
- Coût zéro : Pas d'abonnement mensuel
- Métriques VM : Mémoire, CPU, schedulers Erlang visibles
- Debug facilité : Processus Erlang, Oban jobs, connexions DB
- Logs structurés : Format JSON prêt pour export futur
- Extensibilité : Migration vers Logflare/Papertrail triviale si nécessaire

### Négatives

- Pas d'historique long terme : Dashboard temps réel uniquement
- Pas d'alerting automatique : Nécessite check manuel ou Newsletter
- Dashboard nécessite authentification admin

### Neutres

- Logging externe futur : Prévu mais pas urgent (Logflare ~$10-20/mois si nécessaire)

## Stratégie Telemetry Détaillée

### Événements Telemetry Émis

Catégorie | Événement | Measurements | Metadata
---|---|---|---
Photography | `[:portfolio, :photography, :photo, :uploaded]` | `duration`, `size` | `album_id`, `user_id`
Photography | `[:portfolio, :photography, :album, :created]` | `duration` | `type`, `user_id`
Photography | `[:portfolio, :photography, :album, :published]` | `duration` | `album_id`, `slug`
Auth | `[:portfolio, :auth, :magic_link, :requested]` | `duration` | `email`
Auth | `[:portfolio, :auth, :magic_link, :verified]` | `duration` | `user_id`, `email`
Image | `[:portfolio, :image, :processing, :start]` | `system_time` | `photo_id`
Image | `[:portfolio, :image, :processing, :stop]` | `duration` | `photo_id`, `variant_count`
Image | `[:portfolio, :image, :processing, :exception]` | - | `photo_id`, `reason`

### Métriques Telemetry Configurées

Type | Métrique | Description | Priorité
---|---|---|---
Counter | `portfolio.photography.photo.uploaded.count` | Nombre total photos uploadées | Business
Distribution | `portfolio.photography.photo.uploaded.duration` | Durée upload photos (ms) | Performance
Counter | `portfolio.photography.album.created.count` | Nombre albums créés | Business
Distribution | `portfolio.photography.album.created.duration` | Durée création album (ms) | Performance
Counter | `portfolio.auth.magic_link.requested.count` | Magic links envoyés | Business
Distribution | `portfolio.auth.magic_link.requested.duration` | Durée envoi magic link (ms) | Performance
Last Value | `vm.memory.total` | Mémoire totale VM (Mo) | Technique
Last Value | `vm.total_run_queue_lengths.total` | Run queue schedulers | Technique
Summary | `phoenix.endpoint.stop.duration` | Durée requêtes HTTP (ms) | Performance
Summary | `phoenix.router_dispatch.stop.duration` | Durée dispatch routes (ms) | Performance

### Handlers Telemetry

Chaque événement Telemetry est capturé par un handler qui log de manière structurée :

```elixir
defp attach_handlers do
  :telemetry.attach(
    "portfolio-photography-photo-uploaded",
    [:portfolio, :photography, :photo, :uploaded],
    &__MODULE__.handle_photo_uploaded/4,
    nil
  )
end

def handle_photo_uploaded(_event, %{duration: duration, size: size}, metadata, _config) do
  Logger.info("Photo uploaded",
    album_id: metadata.album_id,
    user_id: metadata.user_id,
    duration_ms: System.convert_time_unit(duration, :native, :millisecond),
    file_size_mb: Float.round(size / 1_000_000, 2)
  )
end
```

Format de log structuré (JSON en production) :

```json
{
  "level": "info",
  "message": "Photo uploaded",
  "timestamp": "2025-11-11T14:23:45.123Z",
  "metadata": {
    "album_id": "a3f2b8c4-...",
    "user_id": "7d8e9f1a-...",
    "duration_ms": 234,
    "file_size_mb": 3.45
  }
}
```

## LiveDashboard Phoenix

### Accès Dashboard

URL : `/admin/dashboard`  
Authentification : Admin uniquement (via plug `:require_admin`)

Configuration :

```elixir
# lib/portfolio_web/router.ex
scope "/admin" do
  pipe_through [:browser, :require_authenticated_user, :require_admin]
  
  live_dashboard "/dashboard",
    metrics: PortfolioWeb.Telemetry,
    ecto_repos: [Portfolio.Repo],
    additional_pages: [
      oban: Oban.Web.Dashboard  # Optionnel si Oban Web installé
    ]
end
```

### Fonctionnalités LiveDashboard

Onglet | Fonctionnalité | Utilité
---|---|---
Home | Vue d'ensemble métriques | Snapshot rapide
Metrics | Graphiques métriques temps réel | Monitoring performance
OS Data | CPU, mémoire, disk, network | Monitoring ressources système
Processes | Processus Erlang actifs | Debug leaks mémoire
Applications | Apps OTP actives | Vérifier supervision tree
ETS | Tables ETS (Cachex, Hammer) | Debug cache
Sockets | Connexions Phoenix actives | Monitoring LiveView
Request Logger | Requêtes HTTP temps réel | Debug lenteurs

### Métriques Visibles

LiveDashboard affiche automatiquement :

Catégorie technique (priorité haute) :
- Mémoire VM totale (objectif < 1.5 Go)
- Processus actifs
- Run queue lengths (CPU saturation)
- Réductions (work done par scheduler)

Catégorie performance (priorité haute) :
- Durée requêtes HTTP P50/P95/P99
- Durée dispatch routes
- Latence DB queries
- Cache hit rate Cachex (via ETS tab)

Catégorie business (priorité moyenne) :
- Photos uploadées (counter)
- Albums créés (counter)
- Magic links envoyés (counter)

## Structured Logging

### Configuration Logger

```elixir
# config/prod.exs
config :logger,
  level: :info,
  backends: [:console],
  compile_time_purge_matching: [
    [level_lower_than: :info]
  ]

config :logger, :console,
  format: {Jason, :encode!},  # JSON format
  metadata: [
    :request_id,
    :user_id,
    :album_id,
    :photo_id,
    :duration_ms
  ]
```

### Format de Logs

Développement (human-readable) :

```
[info] Photo uploaded album_id=a3f2b8c4 user_id=7d8e9f1a duration_ms=234 file_size_mb=3.45
```

Production (JSON) :

```json
{
  "level": "info",
  "message": "Photo uploaded",
  "timestamp": "2025-11-11T14:23:45.123Z",
  "request_id": "FxaU3wEBO_IAAACB",
  "album_id": "a3f2b8c4-1234-5678-90ab-cdef12345678",
  "user_id": "7d8e9f1a-abcd-ef01-2345-6789abcdef01",
  "duration_ms": 234,
  "file_size_mb": 3.45
}
```

Avantages JSON en production :
- Parsing automatique par Logflare/Papertrail
- Recherche par champ (ex: `user_id:"7d8e9f1a"`)
- Agrégations (durée moyenne par user)
- Visualisations graphiques

## Plan d'action

### Phase 1: Amélioration Dashboard Admin (Priorité: HAUTE)

Tâches :
1. Ajouter section "Métriques Techniques" dans dashboard admin
   - Mémoire VM actuelle vs budget (1-2 Go)
   - Cache Cachex : hit rate, size, evictions
   - Oban : jobs pending, completed, failed
   - DB : connexions actives, pool size
2. Ajouter section "Performance"
   - P95 requêtes HTTP
   - P95 uploads photos
   - P95 traitement images
3. Ajouter section "Business" (optionnel, priorité basse)
   - Photos uploadées aujourd'hui/semaine/mois
   - Albums publiés semaine/mois
   - Users actifs

Critères de succès :
- Dashboard admin affiche métriques clés
- Refresh automatique toutes les 10 secondes
- Accessible à `/admin/dashboard`

Estimation : 2 jours

### Phase 2: Alerting via Newsletter (Priorité: MOYENNE)

Contexte :

Pas besoin d'alerting temps réel critique actuellement. Newsletter hebdomadaire suffit pour monitoring santé système.

Tâches :
1. Créer `SystemHealthReportWorker` (Oban, cron hebdomadaire)
2. Générer rapport santé système :
   - Mémoire moyenne semaine
   - P95 latence requêtes
   - Cache hit rate
   - Jobs Oban échoués
   - Erreurs serveur 5xx
3. Envoyer email admin chaque lundi 9h
4. Format HTML lisible avec graphiques ASCII simples

Critères de succès :
- Email hebdomadaire envoyé automatiquement
- Rapport contient métriques clés
- Admin peut agir si anomalie détectée

Estimation : 2 jours

### Phase 3: Logging Externe (Priorité: BASSE - Futur)

Contexte :

Actuellement, logs locaux sur serveur suffisent. Logging externe (Logflare, Papertrail) prévu si :
- Besoin d'historique > 7 jours
- Besoin de recherche avancée dans logs
- Besoin de graphiques long terme

Services possibles (coût faible) :

Service | Coût | Fonctionnalités
---|---|---
Logflare | $0-10/mois (100k events) | Dashboard, search, graphiques
Papertrail | $0-7/mois (50 Mo/mois) | Search, alerting basique
Logtail | $0-10/mois | Visualisation, search

Tâches :
1. Choisir service selon budget (recommandation : Logflare)
2. Configurer export logs JSON vers service
3. Créer dashboard basique (latence, erreurs)
4. Configurer alerting si nécessaire

Déclencheur : Budget disponible (~$10/mois) OU besoin urgent d'historique long terme

Estimation : 1 jour setup

### Phase 4: Métriques Additionnelles (Priorité: BASSE)

Identifier métriques manquantes utiles :
- CDN : Invalidations réussies vs échouées
- Cache : Temps réponse Cachex (get latency)
- DB : Slow queries (> 1 seconde)
- Images : Taille moyenne variantes générées

Tâches :
1. Identifier métriques prioritaires
2. Ajouter émission Telemetry
3. Ajouter handlers logging
4. Intégrer dans dashboard admin

Critères de succès :
- Métriques utiles pour debug production

Estimation : 1 jour

## Alternatives Futures

### Si Budget Disponible : APM Payant

Si le projet génère des revenus ou obtient un budget (~$50-100/mois), envisager :

Option : AppSignal ($49/mois)
- Dashboard riche avec historique
- Alerting automatique (email, SMS, Slack)
- Tracing distribué (voir queries DB lentes)
- Profiling performance
- Support professionnel

Déclencheur : Budget disponible + besoin d'alerting temps réel

### Si Scale Horizontal : Distributed Tracing

Si le projet évolue vers plusieurs instances, implémenter distributed tracing :

Option : OpenTelemetry + Jaeger
- Tracer requêtes à travers instances
- Identifier bottlenecks distribués
- Visualiser dépendances entre services

Déclencheur : Architecture multi-instances (load balancing)

## Références

- [Telemetry Documentation](https://hexdocs.pm/telemetry/)
- [LiveDashboard Phoenix](https://hexdocs.pm/phoenix_live_dashboard/)
- [Telemetry.Metrics](https://hexdocs.pm/telemetry_metrics/)
- [Structured Logging avec Logger](https://hexdocs.pm/logger/)
- Code source :
  - `lib/portfolio_web/telemetry.ex` : Configuration Telemetry
  - `lib/portfolio/services/service.ex` : Macro `with_telemetry/3`
  - `lib/portfolio/workers/image_variant_worker.ex:48-56` : Émission Telemetry

## Notes

### Telemetry vs Logger : Quand Utiliser Quoi ?

Utiliser Telemetry pour :
- Métriques agrégées (compteurs, distributions)
- Événements applicatifs structurés
- Intégration avec métriques existantes

Utiliser Logger pour :
- Messages debug/info/warning/error
- Logs contextuels avec métadonnées
- Événements ponctuels non agrégés

Pattern recommandé : Telemetry + Handler qui log

```elixir
# 1. Émettre événement Telemetry (métriques)
:telemetry.execute([:app, :action, :done], %{duration: 123}, %{user: "alice"})

# 2. Handler capture et log (historique)
def handle_event(_event, %{duration: duration}, metadata, _config) do
  Logger.info("Action done", user: metadata.user, duration_ms: duration)
end
```

Avantages :
- Telemetry = métriques temps réel (dashboard)
- Logger = historique persistent (fichiers)
- Découplage : Métriques et logs séparés

### LiveDashboard vs Oban Web

LiveDashboard Phoenix (gratuit) | Oban Web ($99/dev/an)
---|---
Métriques générales | Focus Oban jobs
Processus Erlang | Interface riche Oban
ETS tables | Pause/cancel jobs
Basique mais suffisant | Avancé mais payant

Recommandation : LiveDashboard suffit pour démarrer. Oban Web uniquement si équipe > 3 devs.

### JSON Logging en Production

Activer JSON logging uniquement en production :

```elixir
# config/prod.exs
config :logger, :console,
  format: {Jason, :encode!},
  metadata: [:request_id, :user_id, :duration_ms]

# config/dev.exs (human-readable)
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]
```

Avantages JSON :
- Parsing automatique par services externes
- Recherche structurée (champs)
- Agrégations faciles

Inconvénients :
- Difficile à lire en console

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
