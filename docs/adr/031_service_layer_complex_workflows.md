# ADR-031: Service Layer pour Workflows Complexes

Statut: Accepté
Date: 2025-11-11

## Contexte

Dans une architecture Clean Architecture / DDD, la question de la séparation des responsabilités entre les différentes couches est cruciale. Le projet Portfolio utilise actuellement trois couches principales pour la logique métier :

1. **Repository** : Accès aux données (Infrastructure Layer)
2. **Context** : API publique du bounded context (Application Layer)
3. **Service** : Workflows complexes (Application Layer)

### Problématique

La délimitation entre ces couches n'était pas clairement définie, menant à des questions récurrentes :
- Quand créer un Service vs garder la logique dans le Context ?
- Tous les Services doivent-ils implémenter le behaviour `Portfolio.Services.Service` ?
- Le CRUD simple doit-il être dans le Repository ou le Context ?
- `AlbumPublicationService` est-il vraiment nécessaire (seulement 3 étapes) ?

**Exemples de confusion observés :**

```elixir
# Context Photography : Inconsistance
def create_album(attrs), do: AlbumRepository.insert(attrs)  # - Pas de telemetry
def publish_album(album), do: AlbumPublicationService.execute(album)  # - Délégation Service
def upload_photos(album, uploads), do: PhotoUploadService.execute(album, uploads)  # - Service
```

Sans règles claires, le risque est :
- **Fat Contexts** : Toute la logique dans le Context (God Object anti-pattern)
- **Anemic Contexts** : Context devient un simple proxy vers Services
- **Incohérence** : Certaines opérations en Service, d'autres dans Context sans logique

### Contraintes

- **Single Responsibility Principle (SRP)** : Chaque couche a une responsabilité unique
- **Testabilité** : Faciliter les tests unitaires et d'intégration
- **Maintenabilité** : Code facile à comprendre et modifier
- **Réutilisabilité** : Services réutilisables dans plusieurs contextes (admin, API, CLI)
- **Performance** : Support du parallélisme pour opérations coûteuses (upload photos)

### Impact si aucune décision n'est prise

Sans règles claires :
- Code désorganisé et incohérent
- Difficile de savoir où placer nouvelle logique métier
- Tests complexes (trop de dépendances)
- Duplication de code entre Contexts
- Violation des principes SOLID

## Options considérées

### Option 1: Fat Contexts (Toute la logique dans le Context)

**Description:**

Toute la logique métier est placée dans les modules Context (Photography, Auth). Pas de couche Service distincte. Le Context appelle directement les Repositories et orchestre toutes les opérations.

```elixir
defmodule Portfolio.Photography do
  def upload_photos(album_slug, uploads, opts \\ []) do
    with {:ok, album} <- AlbumRepository.get_by_slug(album_slug) do
      # Parallélisme ici
      results = Task.async_stream(uploads, fn upload ->
        Storage.store_photo(upload, [])
      end)

      # Ecto.Multi ici
      multi = Enum.reduce(results, Multi.new(), fn result, multi ->
        # ... création photos ...
      end)

      # Rollback ici si échec
      # ... telemetry, events, cache ...
    end
  end

  def publish_album(album, user_id) do
    with {:ok, album} <- AlbumRepository.update(album, %{published: true}),
         :ok <- invalidate_cache(),
         :ok <- emit_event(album) do
      {:ok, album}
    end
  end
end
```

**Avantages:**
- Simplicité apparente : une seule couche pour la logique métier
- Pas de navigation entre fichiers multiples
- Moins de code boilerplate (pas de behaviour Service)

**Inconvénients:**
- **God Object anti-pattern** : Contexts deviennent énormes (> 1000 lignes)
- **Violation SRP** : Context fait trop de choses (API + orchestration + logique métier)
- **Difficile à tester** : Tests nécessitent tout le Context, impossible d'isoler
- **Duplication** : Logique réutilisable doit être dupliquée si appelée depuis plusieurs endroits
- **Maintenance cauchemardesque** : Fichier monolithique difficile à naviguer
- **Pas de parallélisme propre** : Code Task.async_stream mélangé avec logique métier

