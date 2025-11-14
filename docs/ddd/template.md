# [Nom du Bounded Context] - Architecture DDD

Bounded Context: [Nom]
Statut: [En cours / Stable / En refactoring]
Date: [YYYY-MM-DD]

---

## 1. DDD Stratégique

### 1.1 Vue d'Ensemble du Bounded Context

Description du rôle et de la responsabilité de ce Bounded Context dans le système global.

Responsabilités principales:
- Responsabilité 1
- Responsabilité 2
- Responsabilité 3

Limites du contexte:
- Ce qui est INCLUS dans ce contexte
- Ce qui est EXCLU de ce contexte

### 1.2 Ubiquitous Language

Vocabulaire métier partagé entre développeurs et experts métier:

Terme | Définition | Synonymes à éviter
---|---|---
TermeMetier1 | Définition précise du concept métier | Terme ambigu, Autre terme
TermeMetier2 | Définition avec exemple concret | Ancien terme, Terme technique
TermeMetier3 | Définition alignée avec le métier | Mauvais terme

Règles linguistiques:
- Règle 1: Toujours utiliser X au lieu de Y
- Règle 2: Distinguer clairement A de B
- Règle 3: Éviter les termes techniques quand un terme métier existe

### 1.3 Relations avec Autres Bounded Contexts

#### Context Map

```
[Ce Context] ──relation──> [Autre Context]
```

Type de relation | Contexte cible | Description | Direction des dépendances
---|---|---|---
Customer-Supplier | ContextB | Description de la relation | Nous dépendons de ContextB
Shared Kernel | ContextC | Noyau partagé pour X | Bidirectionnel
Anti-Corruption Layer | ContextD | ACL pour protéger notre modèle | Nous consommons ContextD
Conformist | ContextE | Suit le modèle de ContextE | Nous suivons ContextE

#### Intégrations

Contexte | Mode d'intégration | Données échangées | Fréquence
---|---|---|---
ContextB | Domain Events | EventX, EventY | Temps réel
ContextC | API REST | DTO ResourceZ | À la demande
ContextD | Message Queue | CommandA | Asynchrone

### 1.4 Domain Events

Événements publiés par ce contexte:

Événement | Déclencheur | Données | Consommateurs
---|---|---|---
EntityCreated | Création entité X | entity_id, attributes | ContextB, ContextC
EntityUpdated | Mise à jour entité X | entity_id, changes | ContextB
EntityDeleted | Suppression entité X | entity_id | ContextB, ContextC

Événements consommés:

Événement | Producteur | Action | Impact
---|---|---|---
ExternalEventA | ContextY | Synchroniser données | Mise à jour entité locale
ExternalEventB | ContextZ | Déclencher workflow | Création nouvelle entité

### 1.5 Sous-Domaines

Type de sous-domaine: [Core / Supporting / Generic]

Justification:
- Pourquoi ce contexte est classé ainsi
- Impact sur les priorités de développement
- Niveau de complexité métier

Évolution prévue:
- Court terme (3-6 mois): Évolution X
- Moyen terme (6-12 mois): Évolution Y
- Long terme (1-2 ans): Évolution Z

---

## 2. DDD Tactique

### 2.1 Aggregates

#### Aggregate 1: [Nom]

Aggregate Root: `EntityX`

Responsabilités:
- Garantir invariant métier 1
- Garantir invariant métier 2
- Coordonner EntitéA et EntitéB

Entités:
```
EntityX (Aggregate Root)
  ├── EntityA (Entité enfant)
  └── EntityB (Entité enfant)
```

Invariants métier:
1. Invariant 1: Description précise de la règle métier
2. Invariant 2: Conditions qui doivent toujours être vraies
3. Invariant 3: Contraintes d'intégrité

Limite transactionnelle:
- Tout changement dans cet agrégat = 1 transaction
- Modifications atomiques garanties
- Cohérence forte à l'intérieur de l'agrégat

Fichier: `lib/portfolio/[context]/[aggregate].ex`

#### Aggregate 2: [Nom]

[Répéter structure ci-dessus]

### 2.2 Entities

Entité | Aggregate Parent | Identité | Cycle de vie
---|---|---|---
EntityA | AggregateX | UUID | Créée → Active → Archivée
EntityB | AggregateX | ID composite | Créée → Publiée → Supprimée
EntityC | AggregateY | Slug unique | Draft → Published → Deleted

