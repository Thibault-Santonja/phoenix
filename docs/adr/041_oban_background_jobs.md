# ADR-041: Jobs Asynchrones avec Oban

Statut: Accepté  
Date: 2025-11-11

## Contexte

Dans une application web, certaines opérations sont coûteuses et ne doivent pas bloquer la requête HTTP de l'utilisateur. Le traitement d'images, l'envoi d'emails, les notifications et les tâches de nettoyage sont des exemples typiques de traitements asynchrones.

### Problématique

Le portfolio Photography nécessite plusieurs traitements asynchrones :

Opérations identifiées :
1. Génération de variantes d'images (thumbnail, small, medium, large) - voir ADR-011
2. Extraction et stockage de métadonnées EXIF - voir ADR-011
3. Envoi d'emails (newsletter, notifications)
4. Nettoyage périodique (sessions expirées, jobs anciens)
5. Invalidation CDN (actuellement synchrone, à améliorer) - voir ADR-044

**Voir aussi** :
- ADR-011 (Image Processing) pour les détails du traitement d'images
- ADR-030 (Domain Events) pour l'intégration avec les événements domaine
- ADR-042 (Telemetry) pour le monitoring des jobs Oban
- ADR-044 (CDN Strategy) pour l'invalidation CDN asynchrone

Sans système de jobs asynchrones :
- Upload photo bloque jusqu'à génération de toutes les variantes (5-10 secondes)
- Envoi d'email bloque la réponse HTTP (risque de timeout)
- Échec de traitement = perte définitive du travail (pas de retry)
- Impossible de monitorer l'état des traitements en cours

### Contraintes

- Persistence nécessaire : Jobs doivent survivre aux redémarrages
- Retry automatique : Échecs temporaires doivent être réessayés
- Priorités : Certains jobs plus urgents que d'autres
- Monitoring : Visibilité sur jobs en cours, échoués, complétés
- Ressources limitées : 3 workers max pour traitement d'images (éviter surcharge CPU)
- Simplicité : Pas d'infrastructure externe (pas de Redis, RabbitMQ)

### Impact si aucune décision n'est prise

Sans système de jobs robuste :
- Expérience utilisateur dégradée (pages lentes, timeouts)
- Perte de travail en cas de crash serveur
- Impossibilité de retry automatique
- Code custom complexe pour gérer l'asynchronisme
- Difficile de monitorer et debugger les traitements

## Options considérées

### Option 1: Task.async / Task.Supervisor

Description:

Utiliser les primitives Elixir natives `Task.async/await` ou `Task.Supervisor` pour gérer l'asynchronisme.

```elixir
def upload_photo(album, upload) do
  {:ok, photo} = create_photo(album, upload)
  
  # Lance traitement en arrière-plan
  Task.Supervisor.start_child(MyApp.TaskSupervisor, fn ->
    generate_variants(photo.id)
  end)
  
  {:ok, photo}
end
```

Avantages :
- Pas de dépendance externe
- Très simple pour cas basiques
- Performance maximale (in-process)
- Pas de latence DB

Inconvénients :
- Pas de persistence : Jobs perdus au redémarrage
- Pas de retry automatique : Échec = échec définitif
- Pas de monitoring : Impossible de voir jobs en cours
- Pas de priorisation
- Pas de rate limiting
- Pas de scheduling (jobs périodiques)
- Supervision basique seulement

Effort estimé : Faible

Risques :
- Perte de travail en production [Probabilité: Élevée, Impact: Élevé]
- Impossible de debugger échecs [Probabilité: Élevée, Impact: Moyen]

### Option 2: GenServer Custom avec Persistence

Description:

Créer un système custom de jobs basé sur GenServer avec persistence PostgreSQL manuelle.