**Effort estimé:** Faible (code déjà dans Context)

**Risques:**
- Dette technique massive à long terme [Probabilité: Élevée, Impact: Critique]
- Impossible de tester unitairement [Probabilité: Élevée, Impact: Élevé]

### Option 2: Service Layer avec règles claires (Choix actuel amélioré)

**Description:**

Séparer clairement les responsabilités entre Repository, Context et Service avec des règles explicites :

**Repository (Infrastructure Layer)** : Abstraction de la persistence
- CRUD DB uniquement : insert, update, delete, get, list
- Query Objects pour requêtes composables
- Aucune logique métier, aucun side-effect

**Context (Application Layer)** : API publique du bounded context
- CRUD simple : Déléguer au Repository + wrapper telemetry
- Orchestration simple : 1-3 étapes séquentielles simples
- Cache management : Invalidation après mutations
- Délégation workflows complexes : Appeler les Services appropriés

**Service (Application Layer)** : Workflows complexes multi-étapes
- Workflows > 3 étapes OU
- Opérations parallèles (Task.async_stream) OU
- Transactions complexes (Ecto.Multi > 2 ops) OU
- Logique rollback/compensation OU
- Cross-context coordination

**Architecture:**

```
Controller/LiveView
       ↓
   Context (API publique)
       ↓
   ┌───┴────┐
   ↓        ↓
Repository  Service (workflows complexes)
   ↓           ↓
  DB      Repository + Storage + Events
```

**Implémentation:**

```elixir
# Repository - Accès données uniquement
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  def insert(attrs), do: %Album{} |> Album.changeset(attrs) |> Repo.insert()
  def update(album, attrs), do: album |> Album.changeset(attrs) |> Repo.update()
  def get(id, opts \\ []), do: # ... query DB
  def list(opts \\ []), do: # ... query with filters
end

# Context - API publique + orchestration simple
defmodule Portfolio.Photography do
  # CRUD simple : Repository + telemetry
  def create_album(attrs) do
    with_telemetry([:album, :created], %{}, fn ->
      AlbumRepository.insert(attrs)
    end)
  end

  # Orchestration simple (2-3 étapes)
  def update_album(album, attrs) do
    with {:ok, album} <- AlbumRepository.update(album, attrs),
         :ok <- invalidate_cache_if_published(album) do
      {:ok, album}
    end
  end

  # Workflow complexe : Déléguer au Service
  def upload_photos(album_slug, uploads, opts \\ []) do
    PhotoUploadService.execute(album_slug, uploads, opts)
  end

  def publish_album(album, user_id \\ nil) do
    AlbumPublicationService.execute(album, user_id: user_id)
  end

  def delete_album(album) do
    AlbumDeletionService.execute(album)
  end
end

# Service - Workflow complexe
defmodule Portfolio.Services.Photography.PhotoUploadService do
  use Portfolio.Services.Service  # Behaviour + telemetry macro

  @impl true
  def execute(album_slug, uploads, opts \\ []) do
    with_telemetry([:photos, :uploaded], %{count: length(uploads)}, fn ->
      with {:ok, album} <- Photography.get_album_by_slug(album_slug),
           {:ok, metadata} <- upload_files_parallel(uploads, opts),
           {:ok, photos} <- create_photos_atomically(album, metadata) do
        {:ok, photos}
      else
        {:error, :upload_failed, _reason, uploaded} ->
          rollback_uploaded_files(uploaded)
          {:error, :partial_upload_failure}
        error -> error
      end
    end)
  end

  defp upload_files_parallel(uploads, opts) do
    # Task.async_stream avec max_concurrency, timeout, rollback
  end

  defp create_photos_atomically(album, metadata) do
    # Ecto.Multi pour atomicité
  end

  defp rollback_uploaded_files(metadata) do
    # Compensation : delete files si DB failed
  end
end
```

