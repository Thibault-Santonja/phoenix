# ADR-013 : Traitement Asynchrone d'Images avec Oban

Statut: Accepté
Date: 2025-07

## Contexte

Le traitement d'images pour génération de variantes (3 WebP + 1 AVIF) prend 3-5 secondes par photo (12MP, 4 variantes). Le contexte photographique impose des contraintes spécifiques :

### Besoins fonctionnels

1. Upload multiple : 10-20 photos simultanées lors d'événements (mariage, reportage)
2. Expérience utilisateur : Upload ne doit pas bloquer l'interface (feedback immédiat)
3. Résilience : Reprise traitement après crash serveur ou redémarrage
4. Monitoring : Visibilité sur jobs en cours, échecs, performances
5. Gestion erreurs : Retry automatique (erreurs transitoires), abandon (erreurs permanentes)

### Contraintes techniques

1. VPS Hetzner 2 vCPU, 4GB RAM : Capacité CPU/mémoire limitée
2. Phoenix LiveView : Timeout requêtes HTTP 60s (traitement sync impossible pour 10+ photos)
3. Upload synchrone bloquant : 10 photos × 5s = 50s → timeout + mauvaise UX
4. Persistence nécessaire : Garantie traitement même après redémarrage
5. PostgreSQL déjà présent : Base données disponible pour persistance jobs

### Problématique

Comment traiter les images de manière asynchrone sans bloquer les requêtes HTTP, avec garantie de traitement (résilience), gestion d'erreurs robuste (retry), et monitoring des jobs, dans un environnement contraint en ressources ?

---

## Options Considérées

### Option 1 : Traitement synchrone bloquant

Traitement immédiat pendant la requête HTTP upload.

**Description :**
L'upload génère les variantes de manière synchrone avant de retourner la réponse HTTP.

```elixir
def upload_photo(upload) do
  with {:ok, file_path} <- store_original(upload),
       {:ok, variants} <- ImageProcessor.generate_variants(file_path, output_dir) do
    create_photo(%{file_path: file_path, variants: variants})
  end
end
```

**Avantages :**
- Simplicité maximale (aucune infrastructure async)
- Photo immédiatement disponible avec variantes
- Pas de complexité supervision/retry
- Debuggage trivial (stack trace directe)

**Inconvénients :**
- Timeout requêtes HTTP (Phoenix 60s par défaut)
- Upload 10 photos = 50s → échec probable
- Interface bloquée pendant traitement (UX catastrophique)
- Aucune résilience (crash = perte traitement)
- Impossible scaling (1 upload = 1 processus Phoenix bloqué)

**Effort estimé :** Faible (solution par défaut)

**Risques :**
- Timeout production [Probabilité: Élevée, Impact: Élevé]
- UX dégradée [Probabilité: Certaine, Impact: Élevé]

**Rejeté** : Incompatible avec besoin upload multiple (> 10 photos).

### Option 2 : Task.Supervisor simple

Utilisation de `Task.Supervisor` pour traitement asynchrone sans persistance.

**Description :**
Spawner des tasks asynchrones supervisées pour traitement images.

```elixir
# Supervision tree
children = [
  {Task.Supervisor, name: Portfolio.ImageTaskSupervisor}
]

# Upload handler
def upload_photo(upload) do
  with {:ok, file_path} <- store_original(upload) do
    # Fire and forget
    Task.Supervisor.start_child(
      Portfolio.ImageTaskSupervisor,
      fn -> generate_variants_async(file_path) end
    )
    
    create_photo(%{file_path: file_path, processing_status: :pending})
  end
end
```

**Avantages :**
- Simple à implémenter (stdlib Elixir, pas de dépendance)
- Feedback immédiat (photo créée en état pending)
- Non bloquant (tasks isolées)
- Supervision automatique (restart si crash)