```elixir
defmodule JobQueue do
  use GenServer
  
  def init(_) do
    # Charger jobs depuis DB au démarrage
    jobs = Repo.all(Job)
    {:ok, %{jobs: jobs, workers: []}}
  end
  
  def handle_call({:enqueue, job}, _from, state) do
    # Persister en DB
    {:ok, job} = Repo.insert(job)
    # Lancer worker
    spawn_worker(job)
    {:reply, {:ok, job}, state}
  end
end
```

Avantages :
- Contrôle total sur l'implémentation
- Pas de dépendance externe
- Adapté aux besoins spécifiques

Inconvénients :
- Complexité élevée : Réinventer la roue
- Code custom à maintenir (retry, scheduling, monitoring)
- Risque de bugs (race conditions, deadlocks)
- Pas de dashboard out-of-the-box
- Temps de développement important
- Difficulté à gérer concurrence et priorités

Effort estimé : Très élevé (2-3 semaines)

Risques :
- Bugs complexes à débugger [Probabilité: Élevée, Impact: Élevé]
- Maintenance coûteuse [Probabilité: Très élevée, Impact: Moyen]
- Réinvention de fonctionnalités existantes [Probabilité: Très élevée, Impact: Moyen]

### Option 3: Exq (Redis-backed)

Description:

Utiliser Exq, une implémentation Elixir de Sidekiq avec Redis comme backend de persistence.

```elixir
defmodule ImageWorker do
  def perform(photo_id) do
    generate_variants(photo_id)
  end
end

# Enqueue
Exq.enqueue(Exq, "image_processing", ImageWorker, [photo_id])
```

Avantages :
- API simple inspirée de Sidekiq (Ruby)
- Monitoring via Redis
- Retry automatique
- Scheduling

Inconvénients :
- Dépendance Redis : Infrastructure externe nécessaire
- Consommation mémoire Redis : 30-50 Mo minimum
- Complexité opérationnelle : Redis à gérer
- Communauté plus petite qu'Oban
- Moins maintenu (dernière release 2021)
- Over-engineering pour serveur mono-instance

Effort estimé : Moyen

Risques :
- Infrastructure externe à gérer [Probabilité: Élevée, Impact: Élevé]
- Maintenance incertaine [Probabilité: Moyenne, Impact: Moyen]

### Option 4: Quantum (Cron-like Scheduler)

Description:

Utiliser Quantum uniquement pour scheduling de jobs périodiques (cron-like), pas pour jobs asynchrones généraux.

```elixir
config :my_app, MyApp.Scheduler,
  jobs: [
    {"0 2 * * *", {MyApp.Cleaner, :cleanup_old_sessions, []}}
  ]
```

Avantages :
- Très simple pour jobs périodiques
- API familière (cron syntax)
- Pas de DB requise

Inconvénients :
- Ne gère pas jobs asynchrones généraux
- Pas de persistence des jobs
- Pas de retry automatique
- Pas de monitoring
- Complémentaire, pas alternatif à système de jobs

Effort estimé : Faible

Note : Quantum est complémentaire à un système de jobs comme Oban, pas un remplacement.

### Option 5: Oban (PostgreSQL-backed)

Description:

Utiliser **Oban**, une bibliothèque Elixir de jobs asynchrones avec PostgreSQL comme backend de persistence. Oban offre retry, scheduling, monitoring et distributed locking natifs.

Architecture :

```
HTTP Request (Upload Photo)
   ↓
PhotoUploadService (Store Original)
   ↓
Oban.insert(ImageVariantWorker, %{photo_id: id})
   ↓
PostgreSQL (oban_jobs table)
   ↓
Oban Polling (Queue :image_processing)
   ↓
ImageVariantWorker.perform(%{photo_id: id})
   ↓
Generate Variants → Update Photo Record
```

Implémentation :