**Avantages:**
- **SRP respecté** : Chaque couche a une responsabilité unique et claire
- **Testabilité excellente** : Services testables en isolation
- **Réutilisabilité** : Services appelables depuis admin, API, CLI, background jobs
- **Maintenabilité** : Code organisé, facile à naviguer
- **Parallélisme propre** : Task.async_stream encapsulé dans Services
- **Cohérence** : Règles claires pour décider où placer la logique
- **Open/Closed** : Ajouter nouveaux Services sans modifier Contexts existants

**Inconvénients:**
- Couche supplémentaire (Context + Service vs Context seul)
- Plus de fichiers à naviguer (mais organisés logiquement)
- Nécessite discipline pour suivre les règles

**Effort estimé:** Moyen (refactoring léger pour cohérence)

**Risques:**
- Over-engineering si trop de Services pour logique simple [Probabilité: Faible, Impact: Faible]

### Option 3: Anemic Contexts (Context = proxy vers Services)

**Description:**

Le Context devient un simple proxy transparent vers les Services. Toute la logique métier, même simple, est dans les Services.

```elixir
defmodule Portfolio.Photography do
  def create_album(attrs), do: CreateAlbumService.execute(attrs)
  def update_album(album, attrs), do: UpdateAlbumService.execute(album, attrs)
  def delete_album(album), do: DeleteAlbumService.execute(album)
  def publish_album(album), do: PublishAlbumService.execute(album)
  # ... tous déléguent à des Services
end
```

**Avantages:**
- Services testables en isolation
- Réutilisabilité maximale

**Inconvénients:**
- **Over-engineering massif** : Service pour chaque opération, même CRUD simple
- **Context anémique** : Pas de valeur ajoutée, devient un simple dispatcher
- **Navigation complexe** : Toujours besoin d'ouvrir 2 fichiers (Context + Service)
- **Violation DDD** : Context doit être le point d'entrée avec logique métier simple

**Effort estimé:** Élevé (créer des Services partout)

**Risques:**
- Complexité inutile pour opérations simples [Probabilité: Élevée, Impact: Moyen]
- Frustration développeurs [Probabilité: Élevée, Impact: Moyen]

## Décision

L'option choisie est: **Option 2 - Service Layer avec règles claires**

Avec les règles de délimitation suivantes :

### Règles de Délimitation des Couches

#### Repository (Infrastructure Layer)

**Responsabilité unique :** Abstraction de la persistence, CRUD DB uniquement

**Contenu autorisé :**
- - `insert/1`, `update/2`, `delete/1`
- - `get/1`, `get!/1`, `get_by_slug/1`
- - `list/1` avec filtres simples
- - `count_all/0`, `count_published/0`, `count_by_type/1`
- - Utilisation de Query Objects pour requêtes composables

**Contenu interdit :**
- - Logique métier
- - Validation business rules
- - Orchestration multi-étapes
- - Émission d'événements domaine
- - Cache, telemetry, side-effects

**Exemple :**
```elixir
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  def insert(attrs) do
    %Album{} |> Album.changeset(attrs) |> Repo.insert()
  end

  def list(opts \\ []) do
    Album
    |> AlbumQuery.apply_filters(opts)
    |> AlbumQuery.apply_preloads(opts)
    |> Repo.all()
  end
end
```

#### Context (Application Layer)

**Responsabilité unique :** API publique du bounded context, orchestration simple

**Contenu autorisé :**
- - **CRUD simple** : Déléguer au Repository + wrapper telemetry
- - **Orchestration simple** : 1-3 étapes séquentielles simples
- - **Cache management** : Invalidation après mutations
- - **Délégation Services** : Appeler Services pour workflows complexes
- - **Fonctions helpers publiques** : get_album_stats, list_published_albums, etc.

**Contenu interdit :**
- - Workflows complexes (> 3 étapes ou parallélisme)
- - Task.async_stream, Task.await_many
- - Ecto.Multi avec > 2 opérations
- - Logique de retry/rollback complexe
- - Accès direct à Repo (toujours via Repository)