**Inconvénients :**
- Aucune persistance : Redémarrage serveur = jobs perdus
- Pas de retry automatique (échec = job perdu)
- Pas de monitoring intégré (visibilité jobs en cours)
- Pas de contrôle concurrence (risque surcharge CPU/RAM)
- Pas de priorité jobs (FIFO basique)
- Debugging difficile (tasks éphémères, pas d'historique)

**Effort estimé :** Faible (2-3 jours implémentation)

**Risques :**
- Perte jobs après redémarrage [Probabilité: Certaine, Impact: Élevé]
- Surcharge serveur (pas de backpressure) [Probabilité: Moyenne, Impact: Élevé]

**Rejeté** : Manque de persistance inacceptable (photos non traitées après deploy/crash).

### Option 3 : GenServer custom avec pooling

Implémentation custom d'une pool de GenServers pour traitement.

**Description :**
Pool de GenServers workers qui consomment une queue de jobs (Agent ou ETS).

```elixir
# Pool de workers
defmodule Portfolio.ImageWorkerPool do
  use Supervisor
  
  def start_link(_) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end
  
  def init(:ok) do
    children = for i <- 1..3 do
      Supervisor.child_spec(
        {Portfolio.ImageWorker, i},
        id: {Portfolio.ImageWorker, i}
      )
    end
    
    Supervisor.init(children, strategy: :one_for_one)
  end
end

defmodule Portfolio.ImageWorker do
  use GenServer
  
  def handle_info(:process_next, state) do
    case JobQueue.pop() do
      {:ok, job} -> 
        process_image(job)
        schedule_next()
        {:noreply, state}
      
      :empty -> 
        schedule_next()
        {:noreply, state}
    end
  end
end
```

Avec `Poolboy` ou `NimblePool` pour gestion pool sophistiquée.

**Avantages :**
- Contrôle concurrence explicite (pool size = 2-3 workers)
- Backpressure intégrée (queue saturée = upload ralenti)
- Monitoring custom possible (métriques pool)
- Pas de dépendance externe lourde

**Inconvénients :**
- Complexité implémentation élevée (queue, workers, supervision)
- Persistance à implémenter manuellement (ETS = perte redémarrage, DB = complexe)
- Retry logic à implémenter (exponential backoff, max attempts)
- Monitoring à développer from scratch
- Debugging difficile (état distribué pool + queue)
- Maintenance long terme (bugs, évolutions)
- Réinventer la roue (Oban existe et fait tout ça)

**Effort estimé :** Élevé (2-3 semaines implémentation + tests + monitoring)

**Risques :**
- Bugs implémentation custom [Probabilité: Élevée, Impact: Moyen]
- Maintenance complexe [Probabilité: Certaine, Impact: Moyen]
- Persistance partielle [Probabilité: Moyenne, Impact: Élevé]

**Rejeté** : Rapport complexité/bénéfice défavorable (réinventer Oban).

### Option 4 : Broadway (streaming data processing)

Framework pour traitement streaming de données avec GenStage.

**Description :**
Pipeline Broadway pour consommer des événements upload et traiter images.

```elixir
defmodule Portfolio.ImagePipeline do
  use Broadway
  
  def start_link(_) do
    Broadway.start_link(__MODULE__,
      name: __MODULE__,
      producer: [
        module: {BroadwayRabbitMQ.Producer, queue: "image_processing"}
      ],
      processors: [
        default: [concurrency: 2]
      ]
    )
  end
  
  def handle_message(_, message, _) do
    photo_id = message.data
    generate_variants(photo_id)
    message
  end
end
```

**Avantages :**
- Conçu pour high-throughput data processing
- Backpressure sophistiquée (GenStage)
- Monitoring telemetry intégré
- Support batching (traiter N images en lot)

**Inconvénients :**
- Over-engineering pour use case simple (10-20 photos/jour)
- Nécessite message broker externe (RabbitMQ, Kafka, SQS)
- Complexité architecture élevée (producer, processors, batchers)
- Pas de persistance jobs intégrée (dépend du broker)
- Pas de retry sophistiqué (à implémenter)
- Courbe apprentissage GenStage/Broadway

**Effort estimé :** Élevé (1-2 semaines + infrastructure broker)

**Risques :**
- Complexité disproportionnée [Probabilité: Certaine, Impact: Moyen]
- Dépendance broker externe [Probabilité: Certaine, Impact: Moyen]

**Rejeté** : Conçu pour streaming haute volumétrie (milliers events/seconde), inadapté pour 10-20 photos/jour.

### Option 5 : Oban (persistent job queue) ⭐

Bibliothèque Elixir de job queue avec persistance PostgreSQL.

**Description :**
Jobs Oban persistés en base de données, workers supervisés, retry automatique.

```elixir
# Worker
defmodule Portfolio.Workers.ImageVariantWorker do
  use Oban.Worker,
    queue: :image_processing,
    max_attempts: 3,
    priority: 1
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}}) do
    case generate_variants(photo_id) do
      {:ok, variants} -> 
        update_photo(photo_id, variants)
        :ok
      
      {:error, :file_not_found} -> 
        {:cancel, "File not found"}  # Permanent error
      
      {:error, reason} -> 
        {:error, reason}  # Retry automatique
    end
  end
end

# Enqueue
ImageVariantWorker.new(%{photo_id: id}) |> Oban.insert()
```

**Avantages :**
- Persistance PostgreSQL : Résilience redémarrage serveur (jobs récupérés automatiquement)
- Retry automatique avec exponential backoff configurable (15s, 2m, 5m par défaut)
- Monitoring intégré : Oban Web UI (dashboard jobs, métriques, historique)
- Contrôle concurrence : Queue limit (ex: `image_processing: 2`)
- Gestion erreurs sophistiquée : Permanent (`{:cancel, reason}`) vs transient (`{:error, reason}`)
- Priorités jobs : Priority field (0 = haute, 3 = basse)
- Telemetry events : Hooks pour métriques custom
- Plugins : Pruner (nettoyage jobs anciens), Cron (scheduling), Lifeline (rescue stuck jobs)
- Production ready : Utilisé par des milliers d'apps Elixir
- Maintenance active : Parker Selbert (core team Elixir)

**Inconvénients :**
- Nécessite PostgreSQL : Contrainte déjà présente (ADR-004, imposée par Oban justement)
- Complexité configuration : Queues, workers, plugins à configurer
- Migration base données : Table `oban_jobs` (overhead ~1-2MB/1000 jobs)
- Dépendance externe : Mise à jour Oban nécessaire (breaking changes possibles)

**Effort estimé :** Moyen (2-3 jours configuration + migration + tests)

**Risques :**
- Saturation table oban_jobs sans pruning [Probabilité: Faible, Impact: Moyen]
- Breaking changes Oban (rare) [Probabilité: Faible, Impact: Faible]

---

## Décision

L'option choisie est : **Option 5 - Oban**

### Critères de décision

**Alignement avec l'architecture :**
- PostgreSQL déjà présent (ADR-004) : Pas de nouvelle dépendance infrastructure
- DDD events : `PhotoUploaded` event → enqueue Oban job (découplage)
- Supervision OTP : Oban supervisé par application, restart automatique

**Impact sur la dette technique :**
- Implémentation custom évitée (GenServer pools = maintenance long terme)
- API stable et documentée (Oban = standard communauté Elixir)
- Plugins extensibles (monitoring, cron, etc. sans code custom)

**Maintenabilité :**
- Code worker simple (focus logique métier, pas infrastructure)
- Debugging facilité (Oban Web UI = visibilité jobs, historique, erreurs)
- Tests simples (Oban.Testing helpers, mode inline test)

**Performance :**
- Concurrence contrôlée : `queue: [image_processing: 2]` limite RAM/CPU
- Backpressure : Queue saturée = enqueue ralenti (pas de crash)
- Telemetry : Monitoring performance jobs (durée, throughput)

**Sécurité :**
- Jobs atomiques : Transaction PostgreSQL (all-or-nothing)
- Isolation workers : Crash worker N ≠ impact worker M
- Replay attacks : Idempotence jobs (même photo_id traité 2× = safe)

**Coût/Effort :**
- Setup : 2-3 jours (migration, configuration, workers, tests)
- Maintenance : Faible (bibliothèque mature, communauté active)
- Infrastructure : Aucun coût ajouté (PostgreSQL existant)

**Réversibilité :**
- Migration Task.Supervisor : Possible mais perte fonctionnalités (retry, monitoring)
- Migration Broadway : Complexité augmentée, inadapté au volume
- Désinstallation : Supprimer table `oban_jobs`, retirer dépendance (réversible)

### Décision finale

Adoption Oban comme système de job queue asynchrone pour traitement d'images avec les justifications suivantes :

1. **Persistance critique** : Garantie traitement même après crash/redémarrage serveur (photos perdues inacceptable)

2. **Retry automatique** : Gestion erreurs transitoires (I/O temporaire, network glitch) sans code custom

3. **Monitoring intégré** : Oban Web UI = visibilité production, debugging facilité, métriques

4. **Contrôle concurrence** : `limit: 2` workers simultanés = protection VPS 4GB RAM

5. **PostgreSQL existant** : Pas de nouvelle dépendance infrastructure (coût déjà payé ADR-004)

6. **Évite réinventer la roue** : GenServer pools custom = 2-3 semaines développement + bugs + maintenance vs 2-3 jours Oban

---

## Conséquences

### Positives

1. **Résilience production**
   - Jobs persistés PostgreSQL : Redémarrage serveur = reprise automatique traitement
   - Retry automatique : Erreurs transitoires (I/O, network) gérées sans intervention
   - Exponential backoff : 15s, 2m, 5m (évite surcharge serveur)

2. **Expérience utilisateur**
   - Upload non bloquant : Feedback immédiat (photo en état pending)
   - Upload multiple : 20 photos = 20× 200ms (upload original) vs 20× 5s (sync)
   - Interface réactive : Pas de timeout, pas de freeze

3. **Monitoring et observabilité**
   - Oban Web UI : Dashboard jobs en cours, historique, échecs, performances
   - Telemetry events : Hooks custom pour métriques (durée traitement, taux échec)
   - Logging structuré : photo_id, attempt, duration, reason

4. **Contrôle ressources**
   - Concurrence limitée : `image_processing: 2` = max 2 jobs simultanés
   - Backpressure : Queue saturée = ralentissement enqueue (pas de crash)
   - Isolation : Crash worker = restart automatique sans impact autres jobs

5. **Maintenabilité**
   - Code worker simple : Focus logique métier (génération variantes)
   - Tests simples : `Oban.Testing.with_testing_mode(:inline)` = mode synchrone tests
   - Debugging facilité : Historique jobs, stack traces, retry count

### Négatives

1. **Complexité configuration (mitigée)**
   - Migration base données : Table `oban_jobs` (overhead ~1-2MB/1000 jobs)
   - Configuration queues, plugins, workers : Courbe apprentissage
   - **Mitigation** : Documentation Oban excellente, configuration initiale simple

2. **Dépendance externe**
   - Mise à jour Oban : Vérification breaking changes nécessaire
   - Lock version production : Éviter upgrades automatiques
   - **Mitigation** : Oban stable (v2.x depuis 2020), communauté large

3. **Saturation table oban_jobs sans pruning (résolu)**
   - 1000 jobs/mois × 12 mois = 12k lignes (~ 10-20MB)
   - Plugin Pruner configuré : Suppression jobs > 7 jours
   - **Mitigation** : `Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7` (7 jours)

4. **Dette technique identifiée : Task.async_stream hybride**
   - `PhotoUploadService` utilise `Task.async_stream` pour uploads parallèles (non Oban)
   - `PhotoUploadedHandler` utilise `Task.start` pour extraction EXIF (non Oban)
   - Risque surcharge : Tasks illimitées + Oban workers = dépassement RAM/CPU
   - **Mitigation prévue** : Migration complète vers Oban (voir Plan d'action Phase 3)

### Neutres

1. **PostgreSQL obligatoire**
   - Contrainte déjà présente (ADR-004)
   - Impact nul sur architecture

2. **Oban Web UI nécessite route Phoenix**
   - Configuration route `/admin/oban` avec authentification
   - Impact faible (quelques lignes code)

---

## Configuration Technique

### Configuration Oban

```elixir
# config/config.exs
config :portfolio, Oban,
  engine: Oban.Engines.Basic,
  queues: [
    default: 10,              # Jobs génériques
    image_processing: 2       # Traitement images (heavy) - 3 WebP + 1 AVIF
  ],
  plugins: [
    # Nettoyage jobs anciens (> 7 jours)
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7},
    
    # Rescue jobs stuck (> 15min sans heartbeat)
    {Oban.Plugins.Lifeline, rescue_after: :timer.minutes(15)}
  ],
  repo: Portfolio.Repo
```

**Justification configuration :**

- `image_processing: 2` : Cohérence ADR-011 (calcul RAM VPS 4GB : 2× 50MB + marge sécurité)
- `Pruner max_age: 7 jours` : Compromis audit debugging / saturation table
- `Lifeline rescue_after: 15min` : Jobs image < 10s normalement, 15min = sécurité crash silencieux

### Worker ImageVariantWorker

```elixir
defmodule Portfolio.Workers.ImageVariantWorker do
  use Oban.Worker,
    queue: :image_processing,
    max_attempts: 3,
    priority: 1  # 0=haute, 3=basse ; 1=normal-basse
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}, attempt: attempt}) do
    case storage_adapter().generate_variants(photo_id) do
      {:ok, variants} ->
        update_photo(photo_id, variants, :completed)
        :ok
      
      # Erreurs permanentes (cancel job, pas de retry)
      {:error, :file_not_found} -> {:cancel, "File not found"}
      {:error, :corrupted_file} -> {:cancel, "Corrupted file"}
      
      # Erreurs transitoires (retry automatique avec backoff)
      {:error, reason} -> {:error, reason}
    end
  end
end
```

**Gestion erreurs :**

- **Permanent** (`{:cancel, reason}`) : Photo absente, fichier corrompu → abandon immédiat
- **Transient** (`{:error, reason}`) : I/O temporaire, timeout network → retry backoff
- **Backoff automatique** : Oban implémente exponential backoff par défaut (15s, 2m, 5m)

**Configuration backoff custom (si nécessaire) :**

```elixir
use Oban.Worker,
  queue: :image_processing,
  max_attempts: 5,
  backoff: fn attempt -> 
    # Custom: 30s, 2m, 10m, 30m, 1h
    trunc(:math.pow(2, attempt) * 30)
  end
```

### Migration base données

```elixir
# priv/repo/migrations/20250727_add_oban_jobs_table.exs
defmodule Portfolio.Repo.Migrations.AddObanJobsTable do
  use Ecto.Migration

  def up do
    Oban.Migration.up(version: 12)
  end

  def down do
    Oban.Migration.down(version: 1)
  end
end
```

### Enqueue job

```elixir
# Dans PhotoUploadService ou event handler
def enqueue_image_processing(photo_id) do
  %{photo_id: photo_id}
  |> Portfolio.Workers.ImageVariantWorker.new()
  |> Oban.insert()
end
```

### Tests

```elixir
# test/portfolio/workers/image_variant_worker_test.exs
defmodule Portfolio.Workers.ImageVariantWorkerTest do
  use Portfolio.DataCase, async: true
  use Oban.Testing, repo: Portfolio.Repo
  
  alias Portfolio.Workers.ImageVariantWorker
  
  test "processes image and updates photo" do
    photo = insert(:photo, processing_status: :pending)
    
    # Mode synchrone pour tests
    assert :ok = perform_job(ImageVariantWorker, %{photo_id: photo.id})
    
    updated = Repo.reload!(photo)
    assert updated.processing_status == :completed
    assert map_size(updated.variants) == 4
  end
  
  test "cancels job on file not found" do
    assert {:cancel, _} = perform_job(ImageVariantWorker, %{photo_id: "invalid"})
  end
end
```

---

## Plan d'action

### Phase 1 : Configuration Oban (Complétée 2025-07)

**Étapes réalisées :**
1. Installation dépendance `{:oban, "~> 2.17"}`
2. Migration `add_oban_jobs_table` (version 12)
3. Configuration queues et plugins
4. Création worker `ImageVariantWorker`
5. Tests unitaires worker

**Statut :** Complété

### Phase 2 : Correction concurrency ✅ (Complétée 2025-11)

**Problème :** Configuration actuelle `image_processing: 3` incohérente avec ADR-011 (`limit: 2`).

**Action :**

```elixir
# config/config.exs
config :portfolio, Oban,
  queues: [
    default: 10,
    image_processing: 2  # Corrigé : 3 → 2 (3 WebP + 1 AVIF par photo)
  ]
```

**Justification :** Calcul RAM ADR-011 (2× 50MB + 1000MB services = 1.1GB / 4GB = safe).

**Tests validation :**
- Upload 10 photos simultanées
- Monitoring RAM/CPU pendant traitement
- Vérification aucun OOM (Out Of Memory)

**Critères succès :**
- RAM peak < 2GB (50% VPS 4GB)
- CPU < 100% sustained (pas de throttling)
- Aucun timeout job (< 10s par photo)

### Phase 3 : Migration Task.async_stream vers Oban (Q1 2026)

**Problème identifié :** Dette technique hybride Task + Oban.

**Situation actuelle :**

```elixir
# PhotoUploadService : Task.async_stream pour uploads parallèles
Task.async_stream(uploads, fn upload -> 
  storage().store_photo(upload, []) 
end)

# PhotoUploadedHandler : Task.start pour extraction EXIF
Task.start(fn -> extract_and_store_exif(event) end)
```

**Risques :**
- Tasks illimitées + Oban workers = surcharge CPU/RAM possible
- Pas de retry sur échec EXIF extraction
- Pas de monitoring tasks (visibilité limitée)

**Solution : Architecture cible Oban pur**

1. **Créer worker EXIF léger**

```elixir
defmodule Portfolio.Workers.ExifExtractionWorker do
  use Oban.Worker,
    queue: :exif_extraction,
    max_attempts: 2,
    priority: 2  # Plus basse priorité qu'images
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_id" => photo_id}}) do
    case extract_exif(photo_id) do
      {:ok, exif_data} -> 
        update_photo_exif(photo_id, exif_data)
        :ok
      {:error, reason} -> 
        {:error, reason}  # Retry 1× puis abandon
    end
  end
end
```

2. **Configurer queue dédiée**

```elixir
config :portfolio, Oban,
  queues: [
    default: 10,
    image_processing: 2,      # Heavy : 3-5s/job, 50MB RAM
    exif_extraction: 5        # Light : <1s/job, 10MB RAM
  ]
```

3. **Remplacer Task.start par enqueue**

```elixir
# PhotoUploadedHandler
def handle_info({:photo_uploaded, event}, state) do
  # Au lieu de Task.start
  ExifExtractionWorker.new(%{photo_id: event.photo_id})
  |> Oban.insert()
  
  {:noreply, state}
end
```

4. **Upload parallèle : repenser architecture**

Option A : Upload séquentiel + Oban (simple)
```elixir
# PhotoUploadService
def execute(album_slug, uploads) do
  Enum.each(uploads, fn upload ->
    with {:ok, photo} <- create_photo_pending(upload) do
      ImageVariantWorker.enqueue(photo.id)
    end
  end)
end
```

Option B : Upload parallèle Task + Oban workers (actuel optimisé)
```elixir
# Garder Task.async_stream pour uploads (I/O bound, rapide)
# Mais limiter concurrence explicitement
Task.async_stream(uploads, &store_photo/1, 
  max_concurrency: 4,  # Limité explicitement
  timeout: 10_000
)
```

**Recommandation :** Option B (upload parallèle Task conservé, juste EXIF → Oban).

**Justification :**
- Upload original = I/O bound (200-500ms), pas CPU intensive
- Task.async_stream avec `max_concurrency: 4` = sécurisé
- Traitement images = CPU bound → Oban nécessaire
- EXIF extraction = CPU light mais bénéficie retry/monitoring Oban

**Critères succès :**
- Suppression `Task.start` dans `PhotoUploadedHandler`
- EXIF extraction via Oban avec retry
- Monitoring EXIF jobs dans Oban Web UI
- Tests régression (EXIF correctement extrait)

### Phase 4 : Monitoring et alerting (Q1 2026)

**Objectif :** Visibilité production jobs Oban.

**Actions :**

1. **Oban Web UI (priorité haute)**

```elixir
# lib/portfolio_web/router.ex
import Phoenix.LiveDashboard.Router

scope "/admin", PortfolioWeb do
  pipe_through [:browser, :require_authenticated_user, :require_admin]
  
  # Oban Web UI
  forward "/oban", Oban.Web.Router
end
```

Configuration authentification :
```elixir
# config/runtime.exs
config :portfolio, Oban.Web,
  auth: {PortfolioWeb.Auth, :check_admin}
```

2. **Telemetry handlers custom**

```elixir
# lib/portfolio_web/telemetry.ex
defmodule PortfolioWeb.Telemetry do
  def handle_event(
    [:oban, :job, :exception], 
    measurements, 
    %{job: job, kind: kind, reason: reason}, 
    _config
  ) do
    # Log erreur structuré
    Logger.error("Oban job failed",
      worker: job.worker,
      photo_id: job.args["photo_id"],
      attempt: job.attempt,
      max_attempts: job.max_attempts,
      kind: kind,
      reason: inspect(reason)
    )
    
    # Alerting Slack/Email si échec définitif
    if job.attempt >= job.max_attempts do
      notify_admin("Image processing failed permanently", job)
    end
  end
end
```

3. **Métriques dashboard admin**

```elixir
# lib/portfolio_web/live/admin/dashboard_live/index.ex
def mount(_params, _session, socket) do
  stats = %{
    jobs_pending: count_jobs_by_state(:available),
    jobs_running: count_jobs_by_state(:executing),
    jobs_failed_24h: count_failed_jobs_last_24h(),
    avg_processing_time: avg_job_duration(:image_processing)
  }
  
  {:ok, assign(socket, stats: stats)}
end
```

**Critères succès :**
- Oban Web UI accessible `/admin/oban`
- Alertes échecs définitifs (email/Slack)
- Dashboard admin avec métriques jobs
- Logs structurés jobs (photo_id, durée, erreur)

### Phase 5 : Optimisations avancées (Q2 2026, optionnel)

**Si nécessaire après production :**

1. **Batching pour uploads massifs**

```elixir
# Si > 50 photos uploadées simultanément
defmodule Portfolio.Workers.BatchImageWorker do
  use Oban.Worker, queue: :image_processing
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"photo_ids" => photo_ids}}) do
    # Traiter 10 photos en batch (économie overhead Oban)
    Enum.each(photo_ids, &generate_variants/1)
  end
end
```

2. **Priorité dynamique**

```elixir
# Photos album publié = priorité haute
priority = if album.published?, do: 0, else: 2

ImageVariantWorker.new(%{photo_id: photo.id}, priority: priority)
|> Oban.insert()
```

3. **Rate limiting uploads**

```elixir
# Limiter uploads utilisateur (anti-abuse)
{:ok, _} = Hammer.check_rate("upload:#{user_id}", 60_000, 10)
```

---

## Références

### Documentation technique

- [Oban documentation](https://hexdocs.pm/oban/Oban.html)
- [Oban.Worker](https://hexdocs.pm/oban/Oban.Worker.html)
- [Oban.Plugins.Pruner](https://hexdocs.pm/oban/Oban.Plugins.Pruner.html)
- [Oban Web UI](https://getoban.pro/oban-web)
- [Task.async_stream](https://hexdocs.pm/elixir/Task.html#async_stream/3)

### Articles et études

- Parker Selbert "Reliable Background Jobs with Oban" (2020)
- Chris McCord "Phoenix and Background Jobs" (2019)
- José Valim "GenStage and Flow" (2017) - alternatives streaming

### Code pertinent

- `lib/portfolio/workers/image_variant_worker.ex` : Worker principal
- `lib/portfolio/photography/event_handlers/photo_uploaded_handler.ex` : Enqueue jobs
- `lib/portfolio/services/photography/photo_upload_service.ex` : Upload parallèle (dette technique)
- `config/config.exs` : Configuration Oban queues/plugins
- `priv/repo/migrations/20250727_add_oban_jobs_table.exs` : Migration table jobs

---

## Notes

### Décisions actées

1. Oban comme système job queue (2025-07)
2. Concurrency `image_processing: 2` (correction à appliquer)
3. Retry automatique avec backoff Oban par défaut
4. Pruner 7 jours pour nettoyage jobs
5. Oban Web UI pour monitoring production

### Compromis acceptés

1. **PostgreSQL obligatoire** : Contrainte déjà présente ADR-004, impact nul
2. **Dette technique Task.async_stream** : Migration Oban prévue Q1 2026, risque contrôlé
3. **Overhead table oban_jobs** : 1-2MB/1000 jobs, négligeable (pruning 7 jours)

### Enseignements

1. **Persistance non négociable**
   - Redémarrage serveur fréquent (deploy, crash) : Jobs perdus = photos non traitées
   - Task.Supervisor insuffisant (éphémère)
   - Oban = seule solution persistance + retry + monitoring intégrés

2. **Éviter réinventer la roue**
   - GenServer pools custom = 2-3 semaines développement + bugs + maintenance
   - Oban = 2-3 jours setup, production ready, communauté large
   - Rapport complexité/bénéfice largement en faveur Oban

3. **Backoff automatique critique**
   - Erreurs transitoires (I/O temporaire, network glitch) fréquentes production
   - Retry immédiat = saturation serveur (cascade échecs)
   - Exponential backoff (15s, 2m, 5m) = laisser temps système récupérer

4. **Monitoring essentiel production**
   - Oban Web UI = visibilité jobs sans instrumentation custom
   - Telemetry events = hooks métriques/alerting
   - Debugging facilité : Historique jobs, stack traces, retry count

### Prochaines révisions

- Post-production : Retour expérience charge réelle (10+ photos simultanées)
- Q1 2026 : Migration Task.async_stream → Oban (dette technique)
- Q1 2026 : Monitoring complet (Oban Web UI, telemetry, alerting)
- Q2 2026 : Optimisations avancées si nécessaire (batching, priorité dynamique)