```elixir
# config/config.exs
config :portfolio, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    default: 10,              # 10 workers concurrents
    image_processing: 3,      # 3 workers (limite CPU)
    mailers: 5,              # 5 workers email
    cleanup: 1               # 1 worker nettoyage
  ],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},  # Nettoie jobs > 7 jours
    {Oban.Plugins.Cron, 
      crontab: [
        {"0 2 * * *", Portfolio.Workers.SessionCleanupWorker},
        {"0 3 * * SUN", Portfolio.Workers.DatabaseVacuumWorker}
      ]
    }
  ],
  repo: Portfolio.Repo

# Worker
defmodule Portfolio.Workers.ImageVariantWorker do
  use Oban.Worker,
    queue: :image_processing,
    max_attempts: 3,
    priority: 1
    
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}}) do
    case generate_variants(photo_id) do
      {:ok, variants} -> :ok
      {:error, :file_not_found} -> {:cancel, :file_not_found}  # Permanent
      {:error, reason} -> {:error, reason}  # Retry
    end
  end
end

# Enqueue
%{photo_id: photo.id}
|> ImageVariantWorker.new()
|> Oban.insert()
```

Avantages :
- Persistence PostgreSQL : Réutilise DB existante, pas d'infrastructure externe
- Retry automatique : Exponential backoff configurable
- Distributed locking : Évite jobs dupliqués en multi-instance
- Scheduling : Cron-like via plugin
- Monitoring : Dashboard Oban Web disponible
- Telemetry : Métriques intégrées
- Testing : Mode `testing: :manual` pour tests
- Communauté active : Bien maintenu, documentation excellente
- Elixir idiomatique : Pattern Elixir natif

Inconvénients :
- Dépendance externe (mais Elixir pure)
- Polling DB : Légère charge DB (configurable)
- Pas de broadcast instantané (polling 1 seconde par défaut)

Effort estimé : Faible

Risques :
- Pas de risque majeur identifié [Probabilité: Faible, Impact: Faible]

## Décision

L'option choisie est: Option 5 - Oban

### Justification de la décision

Oban offre le meilleur compromis entre robustesse, simplicité et pragmatisme pour le contexte mono-serveur. Cette solution :

1. Réutilise PostgreSQL : Pas d'infrastructure externe (pas de Redis)
2. Persistence native : Jobs survivent aux redémarrages
3. Retry intelligent : Exponential backoff pour erreurs transitoires
4. Monitoring accessible : LiveDashboard Phoenix gratuit (pas besoin Oban Web payant)
5. Communauté active : Bien maintenu, documentation excellente
6. Elixir idiomatique : S'intègre naturellement avec Phoenix

Le principal compromis accepté est le polling DB (légère charge), mais configurable et négligeable pour le volume de jobs actuel.

## Conséquences

### Positives

- Traitement asynchrone : Upload photo instantané (< 200ms) au lieu de 5-10 secondes
- Résilience : Jobs persistés, survit aux crashs et redémarrages
- Retry automatique : Échecs temporaires réessayés automatiquement
- Monitoring : Visibilité complète sur jobs (pending, running, completed, failed)
- Observabilité : Telemetry intégré pour métriques
- Scheduling : Cron-like pour tâches périodiques (nettoyage, backup)
- Testing simplifié : Mode manuel pour tests isolés

### Négatives

- Polling DB : Légère charge additionnelle (1 query/seconde/queue)
- Table `oban_jobs` : Croissance en base (mitigé par Pruner plugin)
- Latence asynchrone : Jobs non instantanés (1-2 secondes de délai)

### Neutres

- Dashboard Oban Web : Payant ($99/dev), alternative gratuite LiveDashboard existe
- Distributed locking : Utile uniquement si scale horizontal futur

## Configuration Détaillée

### Queues et Workers

Queue | Workers | Usage | Priorité
---|---|---|---
`default` | 10 | Jobs généraux non critiques | 0 (normale)
`image_processing` | 3 | Génération variantes images | 1 (normale)
`mailers` | 5 | Envoi emails, notifications | 0 (normale)
`cleanup` | 1 | Nettoyage périodique | 2 (basse)