**Exemple :**
```elixir
defmodule Portfolio.Photography do
  # CRUD simple : Repository + telemetry
  def create_album(attrs) do
    with_telemetry([:album, :created], %{}, fn ->
      AlbumRepository.insert(attrs)
    end)
  end

  # Orchestration simple (3 étapes max)
  def update_album(album, attrs) do
    with {:ok, album} <- AlbumRepository.update(album, attrs),
         :ok <- invalidate_cache_if_published(album),
         :ok <- maybe_emit_event(album) do
      {:ok, album}
    end
  end

  # Workflow complexe : Déléguer au Service
  def upload_photos(album_slug, uploads, opts \\ []) do
    PhotoUploadService.execute(album_slug, uploads, opts)
  end
end
```

#### Service (Application Layer)

**Responsabilité unique :** Workflows complexes multi-étapes

**Critères pour créer un Service (au moins 1 critère requis) :**
1. **> 3 étapes séquentielles** OU
2. **Opérations parallèles** (Task.async_stream, Task.await_many) OU
3. **Ecto.Multi avec > 2 opérations** OU
4. **Logique rollback/compensation** (delete files si DB fails) OU
5. **Cross-context coordination** (rare, à éviter si possible) OU
6. **Logique de retry complexe**

**Contenu autorisé :**
- - Orchestration workflows complexes
- - Task.async_stream pour parallélisme
- - Ecto.Multi pour transactions atomiques
- - Rollback/compensation (delete files, invalidate cache)
- - Émission d'événements domaine
- - Telemetry measurements
- - Appel à plusieurs Repositories

**Contenu interdit :**
- - Accès direct à Repo (toujours via Repository)
- - Logique simple qui pourrait rester dans Context

**Structure obligatoire :**
```elixir
defmodule Portfolio.Services.Photography.MyService do
  @moduledoc """
  Service for [description].

  Responsibilities:
  - Step 1
  - Step 2
  - Step 3

  This service encapsulates [complex workflow description].
  """

  use Portfolio.Services.Service  # - OBLIGATOIRE

  @impl true
  def execute(params, opts \\ []) do
    with_telemetry(
      [:portfolio, :services, :my_service, :executed],
      %{...metadata...},
      fn ->
        # Workflow implementation
        with step1 <- do_step1(params),
             step2 <- do_step2(step1),
             step3 <- do_step3(step2) do
          {:ok, result}
        else
          error -> handle_error_and_rollback(error)
        end
      end
    )
  end

  # Private helper functions
  defp do_step1(params), do: # ...
  defp do_step2(result), do: # ...
  defp do_step3(result), do: # ...
end
```

### Justification de la décision

**Critères de décision:**

- **Alignement avec Clean Architecture/DDD:** Parfait. Séparation nette des couches avec responsabilités uniques. Respecte le principe de dépendance (Domain ← Application ← Infrastructure).

- **Impact sur la dette technique:** Réduit significativement la dette en fournissant des règles claires. Évite les Fat Contexts et le code spaghetti.

- **Maintenabilité:** Excellente. Chaque fichier a une taille raisonnable (< 300 lignes). Facile de trouver où ajouter nouvelle logique.

- **Testabilité:** Optimale. Services testables en isolation. Contexts testables via integration tests. Repositories testables avec sandbox DB.

- **Performance:** Support natif du parallélisme via Services (Task.async_stream). Transactions atomiques via Ecto.Multi.

- **Réutilisabilité:** Services réutilisables depuis admin UI, API REST, CLI, background jobs.

- **Sécurité:** Neutre. Validation business rules dans Changesets (Domain Layer).

- **Coût/Effort:** Moyen. Refactoring léger nécessaire pour cohérence, mais investissement rentabilisé rapidement.

- **Réversibilité:** Élevée. Possible de revenir à Fat Contexts en déplaçant logique Service vers Context (mais non recommandé).

**Décision finale:**

Le Service Layer avec règles claires est le meilleur compromis entre **simplicité et organisation**. Cette solution :
1. Respecte les principes SOLID et Clean Architecture
2. Fournit des règles claires pour éviter confusion
3. Facilite la maintenance et l'évolution du code
4. Permet la testabilité et réutilisabilité
5. Support du parallélisme et transactions complexes

