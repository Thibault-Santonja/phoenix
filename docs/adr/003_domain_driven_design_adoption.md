# ADR-003: Adoption de Domain-Driven Design

Statut: Accepté
Date: 2025-06

## Contexte

Au démarrage du projet Portfolio, plusieurs facteurs orientaient vers une architecture plus structurée qu'un simple CRUD :

### Objectifs d'Apprentissage

**Perfectionnement DDD** :
- Besoin d'approfondir Domain-Driven Design pour montée en compétences professionnelle
- Lectures récentes (2024) : Eric Evans "Domain-Driven Design", Vaughn Vernon "Implementing DDD"
- Participation à conférences (VoxxedDays Geneva, Devoxx Paris) avec présentations DDD
- Influence d'une collègue experte (Aurore Jeremie) ayant démontré l'importance de DDD en production

**Projet d'entraînement** :
- Portfolio personnel = terrain d'expérimentation sans pression commerciale
- Volonté de tester patterns DDD en Elixir (moins documenté que Java/C#)
- Focus sur méthodologie (DDD + TDD + Clean Code) autant que sur fonctionnalités

### Anticipation de Croissance

**Évolution prévisible** :
- Domaine photographique : Ajout de galeries, tags, collections, clients
- Domaine technique : Blog tech avec articles, séries, code samples
- Domaine AMVCC : Articles historiques, événements, reconstitutions
- Authentification : Extension aux commentaires, favoris, accès restreints

**Risque CRUD Simple** :
- Scalabilité limitée : Fat contexts difficiles à maintenir au-delà de 500 lignes
- Couplage fort : Logique métier mélangée avec infrastructure (Ecto, DB)
- Tests complexes : Dépendances DB pour tester logique métier
- Refactoring coûteux : Migration CRUD → DDD nécessite réécriture complète

### Besoins Architecturaux

**Séparation des préoccupations** :
- Domaine métier (albums, photos, utilisateurs) vs Infrastructure (Ecto, storage, mailers)
- Isolation bounded contexts (Photography, Auth, futur Blog)
- Évolutivité indépendante de chaque contexte

**Testabilité** :
- Tests unitaires du domaine sans DB
- Mocking facilité (repositories, services)
- Architecture facilitant TDD

**Maintenabilité long terme** :
- Code auto-documenté via ubiquitous language
- Modules courts (< 300 lignes) grâce à SRP (Single Responsibility Principle)
- Facilité de refactoring (changements localisés)

## Options Considérées

### Option 1: Domain-Driven Design (Tactical Patterns)

**Description:**
Application des tactical patterns DDD : Bounded Contexts, Aggregates, Entities, Value Objects, Repositories, Domain Services, Domain Events.

**Architecture proposée:**

```
lib/portfolio/
├── photography/                    # Bounded Context Photography
│   ├── album.ex                   # Aggregate Root
│   ├── photographie.ex            # Aggregate Root
│   ├── projet.ex                  # Aggregate Root
│   ├── value_objects/
│   │   ├── slug.ex                # Value Object
│   │   ├── titre.ex               # Value Object
│   │   ├── description.ex         # Value Object
│   │   ├── empreinte.ex           # Value Object
│   │   └── etat_traitement.ex     # Value Object
│   ├── repositories/
│   │   ├── album_repository.ex    # Repository Pattern
│   │   ├── photographie_repository.ex
│   │   └── projet_repository.ex
│   ├── queries/
│   │   ├── album_query.ex         # Query Objects (CQRS lite)
│   │   └── photo_query.ex
│   ├── events.ex                  # Domain Events
│   ├── event_handlers/            # Event Handlers
│   └── storage/                   # Infrastructure (Ports & Adapters)
├── auth/                          # Bounded Context Auth
│   ├── user.ex                    # Aggregate Root
│   ├── magic_link.ex              # Entity
│   ├── user_session.ex            # Entity
│   ├── value_objects/
│   │   └── email.ex               # Value Object
│   ├── magic_link_service.ex      # Domain Service
│   ├── session_service.ex         # Domain Service
│   └── user_service.ex            # Domain Service
├── services/photography/          # Application Services
│   ├── photo_upload_service.ex    # Orchestration upload
│   ├── album_publication_service.ex
│   ├── album_deletion_service.ex
│   └── photo_deletion_service.ex
├── photography.ex                 # Context Facade (API publique)
├── auth.ex                        # Context Facade
└── domain_events.ex               # Event infrastructure (PubSub)
```

**Principes appliqués:**

**1. Bounded Contexts**
- **Photography** : Gestion albums/photographies, projets, traitement images, publication
- **Auth** : Authentification passwordless, sessions, utilisateurs
- **User** : Gestion utilisateurs, profils, rôles
- **Communication** : Notifications, newsletters, abonnés
- **Blog** (futur) : Articles tech/AMVCC, catégories, tags

Chaque contexte a son propre langage ubiquitaire et évolue indépendamment.

**2. Aggregates**
- **Album** : Collection cohérente de photographies, invariants (titre, type, dates), publication
- **Photographie** : Image avec métadonnées, traitement async, réutilisable (Blog futur, Projets)
- **Projet** : Ensemble structuré d'albums et photographies (ex: mariage, événement multi-albums) - Voir ADR-016 pour pattern Composite
- **User** : Utilisateur avec rôles, sessions, magic links
- **Notification** : Message à destination utilisateur
- **Newsletter** : Communication périodique
- **Abonné** : Contact abonné à newsletter

Choix **Photographie comme aggregate séparé** (pas entity enfant d'Album) :
- Cycle de vie indépendant : Upload → Traitement → Prêt, peut exister sans album
- Réutilisabilité : Photographies utilisables dans Blog (articles Tech/AMVCC) et Projets
- Granularité transactionnelle : Modifier photographie ne verrouille pas album

**3. Value Objects**
- **Slug** : Identifiant URL-safe avec validation, unicité, immutabilité
- **Email** : Validation RFC 5322, normalisation (lowercase), immutabilité
- **Titre** : Titre avec validation longueur (3-200 caractères), nettoyage espaces
- **Description** : Description avec validation longueur (10-5000 caractères), support markdown
- **Empreinte** : Hash SHA-256 16 caractères pour identification unique fichiers
- **ÉtatTraitement** : Enum (pending, processing, ready, failed) pour statut traitement async
- **ExifData** : Métadonnées EXIF structurées (appareil, objectif, paramètres, localisation) - Stockage JSONB PostgreSQL

Value Objects futurs envisageables (refactoring) :
- **Dimensions** (width, height) : Garantir dimensions > 0
- **DateRange** (date_debut, date_fin) : Garantir début ≤ fin ≤ aujourd'hui

Approche pragmatique : Créer VO si validation/invariants complexes OU réutilisabilité forte.

**4. Repositories**
Abstraction de la persistence derrière interfaces :
```elixir
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  @moduledoc "Abstraction persistence albums"

  def list(opts \\ []), do: # ...
  def get(id), do: # ...
  def create(attrs), do: # ...
  def update(album, attrs), do: # ...
  def delete(album), do: # ...
end
```

Bénéfices :
- Séparation domaine/infrastructure (Ecto dans repositories, pas dans aggregates)
- Testabilité : Mock repositories dans tests unitaires
- Évolutivité : Changement de DB facilité (même si peu probable)

**5. Services**

**Domain Services** (Auth) :
- `MagicLinkService` : Génération/vérification tokens passwordless
- `SessionService` : Création/révocation sessions
- `UserService` : Cycle de vie utilisateurs

**Application Services** (Photography) :
- `PhotoUploadService` : Orchestration upload parallèle + traitement async
- `AlbumPublicationService` : Workflow publication (validation, événements, cache)
- `AlbumDeletionService` : Suppression cascade (album + photos + fichiers)
- `PhotoDeletionService` : Suppression photo + variantes + invalidation cache

Critère service vs logique dans aggregate :
- **Service** si orchestration multi-étapes, transactions complexes, coordination > 1 aggregate
- **Aggregate** si validation simple, invariants, logique locale

Objectif : Respecter SRP (Single Responsibility Principle), modules < 300 lignes.

**6. Domain Events**

Events publiés via Phoenix.PubSub :
- `PhotoUploaded` : Déclenche traitement async (Oban workers)
- `AlbumPublished` : Invalide cache, notifie abonnés (futur)
- `MagicLinkVerified` : Audit trail, analytics (futur)

Motivations :
- **Découplage** : Contextes communiquent sans dépendances directes
- **Extension future** : Event sourcing, audit trail, analytics
- **Audit trail** : Historique des événements métier

**7. Ubiquitous Language**

Vocabulaire métier documenté dans `@moduledoc` :
- **Album** : Collection cohérente de photographies autour d'un événement
- **Photographie** : Image individuelle avec métadonnées EXIF et variantes
- **Projet** : Ensemble structuré d'albums et photographies (ex: mariage multi-albums)
- **Published** : État d'un album visible publiquement (vs brouillon)
- **Cover Photo** : Photographie représentative (première par display_order)
- **Display Order** : Ordre d'affichage des photographies dans album
- **Type** : Catégorie métier (couples, wedding, music, reenactment, etc.)
- **Slug** : Identifiant URL-friendly unique généré depuis titre
- **Magic Link** : Lien d'authentification passwordless à usage unique

Langage en évolution : Rigueur initiale insuffisante, documentation progressive.

**Avantages:**
- Architecture scalable : Ajout de features sans refonte majeure
- Testabilité excellente : Tests domaine sans DB, mocking facilité
- Maintenabilité long terme : Code auto-documenté, modules courts
- Séparation des préoccupations : Domaine vs Infrastructure vs Application
- Apprentissage DDD : Terrain d'entraînement pour montée en compétences
- Facilité de refactoring : Changements localisés grâce à SRP
- Documentation vivante : Ubiquitous language dans code

**Inconvénients:**
- Complexité initiale accrue : Plus de fichiers, plus de concepts
- Verbosité : Repositories, services, events ajoutent boilerplate
- Courbe d'apprentissage : DDD nécessite compréhension patterns
- Développement plus lent initialement : Setup patterns vs CRUD direct
- Risque d'over-engineering : Value Objects, services parfois excessifs

**Effort estimé:** Élevé (apprentissage patterns + implémentation)

**Risques:**
- Over-engineering pour projet solo [Probabilité: Moyenne, Impact: Moyen]
  - Mitigation : Approche pragmatique, patterns appliqués selon besoin réel
- Courbe apprentissage ralentit développement [Probabilité: Élevée, Impact: Faible]
  - Acceptable : Objectif = apprentissage autant que livraison
- Verbosité excessive (boilerplate) [Probabilité: Faible, Impact: Faible]
  - Mitigation : Générateurs Mix pour réduire boilerplate

---

### Option 2: CRUD Simple (Phoenix Contexts Standards)

**Description:**
Utilisation standard des Phoenix contexts sans patterns DDD avancés.

**Architecture:**
```
lib/portfolio/
├── photography.ex          # Context avec toute logique
├── photography/
│   ├── album.ex           # Schema Ecto simple
│   └── photo.ex           # Schema Ecto simple
├── auth.ex
└── auth/
    └── user.ex
```

**Exemple:**
```elixir
defmodule Portfolio.Photography do
  import Ecto.Query
  alias Portfolio.Repo
  alias Portfolio.Photography.Album

  def list_albums do
    Repo.all(from a in Album, order_by: [desc: a.inserted_at])
  end

  def create_album(attrs) do
    %Album{}
    |> Album.changeset(attrs)
    |> Repo.insert()
  end

  # ... toute la logique dans ce fichier
end
```

**Avantages:**
- Simplicité initiale : Moins de fichiers, moins de concepts
- Développement rapide : Pas de boilerplate patterns DDD
- Courbe apprentissage faible : Standards Phoenix bien documentés
- Générateurs Phoenix : `mix phx.gen.context` automatise création

**Inconvénients:**
- Scalabilité limitée : Contexts deviennent fat (> 500 lignes)
- Couplage fort : Logique métier mélangée avec Ecto/DB
- Tests complexes : Nécessitent DB pour tester logique métier
- Refactoring coûteux : Migration vers DDD = réécriture complète
- Pas d'apprentissage DDD : Objectif pédagogique non atteint

**Effort estimé:** Faible (patterns Phoenix standards)

**Décision:** Rejeté car ne répond pas aux objectifs d'apprentissage et anticipe mal la croissance.

---

### Option 3: ActiveRecord Pattern (Fat Models)

**Description:**
Logique métier directement dans les schemas Ecto (inspiré Ruby on Rails).

**Exemple:**
```elixir
defmodule Portfolio.Photography.Album do
  use Ecto.Schema
  import Ecto.Changeset
  alias Portfolio.Repo

  # Logique métier dans le schema
  def publish(%__MODULE__{} = album) do
    album
    |> changeset(%{published: true, published_at: DateTime.utc_now()})
    |> Repo.update()
  end

  def add_photo(%__MODULE__{} = album, photo_attrs) do
    # Logique + persistence mélangées
  end
end
```

**Avantages:**
- Logique métier proche des données
- Pattern familier (Ruby on Rails)
- Moins de fichiers que DDD

**Inconvénients:**
- Couplage fort : Logique métier couplée à persistence
- Violation SRP : Schema responsable de validation ET logique ET persistence
- Tests difficiles : Nécessitent DB même pour logique simple
- Pas idiomatique Elixir : Elixir préfère séparation fonctions/données

**Effort estimé:** Moyen

**Décision:** Rejeté car anti-pattern en Elixir et couple logique métier à infrastructure.

---

### Option 4: Anemic Domain Model (Services uniquement)

**Description:**
Structs sans comportement, toute logique dans services.

**Exemple:**
```elixir
defmodule Portfolio.Photography.Album do
  defstruct [:id, :title, :slug, :published]
  # Aucune validation, aucun comportement
end

defmodule Portfolio.Photography.AlbumService do
  def create(attrs) do
    # Toute validation + logique ici
    struct(Album, attrs)
  end
end
```

**Avantages:**
- Services testables facilement
- Séparation données/logique

**Inconvénients:**
- Anti-pattern DDD : Aucune encapsulation, invariants non garantis
- Validation dispersée : Chaque service doit valider
- Pas de rich domain model : Structs anémiques sans comportement
- Complexité services : Fat services remplacent fat models

**Effort estimé:** Moyen

**Décision:** Rejeté car anti-pattern DDD, pas d'encapsulation ni invariants garantis.

---

## Décision

L'option choisie est: **Option 1 - Domain-Driven Design (Tactical Patterns)**

### Justification

La décision est basée sur les critères suivants :

**1. Objectif d'Apprentissage (Critique)**

DDD est le cœur de l'objectif pédagogique :
- Montée en compétences pour usage professionnel
- Entraînement sur patterns tactiques (aggregates, repositories, events)
- Projet personnel = environnement sûr pour expérimenter sans pression
- Influence collègue experte (Aurore Jeremie) ayant démontré valeur DDD

CRUD simple n'atteindrait pas cet objectif d'apprentissage.

**2. Anticipation Croissance (Très important)**

Architecture DDD facilite évolutions futures :
- Ajout bounded contexts (Blog pour Tech/AMVCC)
- Extension features (galeries, tags, commentaires, favoris)
- Scaling indépendant de chaque contexte
- Refactoring localisé (changements isolés grâce à SRP)

CRUD simple deviendrait ingérable au-delà de 10-15 features.

**3. Maintenabilité Long Terme (Important)**

DDD améliore maintenabilité :
- Code auto-documenté : Ubiquitous language dans noms modules/fonctions
- Modules courts : SRP garantit modules < 300 lignes
- Séparation préoccupations : Domaine vs Infrastructure vs Application
- Facilité onboarding : Documentation `@moduledoc` explicite invariants

**4. Testabilité (Important)**

DDD facilite tests :
- Tests unitaires domaine sans DB (mocking repositories)
- Tests services isolés (orchestration)
- Tests aggregates (invariants, validations)
- Approche TDD simplifiée (test agreggate → implémentation)

Plus de tests nécessaires, mais tests plus simples (fonctions SRP).

**5. Séparation des Préoccupations (Souhaitable)**

DDD force architecture propre :
- Domaine (Album, Photographie, Projet, User) indépendant d'Ecto
- Infrastructure (Repositories, Storage) interchangeable
- Application (Services) orchestre workflows complexes
- Migration DB facilitée (abstraction repositories)

### Implémentation Tactique

**Bounded Contexts:**

**Photography** :
- Responsabilité : Gestion albums/photographies/projets, traitement images, publication
- Aggregates : Album, Photographie, Projet
- Services : PhotoUploadService, AlbumPublicationService, AlbumDeletionService, PhotoDeletionService
- Events : PhotoUploaded, AlbumPublished

**Auth** :
- Responsabilité : Authentification passwordless, sessions, utilisateurs
- Aggregates : User
- Entities : MagicLink, UserSession
- Services : MagicLinkService, SessionService, UserService
- Events : MagicLinkVerified (futur)

**Blog** (futur) :
- Responsabilité : Articles Tech/AMVCC, catégories, tags
- Aggregates : Article, Category
- Services : ArticlePublicationService
- Partage : Tech et AMVCC partagent contexte Blog (même logique métier, layouts UI différents)

**Aggregates vs Entities:**

**Photographie comme Aggregate Root** (choix débattu) :
- **Justification retenue** :
  - Cycle de vie indépendant (upload async, traitement, peut exister sans album)
  - Réutilisabilité future (photographies dans articles Blog, Projets multi-albums)
  - Granularité transactionnelle (modifier photographie ≠ verrouiller album)
- **Alternative envisagée** : Photographie comme entity enfant d'Album
  - Limiterait réutilisabilité (couplage fort Album-Photographie)
  - Complexifierait traitement async (comment référencer photographie sans album ?)
- **Note** : Choix pragmatique basé sur use case, validé par introduction Projet (ADR-016)

**Value Objects:**

Value Objects implémentés :
- **Slug** : Validation URL-safe, unicité, immutabilité
- **Email** : Validation RFC 5322, normalisation, immutabilité
- **Titre** : Validation longueur (3-200 caractères), nettoyage espaces
- **Description** : Validation longueur (10-5000 caractères), support markdown
- **Empreinte** : Hash SHA-256 16 caractères pour dédoublonnage fichiers
- **ÉtatTraitement** : Enum (pending, processing, ready, failed)
- **ExifData** : Métadonnées EXIF structurées (appareil, objectif, paramètres, GPS) - JSONB PostgreSQL

Value Objects futurs (refactoring si nécessaire) :
- **Dimensions** (width, height) : Garantir > 0
- **DateRange** (debut, fin) : Garantir debut ≤ fin ≤ today

Critère création VO : Validation/invariants complexes OU réutilisabilité forte.

**Repositories:**

Abstraction Ecto derrière repositories :
```elixir
# Interface publique (peut être behaviour future)
defmodule Portfolio.Photography.Repositories.AlbumRepository do
  def list(opts), do: # Query Ecto
  def get(id), do: # Query Ecto
  def create(attrs), do: # Insert Ecto
  # ...
end
```

Bénéfices :
- Séparation domaine (Album aggregate) / infrastructure (Ecto)
- Testabilité (mock repositories pour tests domaine)
- Migration DB facilitée (changer implémentation sans toucher domaine)

**Services Layer:**

Critère création service :
- Orchestration multi-étapes (ex: PhotoUploadService = upload + extraction EXIF + enqueue workers)
- Transactions complexes (ex: AlbumDeletionService = suppression cascade + invalidation cache)
- Coordination > 1 aggregate (ex: AlbumPublicationService = update album + publish events)

Services respectent SRP : Un service = un workflow complexe.

**Domain Events:**

Infrastructure : Phoenix.PubSub pour broadcast events.

Events actuels :
- `PhotoUploaded` → Handlers : Enqueue image processing (Oban), analytics (futur)
- `AlbumPublished` → Handlers : Invalidation cache, notifications (futur)

Events futurs :
- `MagicLinkVerified` → Audit trail, analytics
- `ArticlePublished` → Invalidation cache Blog, RSS feed

Motivations :
- Découplage bounded contexts (Photography ne connaît pas détails Auth)
- Extension sans modification (nouveau handler = nouveau subscriber PubSub)
- Audit trail (tous events loggés, event sourcing futur possible)

**Ubiquitous Language:**

Langage métier documenté dans `@moduledoc` de chaque aggregate :
- Termes clés définis (Album, Photographie, Projet, Published, Slug, Magic Link, etc.)
- Invariants explicités (ex: "Un album DOIT avoir un titre de 3-200 caractères")
- Exemples d'usage fournis

Processus :
- Définition initiale lors de création aggregate
- Évolution progressive (rigueur initiale insuffisante, amélioration continue)
- Auto-documentation (domain expert = développeur solo, pas d'experts externes)

Documentation centralisée : `docs/ddd/regles_metier.md` (implémenté 2025-11).

### Adaptation Elixir

**Elixir bien adapté à DDD** :

**Pattern Matching** :
Facilite validation et branchements métier :
```elixir
def publish(%Album{published: true}), do: {:error, :already_published}
def publish(%Album{} = album), do: # Logique publication
```

**Immutabilité** :
Garantit invariants (pas de mutation accidentelle) :
```elixir
# Aggregate immuable, transformation retourne nouvel aggregate
album = %Album{title: "Original"}
updated = %{album | title: "Updated"}  # Pas de mutation
```

**Behaviours** :
Alternative aux interfaces OOP :
```elixir
defmodule PhotoStorage do
  @callback store(path, binary) :: {:ok, path} | {:error, reason}
end

defmodule LocalStorage do
  @behaviour PhotoStorage
  def store(path, data), do: # ...
end
```

**Structs** :
Alternative aux classes, séparation données/fonctions idiomatique Elixir :
```elixir
defmodule Album do
  defstruct [:title, :slug, :published]

  def changeset(%Album{}, attrs), do: # Validation
  def publish(%Album{}), do: # Comportement
end
```

**Pas de difficulté majeure** : Elixir fonctionnel plus simple que OOP pour DDD (pas d'héritage complexe).

### Trade-offs Acceptés

**Complexité initiale accrue** :
- Plus de fichiers (aggregates, repositories, services, events vs simples contexts)
- Plus de concepts à maîtriser (bounded contexts, aggregates, value objects)
- Mitigation : Objectif = apprentissage, complexité justifiée pédagogiquement

**Verbosité (boilerplate)** :
- Repositories wrappent Ecto (code répétitif)
- Services orchestrent workflows (parfois overkill pour opérations simples)
- Mitigation : Approche pragmatique, ne pas sur-ingénierer (VO minimaux, services si réelle orchestration)

**Développement plus lent initialement** :
- Setup patterns DDD vs CRUD direct
- Courbe apprentissage ralentit features initiales
- Acceptable : Projet personnel sans deadline, apprentissage prioritaire

**Zones d'incertitude (débutant DDD)** :
- Photographie comme aggregate vs entity enfant ? (choix retenu : aggregate pour réutilisabilité)
- Quels Value Objects créer ? (approche pragmatique : validation complexe OU réutilisabilité)
- Services vs logique dans aggregates ? (critère orchestration multi-étapes)
- Documentation : Patterns DDD documentés dans `docs/ddd/` (implémenté 2025-11)

## Conséquences

### Positives

- **Apprentissage réussi** : Entraînement DDD sur projet réel, montée en compétences
- **Architecture scalable** : Ajout features/contextes sans refonte majeure
- **Testabilité excellente** : Tests domaine sans DB, mocking facilité, TDD simplifié
- **Maintenabilité** : Code auto-documenté, modules courts (SRP), refactoring facilité
- **Séparation préoccupations** : Domaine indépendant infrastructure, migration DB possible
- **Documentation vivante** : Ubiquitous language dans code, `@moduledoc` explicites
- **Découplage** : Bounded contexts isolés, communication via events
- **Facilité refactoring** : Changements localisés (SRP), impact limité
- **Expérimentation** : Patterns testables sans risque (projet personnel)

### Négatives

- **Courbe apprentissage** : Ralentissement développement initial (patterns à maîtriser)
  - Gestion : Acceptable pour objectif pédagogique, documentation progressive
- **Verbosité** : Plus de fichiers/code que CRUD simple
  - Gestion : Trade-off maintenabilité long terme vs rapidité court terme
- **Zones d'incertitude** : Choix architecturaux débattables (Photo aggregate, VO minimaux)
  - Surveillance : Documentation décisions, refactoring si patterns inadaptés
  - Gestion : Approche pragmatique, ne pas dogmatiser DDD
- **Over-engineering possible** : Risque de patterns excessifs pour features simples
  - Surveillance : Critère pragmatique (service si orchestration complexe, VO si validation complexe)

### Neutres

- **Plus de tests nécessaires** : Tests aggregates + repositories + services
  - Mais tests plus simples (fonctions SRP, mocking facilité)
- **Patterns Elixir vs OOP** : Adaptation idiomes fonctionnels
  - Elixir bien adapté (pattern matching, immutabilité, behaviours)
- **Documentation extensive** : `@moduledoc` pour chaque module
  - Effort initial, bénéfice long terme (onboarding, ubiquitous language)

## Plan d'Action

1. **Phase 1: Bounded Contexts Initiaux** ✅
   - Context Photography (Album, Photographie, Projet aggregates)
   - Context Auth (User aggregate, MagicLink/Session entities)
   - Context User (Utilisateur aggregate)
   - Context Communication (Notification, Newsletter, Abonné aggregates)
   - Séparation claire domaine/infrastructure

2. **Phase 2: Tactical Patterns** ✅
   - Repositories (AlbumRepository, PhotographieRepository, ProjetRepository, UserRepository)
   - Value Objects (Slug, Email, Titre, Description, Empreinte, ÉtatTraitement, ExifData)
   - Services (PhotoUploadService, AlbumPublicationService, AlbumDeletionService, PhotoDeletionService, MagicLinkService, SessionService, UserService)
   - Domain Events (PhotoUploaded, AlbumPublished)

3. **Phase 3: Query Objects** ✅
   - AlbumQuery, PhotographieQuery pour requêtes composables
   - CQRS lite (séparation commands/queries)

4. **Phase 4: Event Handlers** ✅
   - Handlers pour PhotoUploaded (Oban workers)
   - Handlers pour AlbumPublished (invalidation cache)

5. **Phase 5: Documentation DDD** ✅
   - Ubiquitous language centralisé (`docs/ddd/regles_metier.md`)
   - Architecture DDD détaillée (`docs/ddd/architecture_ddd.md`)
   - ADRs pour décisions architecturales majeures

6. **Phase 6: Refactoring Patterns** (Futur, si nécessaire)
   - ✅ Validation Photographie comme aggregate (confirmée avec introduction Projet)
   - ✅ Value Objects ajoutés (Titre, Description, Empreinte, ÉtatTraitement, ExifData)
   - 🔄 Séparation Domain Services vs Application Services si besoin clarification
   - 🔄 Specifications pattern si logique filtrage complexe
   - 🔄 Ajout Value Objects futurs (Dimensions, DateRange) si pertinents

7. **Phase 7: Context Blog** (Futur)
   - Bounded Context Blog pour Tech/AMVCC
   - Aggregates Article, Category
   - Partage contexte métier, séparation layouts UI

**Critères de succès:**
-  2+ bounded contexts implémentés (Photography, Auth)
-  Aggregates avec invariants documentés
-  Repositories abstrayant Ecto
-  Services respectant SRP (< 300 lignes)
-  Domain Events avec PubSub
-  Tests domaine sans DB (mocking repositories)
-  Documentation `@moduledoc` complète
- 🔄 Ubiquitous language documenté centralement (en cours)

**Rollback plan:**

Si DDD s'avère inadapté (peu probable) :
1. Identifier pain points : Verbosité excessive ? Patterns inappropriés ?
2. Simplification graduelle :
   - Option A : Merger repositories dans contexts (réduire abstraction)
   - Option B : Simplifier services (logique dans aggregates si pas d'orchestration)
   - Option C : Supprimer Value Objects excessifs (garder Slug/Email critiques)
3. Dernier recours : Migration vers CRUD simple
   - Garder bounded contexts (séparation utile)
   - Supprimer repositories/services/events
   - Logique directement dans contexts Phoenix standards
   - Effort : 2-3 semaines refactoring

## Références

- [Domain-Driven Design - Eric Evans](https://www.domainlanguage.com/ddd/)
- [Implementing Domain-Driven Design - Vaughn Vernon](https://vaughnvernon.com/)
- [Phoenix Contexts Guide](https://hexdocs.pm/phoenix/contexts.html)
- [Elixir School - OTP Patterns](https://elixirschool.com/en/lessons/advanced/otp_concurrency)

Conférences :
- VoxxedDays Geneva 2024 - Présentations DDD
- Devoxx Paris 2024 - Talks architecture

Influence professionnelle :
- Aurore Jeremie - Mentor DDD ayant démontré valeur en production

Documentation projet connexe :
- `docs/ddd/README.md` (Vue d'ensemble architecture DDD)
- `docs/ddd/bounded_contexts.md` (Description détaillée contextes)
- `docs/ddd/ubiquitous_language.md` (Glossaire métier)
- `docs/architecture/clean_architecture_layers.md` (Implémentation Clean Architecture)

## Notes

### État Actuel (Novembre 2024)

**Bounded Contexts implémentés:**
-  Photography (Album, Photographie, Projet aggregates)
-  Auth (MagicLink, Session entities)
-  User (Utilisateur aggregate)
-  Communication (Notification, Newsletter, Abonné aggregates)
- 🔄 Blog (futur, pour Tech/AMVCC)

**Patterns appliqués:**
-  Aggregates avec invariants documentés
-  Repositories (abstraction Ecto)
-  Value Objects (Slug, Email)
-  Services (Upload, Publication, Deletion, MagicLink, Session, User)
-  Domain Events (PhotoUploaded, AlbumPublished)
-  Event Handlers (PubSub)
-  Query Objects (CQRS lite)

**Satisfaction:**
- Très satisfait du choix DDD pour apprentissage
- Architecture scalable validée (ajout features sans refonte)
- Testabilité confirmée (tests domaine sans DB fonctionnent bien)
- Maintenabilité bonne (modules courts, refactoring facile)

**Zones d'amélioration:**
- ✅ Documentation ubiquitous language centralisée (`docs/ddd/regles_metier.md` - 2025-11)
- ✅ Value Objects implémentés (Titre, Description, Empreinte, ÉtatTraitement, ExifData)
- 🔄 Clarification Domain Services vs Application Services (en cours)
- 🔄 Patterns avancés à explorer (Specifications, Factories)

### Lessons Learned

**Surprises positives:**
- Elixir très adapté à DDD (pattern matching, immutabilité, behaviours)
- Services facilitent SRP (modules < 300 lignes facilement maintenus)
- Domain Events apportent découplage réel (ajout handlers sans modifier domaine)
- Tests domaine sans DB très efficaces (mocking repositories simple)

**Confirmations:**
- CRUD simple aurait été ingérable dès 10-15 features
- Apprentissage DDD nécessite pratique (livres insuffisants, projet réel indispensable)
- Trade-off verbosité/maintenabilité positif long terme

**Ajustements:**
- Approche pragmatique nécessaire (ne pas dogmatiser DDD)
- Value Objects minimaux suffisants (pas de sur-ingénierie)
- Services si réelle orchestration (pas pour chaque opération CRUD)

**Accompagnement souhaité:**
- ✅ Revue patterns appliqués (Photographie aggregate validé, VO enrichis, services cohérents)
- 🔄 Recommandations refactoring si patterns inadaptés (en cours)
- 🔄 Exploration patterns avancés (Specifications, Factories, Sagas)

### Évolutions Futures

**Context Blog:**
Bounded context Blog partagé pour Tech et AMVCC :
- Aggregates : Article, Category, Tag
- Services : ArticlePublicationService
- Events : ArticlePublished
- Partage logique métier, séparation layouts UI (tech., amvcc. sous-domaines)

**Patterns avancés à explorer:**
- **Specifications** : Logique filtrage complexe réutilisable
- **Factories** : Construction aggregates complexes
- **Domain Services vs Application Services** : Clarification distinction
- **Event Sourcing** : Si audit trail exhaustif nécessaire (actuellement events éphémères)

**Refactoring potentiels:**
- ✅ Photographie : Validé comme aggregate (réutilisabilité Blog + Projet)
- ✅ Value Objects : Ajoutés (Titre, Description, Empreinte, ÉtatTraitement, ExifData)
- 🔄 Value Objects futurs : Dimensions, DateRange si besoin avéré
- 🔄 Repositories : Behaviours explicites pour interfaces

---

**Participants à la décision:**
- Thibault San - Développeur Solo

**Influences:**
- Aurore Jeremie - Mentor DDD professionnel

**Révisé par:**
- Thibault San - 2025-11-10