Justification limite 3 workers `image_processing` :
- Génération d'images = CPU-intensive
- 3 workers = max charge CPU acceptable (évite throttling)
- Parallélisme suffisant pour uploads simultanés
- Peut être augmenté si upgrade serveur

### Workers Implémentés et Prévus

Worker | Queue | Status | Max Attempts | Description
---|---|---|---|---
`ImageVariantWorker` | `image_processing` | Implémenté | 3 | Génération variantes WebP
`NewsletterWorker` | `mailers` | À implémenter | 5 | Envoi newsletter périodique
`NotificationWorker` | `mailers` | À implémenter | 5 | Notifications utilisateurs
`SessionCleanupWorker` | `cleanup` | À implémenter | 3 | Nettoyage sessions expirées
`JobPrunerWorker` | `cleanup` | Plugin Oban | N/A | Nettoyage jobs anciens (automatique)

### Stratégie de Retry

Configuration par défaut Oban (exponential backoff) :

```
Attempt 1: Immédiatement
Attempt 2: 15 secondes
Attempt 3: 2 minutes
Attempt 4: 13 minutes
Attempt 5: 1 heure
```

Formule : `backoff = attempt^4` secondes

Cette stratégie est adaptée à la plupart des erreurs transitoires (I/O temporaire, DB lock, API externe down).

Cas particuliers :

Type d'erreur | Action | Justification
---|---|---
Erreur permanente (file not found, corrupted) | `{:cancel, reason}` | Pas de retry inutile
Erreur transitoire (I/O, lock) | `{:error, reason}` | Retry automatique
Succès | `:ok` | Job marqué complété

Exemple dans `ImageVariantWorker` :

```elixir
case storage.generate_variants(photo_id) do
  {:ok, variants} -> :ok
  {:error, :file_not_found} -> {:cancel, :file_not_found}  # Permanent
  {:error, :corrupted_file} -> {:cancel, :corrupted_file}  # Permanent
  {:error, reason} -> {:error, reason}  # Retry (I/O, etc.)
end
```

### Configuration `max_attempts`

Valeur par défaut recommandée : 5 (standard Oban)

Worker | Max Attempts | Justification
---|---|---
`ImageVariantWorker` | 3 | Échec après 2 min acceptable (image peut être regénérée manuellement)
`NewsletterWorker` | 5 | Email critique, retry jusqu'à 1h
`NotificationWorker` | 5 | Notification importante
`SessionCleanupWorker` | 3 | Non critique, réessayera demain

La valeur peut être ajustée par worker selon la criticité du job.

### Plugins Oban

Plugin | Configuration | Description
---|---|---
`Pruner` | `max_age: 7 jours` | Nettoie jobs complétés > 7 jours
`Cron` | Crontab custom | Jobs périodiques (cleanup, backup)
`Lifeline` | Activé par défaut | Rescue orphaned jobs (crashes)
`Stager` | Activé par défaut | Staging de jobs schedulés

Configuration Cron prévue :

```elixir
{Oban.Plugins.Cron, 
  crontab: [
    {"0 2 * * *", Portfolio.Workers.SessionCleanupWorker},      # 2h du matin
    {"0 3 * * SUN", Portfolio.Workers.DatabaseVacuumWorker},    # Dimanche 3h
    {"0 9 * * MON", Portfolio.Workers.NewsletterWorker}         # Lundi 9h
  ]
}
```

## Monitoring et Observabilité

### Dashboard Oban Web vs LiveDashboard

Option | Coût | Fonctionnalités | Recommandation
---|---|---|---
Oban Web | $99/dev/an | Interface riche, pause/cancel jobs, insights avancés | Non nécessaire actuellement
LiveDashboard | Gratuit | Vue basique jobs, métriques système, debug | Recommandé (inclus Phoenix)

LiveDashboard Phoenix (gratuit) permet :
- Voir jobs en cours, complétés, échoués
- Métriques Oban (throughput, latence)
- Processus Erlang (mémoire, CPU)
- Debug en production