Le principal compromis accepté est la **couche supplémentaire** (Context + Service vs Context seul), mais ce compromis est largement compensé par les bénéfices en maintenabilité et testabilité.

## Conséquences

### Positives

- **Code organisé et cohérent** : Règles claires pour placer nouvelle logique métier
- **Testabilité excellente** : Services testables en isolation, Contexts via integration tests
- **Maintenabilité optimale** : Fichiers de taille raisonnable, responsabilités claires
- **Réutilisabilité** : Services appelables depuis plusieurs points d'entrée (admin, API, CLI)
- **Performance** : Support natif du parallélisme (Task.async_stream) et transactions atomiques (Ecto.Multi)
- **Évolutivité** : Facile d'ajouter nouveaux Services sans toucher Contexts existants
- **Respect SOLID** : SRP, Open/Closed, Dependency Inversion respectés

### Négatives

- **Couche supplémentaire** : Plus de fichiers à créer et naviguer (mais organisation logique compense)
- **Discipline requise** : Équipe doit suivre les règles pour éviter incohérences
- **Léger over-engineering possible** : Risque de créer des Services pour logique très simple (mais règles claires limitent ce risque)

### Neutres

- **Apprentissage** : Développeurs juniors doivent comprendre les 3 couches (Repository, Context, Service)
- **Refactoring** : Code existant nécessite ajustements pour cohérence

## Plan d'action

### Phase 1: Documentation et Formation (Priorité: CRITIQUE)

**Tâches:**
1. Documenter les règles de délimitation des couches (Repository, Context, Service)
2. Créer un guide de décision : "Où placer ma nouvelle logique ?"
3. Créer des exemples commentés pour chaque pattern
4. Réviser ce ADR avec l'équipe

**Critères de succès:**
- Documentation complète disponible
- Guide de décision visuel créé (flowchart)
- Exemples pour chaque pattern

**Estimation:** 0.5 jour

### Phase 2: Audit du code existant (Priorité: HAUTE)

**Tâches:**
1. Auditer tous les Contexts (Photography, Auth) pour vérifier cohérence
2. Identifier les violations des règles :
   - Logique complexe qui devrait être dans Service
   - Services inutiles qui devraient être dans Context
   - Logique métier dans Repository
3. Créer une todo list priorisée des refactorings nécessaires

**Cibles d'audit :**

```elixir
# Photography Context
lib/portfolio/photography.ex
  - create_album - Simple CRUD, OK dans Context
  - update_album - 2-3 étapes, OK dans Context
  - publish_album - Délègue à Service, OK
  - upload_photos - Délègue à Service, OK
  - delete_album - Délègue à Service, OK

# Auth Context
lib/portfolio/auth.ex
  - create_user → À vérifier
  - request_magic_link → À vérifier (devrait déléguer à MagicLinkAuthService ?)
  - verify_magic_link → À vérifier

# Repositories
lib/portfolio/photography/repositories/*.ex
  - Vérifier qu'aucune logique métier n'est présente

# Services existants
lib/portfolio/services/photography/*.ex
  - PhotoUploadService - Justifié (parallélisme + Multi + rollback)
  - AlbumPublicationService - Justifié (encapsulation métier publication)
  - AlbumDeletionService - Justifié (Multi + rollback files)
  - PhotoDeletionService - Justifié (transaction + file deletion)

lib/portfolio/services/auth/*.ex
  - MagicLinkAuthService - Justifié (Multi + rate limit + email + events)
```

**Critères de succès:**
- Liste complète des violations identifiées
- Plan de refactoring priorisé

**Estimation:** 1 jour

### Phase 3: Refactoring pour cohérence (Priorité: MOYENNE)

**Tâches:**
1. Corriger les violations identifiées dans Phase 2
2. Ajouter `with_telemetry/3` partout dans les Contexts pour CRUD simple
3. S'assurer que tous les Services utilisent `use Portfolio.Services.Service`
4. Unifier les noms des Services (pattern cohérent)
5. Ajouter `@moduledoc` complet à tous les Services avec section "Responsibilities"