Caractéristiques:
- EntityA: Possède identité unique persistante, mutable
- EntityB: Identité composite (parent_id + position)
- EntityC: Identité basée slug généré depuis attribut métier

### 2.3 Value Objects

Value Object | Responsabilité | Validation | Immutabilité
---|---|---|---
EmailAddress | Encapsuler email valide | Format RFC 5322, max 160 chars | Oui
Slug | URL-friendly identifier | Lowercase, hyphens, unique | Oui
DateRange | Période avec début et fin | Fin > Début | Oui
Money | Montant + devise | Positif, 2 décimales | Oui

Implémentation:
```elixir
defmodule Context.ValueObject do
  @type t :: %__MODULE__{
    field1: String.t(),
    field2: integer()
  }
  
  defstruct [:field1, :field2]
  
  def new(field1, field2) do
    with :ok <- validate_field1(field1),
         :ok <- validate_field2(field2) do
      {:ok, %__MODULE__{field1: field1, field2: field2}}
    end
  end
end
```

Fichier: `lib/portfolio/[context]/value_objects/[name].ex`

### 2.4 Domain Services

Service | Responsabilité | Raison d'être | Dépendances
---|---|---|---
ServiceA | Opération complexe multi-agrégats | Ne rentre pas naturellement dans un agrégat | RepoX, RepoY
ServiceB | Calcul métier sans état | Logique partagée entre agrégats | Aucune
ServiceC | Orchestration workflow | Coordonner plusieurs agrégats | RepoA, EventBus

Principe:
- Service sans état (stateless)
- Opération ne correspond pas à une entité naturelle
- Coordination entre plusieurs agrégats

Fichier: `lib/portfolio/[context]/services/[name].ex`

### 2.5 Repositories

Repository | Aggregate géré | Backend | Responsabilités
---|---|---|---
AggregateXRepository | AggregateX | Ecto/PostgreSQL | CRUD + queries métier
AggregateYRepository | AggregateY | Ecto/PostgreSQL | CRUD + queries complexes

Interface:
```elixir
defmodule Context.Repositories.AggregateXRepository do
  alias Context.AggregateX
  
  @type scope :: %{user: User.t()}
  
  # Lecture
  @spec get(scope(), id :: String.t()) :: {:ok, AggregateX.t()} | {:error, :not_found}
  @spec list(scope(), opts :: Keyword.t()) :: [AggregateX.t()]
  @spec list_by_status(scope(), status :: atom()) :: [AggregateX.t()]
  
  # Écriture
  @spec create(scope(), attrs :: map()) :: {:ok, AggregateX.t()} | {:error, Ecto.Changeset.t()}
  @spec update(scope(), AggregateX.t(), attrs :: map()) :: {:ok, AggregateX.t()} | {:error, Ecto.Changeset.t()}
  @spec delete(scope(), AggregateX.t()) :: {:ok, AggregateX.t()} | {:error, Ecto.Changeset.t()}
end
```

Principe Repository Pattern:
- Abstraction de la persistance
- Collection-like interface
- Queries métier (pas SQL exposé)
- Toujours retourner des Aggregates complets

Fichier: `lib/portfolio/[context]/repositories/[aggregate]_repository.ex`

### 2.6 Factories

Factory | Responsabilité | Complexité | Fichier
---|---|---|---
AggregateXFactory | Créer AggregateX avec dépendances | Initialisation complexe multi-étapes | `factories/aggregate_x_factory.ex`
EntityBuilder | Builder pattern pour Entity | Construction progressive avec validation | `builders/entity_builder.ex`

Utilisation:
- Factory: Création complexe nécessitant logique métier
- Builder: Construction progressive avec validation à chaque étape
- Simple constructor: Pour objets simples (utiliser new/1 directement)

### 2.7 Domain Events (Tactique)

Implémentation événements:

```elixir
defmodule Context.DomainEvents.EntityCreated do
  @enforce_keys [:entity_id, :occurred_at]
  defstruct [:entity_id, :data, :occurred_at, :metadata]
  
  @type t :: %__MODULE__{
    entity_id: String.t(),
    data: map(),
    occurred_at: DateTime.t(),
    metadata: map()
  }
end
```

Event Handlers:

Handler | Événement | Action | Type
---|---|---|---
SyncHandler | EntityCreated | Mise à jour cache | Synchrone
AsyncHandler | EntityDeleted | Nettoyage fichiers | Asynchrone (Oban)
NotificationHandler | EntityPublished | Envoi notifications | Asynchrone

Fichiers:
- Events: `lib/portfolio/[context]/domain_events/[event_name].ex`
- Handlers: `lib/portfolio/[context]/event_handlers/[handler_name].ex`

### 2.8 Specifications

Pattern Specification pour règles métier complexes réutilisables:

Specification | Règle métier | Utilisation
---|---|---
PublishableSpec | Entity peut être publiée (validations complexes) | Validation avant publication
EligibleForDeleteSpec | Entity peut être supprimée (dépendances OK) | Validation avant suppression
VisibleToUserSpec | Entity visible pour user donné (permissions) | Filtrage queries

Implémentation:
```elixir
defmodule Context.Specifications.PublishableSpec do
  def satisfied_by?(entity) do
    entity.status == :draft and
    entity.required_field != nil and
    Enum.count(entity.items) >= 1
  end
end
```

Fichier: `lib/portfolio/[context]/specifications/[name]_spec.ex`

---

## 3. Architecture des Répertoires

```
lib/portfolio/[context]/
├── [context].ex                    # Façade du contexte (API publique)
├── aggregates/
│   ├── aggregate_x.ex              # Aggregate Root X
│   └── aggregate_y.ex              # Aggregate Root Y
├── entities/
│   ├── entity_a.ex                 # Entité A
│   └── entity_b.ex                 # Entité B
├── value_objects/
│   ├── email.ex                    # Value Object Email
│   └── slug.ex                     # Value Object Slug
├── services/
│   ├── service_a.ex                # Domain Service A
│   └── service_b.ex                # Domain Service B
├── repositories/
│   ├── aggregate_x_repository.ex   # Repository pour Aggregate X
│   └── aggregate_y_repository.ex   # Repository pour Aggregate Y
├── queries/
│   ├── aggregate_x_query.ex        # Query Object pour queries complexes
│   └── aggregate_y_query.ex
├── domain_events/
│   ├── entity_created.ex           # Domain Event
│   └── entity_updated.ex
├── event_handlers/
│   ├── sync_handler.ex             # Event Handler synchrone
│   └── async_handler.ex            # Event Handler asynchrone
├── specifications/
│   └── publishable_spec.ex         # Specification pattern
├── factories/
│   └── aggregate_x_factory.ex      # Factory pattern
└── policies/
    └── authorization_policy.ex      # Policies d'autorisation
```

---

## 4. Règles Métier et Invariants

### 4.1 Invariants Globaux du Contexte

Invariant | Niveau | Garantie | Responsable
---|---|---|---
Invariant 1 | Agrégat | Transaction DB | AggregateX.validate/1
Invariant 2 | Contexte | Ecto.Multi | Service layer
Invariant 3 | Inter-contexte | Eventual consistency | Domain Events

### 4.2 Règles Métier Documentées

Règle | Description | Implémentation | Tests
---|---|---|---
Règle 1 | Description précise | `aggregate_x.ex:45` | `aggregate_x_test.exs:23`
Règle 2 | Condition et conséquence | `service_a.ex:78` | `service_a_test.exs:56`
Règle 3 | Validation complexe | `specifications/spec_x.ex:12` | `spec_x_test.exs:34`

---

## 5. Patterns et Conventions

### 5.1 Conventions de Nommage

Élément | Convention | Exemple
---|---|---
Aggregate Root | Nom métier singulier | `Album`, `Photo`, `User`
Entity | Nom métier singulier | `Variant`, `Session`
Value Object | Nom concept métier | `Slug`, `DateRange`, `EmailAddress`
Repository | `[Aggregate]Repository` | `AlbumRepository`, `PhotoRepository`
Service | `[Action][Entity]Service` | `PhotoUploadService`, `AlbumPublicationService`
Domain Event | `[Entity][Action]` | `AlbumPublished`, `PhotoUploaded`
Event Handler | `[Entity][Action]Handler` | `AlbumPublishedHandler`
Query Object | `[Aggregate]Query` | `AlbumQuery`, `PhotoQuery`

### 5.2 Patterns Utilisés