Accès : `/dev/dashboard` (authentification admin requise)

### Telemetry Events

Oban émet des événements Telemetry automatiques :

```elixir
:telemetry.attach_many(
  "oban-logger",
  [
    [:oban, :job, :start],      # Job démarre
    [:oban, :job, :stop],       # Job complété
    [:oban, :job, :exception],  # Job échoue
    [:oban, :queue, :shutdown]  # Queue arrêtée
  ],
  &handle_event/4,
  nil
)
```

Métriques collectées :
- Durée traitement par worker
- Taux de succès/échec par queue
- Jobs en attente (backlog)
- Throughput (jobs/seconde)

Ces métriques seront intégrées dans ADR-042 (Telemetry Monitoring).

### Logging Structuré

Chaque worker log avec contexte structuré :

```elixir
Logger.info("Image variant generation started",
  photo_id: photo_id,
  attempt: attempt,
  queue: :image_processing
)

Logger.error("Image processing failed",
  photo_id: photo_id,
  attempt: attempt,
  reason: reason,
  will_retry: attempt < max_attempts
)
```

Format JSON en production pour parsing facilité (Logflare, Papertrail).

## Testing

### Mode Test

Configuration test désactive polling automatique :

```elixir
# config/test.exs
config :portfolio, Oban, testing: :manual
```

En mode `:manual`, les jobs ne sont pas exécutés automatiquement. Tests peuvent :
- Enqueue des jobs (vérifier création)
- Exécuter manuellement (vérifier comportement)
- Drainer la queue (exécuter tous jobs en attente)

```elixir
# Test
test "enqueues image variant job" do
  photo = photo_fixture()
  
  assert {:ok, job} = ImageVariantWorker.enqueue(photo.id)
  assert job.queue == :image_processing
  assert job.args == %{"photo_id" => photo.id}
end

test "generates variants successfully" do
  photo = photo_fixture()
  job = ImageVariantWorker.new(%{photo_id: photo.id})
  
  assert :ok = Oban.drain_queue(queue: :image_processing)
  
  updated_photo = Photography.get_photo!(photo.id)
  assert updated_photo.processing_status == :completed
  assert map_size(updated_photo.variants) == 4
end
```

### Test Helpers

```elixir
defmodule Portfolio.ObanHelpers do
  def drain_all_queues do
    Oban.drain_queue(queue: :default)
    Oban.drain_queue(queue: :image_processing)
    Oban.drain_queue(queue: :mailers)
    Oban.drain_queue(queue: :cleanup)
  end
  
  def assert_job_enqueued(worker, args) do
    assert_enqueued(worker: worker, args: args)
  end
end
```

## Plan d'action

### Phase 1: Monitoring LiveDashboard (Priorité: HAUTE)

Tâches :
1. Ajouter Oban stats dans LiveDashboard Phoenix
2. Configurer route `/admin/dashboard` avec auth admin
3. Créer section "Background Jobs" avec :
   - Jobs en cours par queue
   - Jobs échoués récents
   - Throughput par queue
   - Backlog (jobs en attente)
4. Documenter comment accéder au dashboard

Critères de succès :
- Dashboard accessible à `/admin/dashboard`
- Statistiques Oban visibles
- Authentification admin fonctionnelle

Estimation : 1 jour

### Phase 2: Workers Additionnels (Priorité: MOYENNE)

Tâches :

2.1 NewsletterWorker
- Implémenter worker envoi newsletter
- Configurer cron mensuel ou manuel
- Tests unitaires

2.2 NotificationWorker
- Implémenter worker notifications utilisateurs
- Intégrer avec événements domaine
- Tests unitaires

2.3 SessionCleanupWorker
- Implémenter worker nettoyage sessions expirées
- Configurer cron quotidien (2h du matin)
- Tests unitaires

Critères de succès :
- 3 nouveaux workers implémentés
- Tests passent à 100%
- Cron configuré pour jobs périodiques