**Exemple de refactoring :**

Avant :
```elixir
# Context sans telemetry
def create_album(attrs) do
  AlbumRepository.insert(attrs)
end
```

Après :
```elixir
# Context avec telemetry
def create_album(attrs) do
  with_telemetry([:album, :created], %{}, fn ->
    AlbumRepository.insert(attrs)
  end)
end
```

**Critères de succès:**
- Zéro violation des règles de délimitation
- Tous les Services avec `use Portfolio.Services.Service`
- Telemetry partout dans Contexts

**Estimation:** 2 jours

### Phase 4: Tests et Validation (Priorité: HAUTE)

**Tâches:**
1. Créer tests unitaires pour tous les Services en isolation
2. Créer tests d'intégration pour les Contexts
3. Vérifier que les Services peuvent être mockés facilement
4. Ajouter tests de rollback/compensation dans Services complexes
5. Valider que `mix test` passe à 100%

**Pattern de test Service :**
```elixir
defmodule Portfolio.Services.Photography.PhotoUploadServiceTest do
  use Portfolio.DataCase, async: true

  alias Portfolio.Services.Photography.PhotoUploadService

  describe "execute/3" do
    test "uploads photos in parallel successfully" do
      album = album_fixture()
      uploads = [upload_fixture(), upload_fixture()]

      assert {:ok, photos} = PhotoUploadService.execute(album.slug, uploads)
      assert length(photos) == 2
    end

    test "rolls back uploaded files if DB insertion fails" do
      # Mock Storage to track file deletions
      # Assert files are deleted on rollback
    end
  end
end
```

**Critères de succès:**
- Tous les Services couverts par tests unitaires
- Tous les Contexts couverts par tests d'intégration
- Coverage > 80% sur Services

**Estimation:** 2 jours

### Phase 5: Guide de Décision Visuel (Optionnel)

**Tâches:**
1. Créer un flowchart "Où placer ma logique métier ?"
2. Ajouter le flowchart dans `docs/architecture/`
3. Référencer le flowchart dans README

**Flowchart (à créer) :**

```
Nouvelle logique métier à implémenter
         ↓
    ┌────────────────────────────┐
    │ Accès DB uniquement ?      │
    │ (CRUD, queries)            │
    └─────────┬──────────────────┘
              │
        ┌─────┴─────┐
        │ OUI       │ NON
        ↓           ↓
   Repository    ┌─────────────────────────┐
                 │ > 3 étapes OU           │
                 │ parallélisme OU         │
                 │ Ecto.Multi > 2 ops OU   │
                 │ rollback/compensation ? │
                 └──────────┬──────────────┘
                            │
                      ┌─────┴─────┐
                      │ OUI       │ NON
                      ↓           ↓
                   Service     Context
```

**Estimation:** 0.5 jour

### Rollback Plan

Si cette architecture de Service Layer pose des problèmes critiques :

1. **Identifier les Services problématiques** (trop complexes, inutiles)
2. **Déplacer logique vers Context** si Service trop simple
3. **Fusionner Services similaires** si trop de fragmentation
4. **Documenter les raisons** du rollback pour apprentissage

**Probabilité de rollback:** Très faible (architecture éprouvée)

## Services Existants Analysés

### Photography Context

#### PhotoUploadService - Justifié

**Fichier:** `lib/portfolio/services/photography/photo_upload_service.ex`

**Workflow:**
1. Récupérer album par slug
2. **Uploader fichiers en parallèle** (Task.async_stream)
3. **Créer photos atomiquement** (Ecto.Multi)
4. **Rollback files** si échec DB

**Justification Service:**
- - Opérations parallèles (Task.async_stream avec max_concurrency)
- - Ecto.Multi avec N opérations (N = nombre de photos)
- - Logique rollback complexe (delete uploaded files si DB fails)
- - Telemetry measurements

**Complexité:** Élevée (parallélisme + atomicité + compensation)

**Verdict:** Service OBLIGATOIRE ✅