Pattern | Usage | Fichier type
---|---|---
Repository | Abstraction persistance | `repositories/[name]_repository.ex`
Query Object | Queries complexes réutilisables | `queries/[name]_query.ex`
Service Layer | Workflows complexes | `services/[name]_service.ex`
Domain Events | Communication asynchrone | `domain_events/[name].ex`
Specification | Règles métier réutilisables | `specifications/[name]_spec.ex`
Factory | Construction complexe | `factories/[name]_factory.ex`
Value Object | Concepts métier immuables | `value_objects/[name].ex`

### 5.3 Anti-Patterns à Éviter

Anti-pattern | Problème | Solution
---|---|---
Anemic Domain Model | Logique métier dans services, entités = simples structures | Enrichir entités avec comportements métier
God Aggregate | Agrégat trop large | Découper en plusieurs agrégats cohérents
Transaction Script | Logique procédurale sans modèle | Utiliser Aggregates + Services
Leaky Abstraction | Ecto exposed dans API publique | Repository pattern + DTO si nécessaire

---

## 6. Testing Strategy

### 6.1 Tests Unitaires

Cible | Focale | Fichier
---|---|---
Aggregates | Invariants métier | `test/[context]/aggregates/[name]_test.exs`
Value Objects | Validation | `test/[context]/value_objects/[name]_test.exs`
Domain Services | Logique métier | `test/[context]/services/[name]_test.exs`
Specifications | Règles métier | `test/[context]/specifications/[name]_test.exs`

### 6.2 Tests Intégration

Cible | Focale | Fichier
---|---|---
Repositories | Persistance | `test/[context]/repositories/[name]_test.exs`
Context Façade | API publique | `test/[context]/[context]_test.exs`
Event Handlers | Événements | `test/[context]/event_handlers/[name]_test.exs`
Workflows | Scénarios bout-en-bout | `test/[context]/workflows/[name]_test.exs`

### 6.3 Coverage Attendu

Module | Target Coverage | Justification
---|---|---
Aggregates | 95%+ | Cœur métier critique
Value Objects | 90%+ | Validation essentielle
Services | 85%+ | Workflows importants
Repositories | 80%+ | Abstraction testée
Event Handlers | 75%+ | Handlers testés

---

## 7. Évolution et Dette Technique

### 7.1 Évolutions Prévues

Phase | Période | Changements
---|---|---
Phase 1 | Q1 2026 | Ajout AggregateZ, nouveau workflow X
Phase 2 | Q2 2026 | Refactoring ServiceA, extraction sous-contexte
Phase 3 | Q3 2026 | Migration vers Event Sourcing partiel

### 7.2 Dette Technique Identifiée

Dette | Impact | Priorité | Plan correction
---|---|---|---
Aggregate trop large | Maintenabilité moyenne | Haute | Découper en 2 agrégats Q1 2026
Manque specifications | Code dupliqué | Moyenne | Extraire specs Q2 2026
Event handlers sync | Performance | Basse | Migrer async Q3 2026

### 7.3 Refactorings Envisagés

Refactoring | Raison | Effort | Risque
---|---|---|---
Split AggregateX | Trop de responsabilités | 5 jours | Moyen
Extract ServiceY | Code dupliqué | 2 jours | Faible
Introduce EventSourcing | Audit trail requis | 10 jours | Élevé

---

## 8. Références

### 8.1 Documentation Connexe

- ADR-003: Domain-Driven Design Adoption
- ADR-010: Architecture DDD générale
- ADR-030: Event-Driven Context Communication
- ADR-032: Repository Pattern Data Access
- ADR-033: Query Objects Composable Queries
- ADR-034: Value Objects Domain Concepts
- ADR-035: Ecto Multi Atomic Transactions

### 8.2 Ressources Externes

- Domain-Driven Design, Eric Evans (Blue Book)
- Implementing Domain-Driven Design, Vaughn Vernon (Red Book)
- Domain-Driven Design Distilled, Vaughn Vernon
- Patterns, Principles, and Practices of Domain-Driven Design, Scott Millett

### 8.3 Code Base

Répertoire principal: `lib/portfolio/[context]/`

Fichiers clés:
- Façade: `lib/portfolio/[context].ex`
- Aggregates: `lib/portfolio/[context]/aggregates/*.ex`
- Repositories: `lib/portfolio/[context]/repositories/*.ex`
- Services: `lib/portfolio/[context]/services/*.ex`

---

Date de création: [YYYY-MM-DD]
Dernière révision: [YYYY-MM-DD]
Auteur: [Nom]