Estimation : 3 jours

### Phase 3: Migration CDN Invalidation vers Oban (Priorité: MOYENNE)

Contexte :

Actuellement, l'invalidation CDN est lancée via `Task.start` dans `AlbumPublishedHandler` (cf ADR-030). Cette approche présente des risques :
- Pas de retry si échec
- Pas de monitoring
- Échec silencieux possible

Tâches :
1. Créer `CDNInvalidationWorker` dans queue `default`
2. Configurer `max_attempts: 5` (retry important)
3. Modifier `AlbumPublishedHandler` pour enqueuer job Oban
4. Tests unitaires worker
5. Tests intégration avec événements domaine

Critères de succès :
- Zéro `Task.start` dans event handlers
- CDN invalidation via Oban
- Retry automatique en cas d'échec

Estimation : 1 jour

### Phase 4: Alerting (Priorité: BASSE)

Tâches :
1. Configurer alertes si backlog > 100 jobs
2. Configurer alertes si taux échec > 10%
3. Email admin si job critique échoue 3 fois
4. Intégrer avec service monitoring (Logflare, Papertrail)

Critères de succès :
- Alertes configurées
- Admin notifié en cas de problème

Estimation : 1 jour

## Alternatives Futures

### Si Scale Horizontal Nécessaire

Oban supporte nativement le scale horizontal via distributed locking PostgreSQL. Si le projet évolue vers plusieurs instances :

Actions :
1. Aucune modification code nécessaire
2. Oban gère automatiquement la coordination entre nœuds
3. Chaque instance polling sa propre portion de jobs

Déclencheur : Trafic > 10k visiteurs/jour nécessitant plusieurs instances.

### Si Besoin Broadcast Instantané

Si latence polling (1 seconde) devient problématique :

Option : Oban.Notifier avec PostgreSQL LISTEN/NOTIFY
- Broadcast instantané des nouveaux jobs
- Pas de polling constant
- Légèrement plus complexe

Déclencheur : Besoin de latence < 100ms pour jobs critiques.

## Références

- Oban Documentation : https://hexdocs.pm/oban/
- Oban GitHub : https://github.com/sorentwo/oban
- Oban Web Dashboard : https://getoban.pro/ (payant)
- LiveDashboard Phoenix : https://hexdocs.pm/phoenix_live_dashboard/ (gratuit)
- Code source :
  - `config/config.exs:79-88` : Configuration Oban
  - `lib/portfolio/application.ex:20` : Démarrage Oban
  - `lib/portfolio/workers/image_variant_worker.ex` : Worker exemple

## Notes

### Pourquoi Pas Sidekiq/Resque ?

Sidekiq (Ruby) et Resque (Ruby) sont des solutions matures mais nécessitent Redis. Oban offre les mêmes fonctionnalités tout en restant dans l'écosystème Elixir et réutilisant PostgreSQL.

### Oban vs Faktory

Faktory est un serveur de jobs agnostique du langage créé par l'auteur de Sidekiq. Non retenu car :
- Infrastructure externe additionnelle
- Over-engineering pour mono-instance
- Oban mieux intégré avec Elixir/Phoenix

### Performance Oban

Benchmark Oban (source : documentation officielle) :
- Throughput : 10k+ jobs/seconde (single instance)
- Latence : < 1 seconde (polling par défaut)
- Overhead DB : ~1 query/seconde/queue (négligeable)

Pour le volume actuel (< 1000 jobs/jour), Oban est largement surdimensionné.

### Coût Oban Web

Oban Web Dashboard coûte $99/développeur/an. Pour un projet solo avec budget limité, LiveDashboard Phoenix (gratuit) est suffisant pour :
- Voir jobs en cours
- Debugger échecs
- Métriques basiques

Oban Web devient utile si :
- Équipe > 3 développeurs
- Volume > 100k jobs/jour
- Besoin d'insights avancés (pause jobs, cancel, recherche)

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