#### AlbumPublicationService - Justifié

**Fichier:** `lib/portfolio/services/photography/album_publication_service.ex`

**Workflow:**
1. Update album published=true
2. Invalidate cache (albums + CDN)
3. Emit domain event AlbumPublished

**Justification Service:**
- - Encapsulation du concept métier "Publication" (pas juste un update)
- - Side-effects multiples (cache, CDN, events)
- - Réutilisabilité (admin UI, API, CLI)
- - Cohérence avec autres Services (AlbumDeletion, PhotoUpload)
- - SRP : Le Service gère la "publication", le Context gère l'API

**Complexité:** Moyenne (3 étapes mais sémantique métier forte)

**Verdict:** Service JUSTIFIÉ - (pour encapsulation + cohérence)

#### AlbumDeletionService - Justifié

**Fichier:** `lib/portfolio/services/photography/album_deletion_service.ex`

**Workflow:**
1. Fetch all album photos
2. Delete all photo files from storage
3. Delete album (CASCADE delete photos in DB)
4. Rollback si échec

**Justification Service:**
- - Ecto.Multi avec 3 opérations
- - Logique rollback complexe (accept :not_found as success)
- - Emit domain event AlbumDeleted
- - Telemetry measurements

**Complexité:** Élevée (Multi + rollback + file deletion)

**Verdict:** Service OBLIGATOIRE ✅

#### PhotoDeletionService - Justifié

**Fichier:** `lib/portfolio/services/photography/photo_deletion_service.ex`

**Workflow:**
1. Delete photo record from DB
2. Delete physical file from storage
3. Rollback si échec (accept :not_found as success)
4. Emit domain event PhotoDeleted

**Justification Service:**
- - Ecto.Multi avec 2 opérations (DB + file)
- - Logique rollback (transaction rollback si file deletion fails)
- - Emit domain event
- - Telemetry measurements

**Complexité:** Moyenne (transaction + file + event)

**Verdict:** Service JUSTIFIÉ ✅

### Auth Context

#### MagicLinkAuthService - Justifié

**Fichier:** `lib/portfolio/services/auth/magic_link_auth_service.ex`

**Workflow:**
1. Check rate limit (5 requests/hour per email)
2. Get or create user by email
3. Generate magic link token (32 bytes Base64)
4. Save magic link to database (Ecto.Multi)
5. Emit domain event MagicLinkRequested
6. Send email with magic link

**Justification Service:**
- - Workflow complexe (> 5 étapes)
- - Ecto.Multi (get_or_create user + create magic_link)
- - Rate limiting logic
- - Email sending (side-effect externe)
- - Emit domain events
- - Telemetry measurements

**Complexité:** Élevée (Multi + rate limit + email + events)

**Verdict:** Service OBLIGATOIRE ✅

## Behaviour Service : Standardisation

Tous les Services DOIVENT utiliser le behaviour `Portfolio.Services.Service` pour garantir cohérence et predictabilité.

**Behaviour défini :**

```elixir
# lib/portfolio/services/service.ex
@callback execute(params :: term(), opts :: keyword()) ::
  {:ok, term()} | {:error, term()}
```

**Macro `use Portfolio.Services.Service` fourni :**
- Implémente le behaviour automatiquement
- Fournit la fonction `with_telemetry/3` pour wrapper l'exécution
- Mesure automatiquement la durée et émet un événement telemetry

**Avantages de la standardisation :**

1. **Interface uniforme** : Tous les Services ont `execute/2`
2. **Telemetry gratuit** : Macro injecte automatiquement le wrapper
3. **Predictabilité** : Retour toujours `{:ok, result} | {:error, reason}`
4. **Mockabilité** : Behaviour facilite le mocking dans les tests
5. **Documentation** : Contract explicite via `@callback`

**Pattern obligatoire :**

```elixir
defmodule Portfolio.Services.MyContext.MyService do
  @moduledoc """
  Service for [description].

  Responsibilities:
  - Step 1
  - Step 2
  - Step 3
  """

  use Portfolio.Services.Service  # - OBLIGATOIRE

  @impl true  # - OBLIGATOIRE : Indique implémentation du callback
  def execute(params, opts \\ []) do
    with_telemetry(
      [:portfolio, :services, :my_service, :executed],
      %{...metadata...},
      fn ->
        # Implementation
      end
    )
  end
end
```

**Exception :** Si un Service nécessite plusieurs fonctions publiques (très rare), documenter clairement pourquoi il viole le pattern standard.

## Règle de Décision Rapide

Pour aider à décider où placer nouvelle logique métier :

### Est-ce seulement un accès DB ?
→ **Repository**

### Est-ce un CRUD simple (1-3 étapes séquentielles) ?
→ **Context**

Exemples :
- create_album : Repository + telemetry → Context
- update_album : Repository + invalidate cache → Context
- get_album : Repository → Context (simple délégation)

### Est-ce un workflow complexe ?
→ **Service** si au moins 1 critère :
- [ ] > 3 étapes séquentielles
- [ ] Opérations parallèles (Task.async_stream)
- [ ] Ecto.Multi avec > 2 opérations
- [ ] Logique rollback/compensation
- [ ] Cross-context coordination
- [ ] Retry logic complexe

Exemples :
- upload_photos : Parallélisme + Multi + rollback → Service ✅
- publish_album : Encapsulation métier + cohérence → Service ✅
- delete_album : Multi + rollback files → Service ✅

## Références

- [Clean Architecture - Robert C. Martin](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- [DDD Service Layer Pattern](https://martinfowler.com/eaaCatalog/serviceLayer.html)
- [Elixir Context vs Service Discussion](https://elixirforum.com/t/context-vs-service-layer/12345)
- Code source :
  - `lib/portfolio/services/service.ex` : Behaviour et macro
  - `lib/portfolio/services/photography/*.ex` : Services Photography
  - `lib/portfolio/services/auth/*.ex` : Services Auth
  - `lib/portfolio/photography.ex` : Context Photography (API publique)
  - `lib/portfolio/auth.ex` : Context Auth (API publique)

## Notes

### Alternative considérée : Fat Contexts

L'approche Fat Contexts (toute la logique dans le Context) a été rejetée car :
- Viole le Single Responsibility Principle (SRP)
- Fichiers énormes (> 1000 lignes) difficiles à maintenir
- Impossible de tester unitairement
- Duplication si logique réutilisée dans plusieurs contextes

### Alternative considérée : Anemic Contexts

L'approche Anemic Contexts (Context = proxy vers Services) a été rejetée car :
- Over-engineering pour CRUD simple
- Context perd sa valeur (juste un dispatcher)
- Navigation complexe (toujours 2 fichiers à ouvrir)
- Viole les principes DDD (Context doit avoir logique métier simple)

### Pattern Command vs Service

Certains frameworks utilisent le pattern **Command** au lieu de Service. Les deux sont équivalents pour notre cas d'usage :

**Command Pattern :**
```elixir
PublishAlbumCommand.execute(album)
UploadPhotosCommand.execute(album, uploads)
```

**Service Pattern (choisi) :**
```elixir
AlbumPublicationService.execute(album)
PhotoUploadService.execute(album, uploads)
```

**Raison du choix "Service" :**
- Convention Elixir/Phoenix (Phoenix.Context utilise Services)
- Sémantique claire : "Service" indique une orchestration métier
- Cohérence avec l'écosystème Elixir

### Évolution Future : CQRS

Si le projet évolue vers une architecture CQRS (Command Query Responsibility Segregation), les Services actuels deviendraient des **Command Handlers** :

```elixir
# CQRS Command Handler
defmodule Portfolio.Commands.UploadPhotosHandler do
  def handle(%UploadPhotosCommand{album_slug: slug, uploads: uploads}) do
    # Implementation actuelle de PhotoUploadService
  end
end
```

Cette migration serait naturelle car les Services respectent déjà le principe "execute command → return result".

---

**Date de création:** 2025-11-11
**Dernière révision:** 2025-11-11
