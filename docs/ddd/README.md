# Documentation Domain-Driven Design - Portfolio

Cette documentation présente l'architecture Domain-Driven Design (DDD) du projet Portfolio, couvrant les aspects stratégiques et tactiques de chaque Bounded Context.

---

## Vue d'Ensemble Architecture

Le projet Portfolio implémente une architecture DDD avec 4 Bounded Contexts:

1. **Photography** (Core Domain) - Gestion des albums et photos du portfolio
2. **Auth** (Supporting Domain) - Authentification passwordless et sessions
3. **User** (Supporting Domain) - Gestion des utilisateurs et permissions
4. **Communication** (Supporting Domain) - Notifications et newsletters

### Principes Architecturaux

- Séparation stricte des Bounded Contexts
- Communication via Domain Events (asynchrone, découplée)
- Clean Architecture en couches (Domain, Application, Infrastructure)
- Ubiquitous Language partagé entre technique et métier
- Aggregates pour garantir invariants métier
- Repository Pattern pour abstraction persistance

---

## Documents Disponibles

### 1. Vue d'Ensemble (`001_vue_ensemble.md`)

Vue d'ensemble complète de l'architecture DDD du projet.

**Contenu:**
- Architecture des 4 Bounded Contexts
- Context Map et relations inter-contexts
- 44 Business Rules complètes (PM, PA, PU, PC, RT)
- Ubiquitous Language global
- Patterns architecturaux appliqués
- Incohérences actuelles et plan de migration

**Audience:** Architectes, chefs de projet, nouveaux développeurs.

### 2. Photography Context (`002_photography_context.md`)

Documentation complète du Bounded Context Photography (Core Domain).

**Contenu:**
- 13 Business Rules (PM-001 à PM-013)
- Aggregates: Photographie, Album, Projet
- Domain Services: PhotoUploadService, AlbumPublicationService, ProjetPublicationService
- Domain Events: PhotoUploaded, AlbumPublished, ProjetPublié
- Patterns: Composite (projets hiérarchiques), Soft Delete, N-N

**Liens ADRs connexes:**
- ADR-010: Storage Local vs Cloud
- ADR-011: Image Processing Vix Libvips
- ADR-013: Async Image Processing Oban
- ADR-014: Hash-based File Deduplication
- ADR-016: Composite Pattern Projets Hiérarchiques

**Audience:** Développeurs travaillant sur la gestion des albums/photos, architectes.

### 3. Auth Context (`003_auth_context.md`)

Documentation complète du Bounded Context Auth (Supporting Domain).

**Contenu:**
- 7 Business Rules (PA-001 à PA-007)
- Aggregates: MagicLink, Session
- Domain Services: MagicLinkService, SessionService
- Domain Events: MagicLinkRequested, MagicLinkVerified, SessionCreated
- Sécurité: Rate limiting, expiration, tokens crypto

**Liens ADRs connexes:**
- ADR-020: Magic Link Passwordless Auth
- ADR-021: RBAC Role-Based Access Control
- ADR-022: Session Management
- ADR-023: Rate Limiting
- ADR-024: CSRF Protection
- ADR-025: Email Validation

**Audience:** Développeurs travaillant sur l'authentification, architectes, sécurité.

### 4. User Context (`004_user_context.md`)

Documentation complète du Bounded Context User (Supporting Domain).

**Contenu:**
- 6 Business Rules (PU-001 à PU-006)
- Aggregate: Utilisateur
- Value Objects: Email, Rôle, Statut
- Domain Events: UtilisateurCréé, UtilisateurSuspendu
- Règles RBAC: admin/user, protection dernier admin

**Liens ADRs connexes:**
- ADR-021: RBAC
- ADR-025: Email Validation

**Audience:** Développeurs travaillant sur la gestion utilisateurs, sécurité.

### 5. Communication Context (`005_communication_context.md`)

Documentation complète du Bounded Context Communication (Supporting Domain).

**Contenu:**
- 10 Business Rules (PC-001 à PC-010)
- Aggregates: Notification, Newsletter, Abonné
- Domain Services: NotificationService, NewsletterService
- Domain Events: NotificationEnvoyée, NewsletterEnvoyée
- RGPD: Double opt-in, données minimales, droit effacement

**Liens ADRs connexes:**
- ADR-030: Event-Driven Context Communication
- ADR-041: Oban Background Jobs

**Audience:** Développeurs travaillant sur notifications/newsletters, conformité RGPD.

### 6. Template DDD (`template.md`)

Template complet pour documenter un Bounded Context incluant:
- DDD Stratégique (Context Map, Ubiquitous Language, Domain Events)
- DDD Tactique (Aggregates, Entities, Value Objects, Services, Repositories)
- Architecture répertoires, règles métier, patterns, tests
- Évolution et dette technique

**Usage:** Utiliser ce template pour documenter tout nouveau Bounded Context.

---

## Navigation Rapide

### Par Sujet

#### Business Rules (44 au total)
- Photography: [PM-001 à PM-013](002_photography_context.md#règles-métier-invariants) (13 règles)
- Auth: [PA-001 à PA-007](003_auth_context.md#règles-métier-invariants) (7 règles)
- User: [PU-001 à PU-006](004_user_context.md#règles-métier-invariants) (6 règles)
- Communication: [PC-001 à PC-010](005_communication_context.md#règles-métier-invariants) (10 règles)
- Transverse: [RT-001 à RT-008](001_vue_ensemble.md#transverse) (8 règles)

#### Aggregates
- Photography: [Photographie, Album, Projet](002_photography_context.md#diagrammes-aggregates-détaillés)
- Auth: [MagicLink, Session](003_auth_context.md#architecture)
- User: [Utilisateur](004_user_context.md#architecture)
- Communication: [Notification, Newsletter, Abonné](005_communication_context.md#architecture)

#### Domain Services
- Photography: [PhotoUploadService, AlbumPublicationService](002_photography_context.md#domain-services)
- Auth: [MagicLinkService, SessionService](003_auth_context.md#domain-services)
- User: [UserService](004_user_context.md#domain-services)
- Communication: [NotificationService, NewsletterService](005_communication_context.md#domain-services)

#### Domain Events
- Photography: [AlbumPublished, PhotoUploaded, ProjetPublié](002_photography_context.md#domain-events)
- Auth: [MagicLinkRequested, MagicLinkVerified, SessionCreated](003_auth_context.md#domain-events)
- User: [UtilisateurCréé, UtilisateurSuspendu](004_user_context.md#domain-events)
- Communication: [NotificationEnvoyée, NewsletterEnvoyée](005_communication_context.md#domain-events)

---

## Context Map

Relations entre Bounded Contexts:

```
┌─────────────────────────────────────────────────────────────┐
│                     Photography Context                     │
│                      (Core Domain)                          │
│                                                             │
│  Aggregates: Album, Photo, Projet                          │
│  Events: AlbumPublished, PhotoUploaded, ProjetPublié       │
│  BR: PM-001 à PM-013 (13 règles)                           │
└─────────────────────────────────────────────────────────────┘
          │                                      │
          │ Domain Events                        │ user_id
          │ Publisher-Subscriber                 │ Customer-Supplier
          ↓                                      ↓
┌──────────────────┐                    ┌─────────────────────┐
│ Communication    │                    │   User Context      │
│   Context        │                    │   (Supporting)      │
│  (Supporting)    │                    │                     │
│                  │                    │  Aggregate: User    │
│  Aggregates:     │                    │  BR: PU-001 à       │
│  - Notification  │                    │       PU-006        │
│  - Newsletter    │                    └─────────────────────┘
│  - Abonné        │                             │
│  BR: PC-001 à    │                             │ user_id
│       PC-010     │                             │ Customer-Supplier
└──────────────────┘                             ↓
                                        ┌─────────────────────┐
                                        │   Auth Context      │
                                        │   (Supporting)      │
                                        │                     │
                                        │  Aggregates:        │
                                        │  - MagicLink        │
                                        │  - Session          │
                                        │  BR: PA-001 à       │
                                        │       PA-007        │
                                        └─────────────────────┘
```

Type de relations:
- **Customer-Supplier**: Photography/Communication dépendent de User pour user_id
- **Publisher-Subscriber**: Photography publie événements, Communication souscrit
- **Anti-Corruption Layer**: Photography utilise ACL pour Storage et CDN externes

---

## Ubiquitous Language Global

Termes transversaux utilisés dans plusieurs contextes:

Terme | Définition | Contextes
---|---|---
Aggregate | Cluster d'entités avec frontière transactionnelle | Photography, Auth, User, Communication
Entity | Objet avec identité persistante | Photography, Auth, User, Communication
Value Object | Objet immuable sans identité propre | Photography, Auth, User, Communication
Repository | Abstraction collection pour persistence | Photography
Domain Service | Opération métier sans état naturel | Photography, Auth, User, Communication
Domain Event | Notification asynchrone de changement d'état | Photography, Auth, User, Communication
Scope | Contexte d'exécution incluant utilisateur courant | Photography, Auth

---

## Règles et Conventions Projet

### Nommage

Élément | Convention | Exemple
---|---|---
Bounded Context | CamelCase singulier | `Photography`, `Auth`
Aggregate Root | Nom métier singulier | `Album`, `User`
Entity | Nom métier singulier | `Photo`, `MagicLink`
Value Object | Nom concept | `Slug`, `Email`
Repository | `[Aggregate]Repository` | `AlbumRepository`
Domain Service | `[Action][Entity]Service` | `PhotoUploadService`
Domain Event | `[Entity][Action]` (passé) | `AlbumPublished`
Event Handler | `[Entity][Action]Handler` | `AlbumPublishedHandler`
Query Object | `[Aggregate]Query` | `AlbumQuery`

### Fichiers

Convention | Chemin | Exemple
---|---|---
Context façade | `lib/portfolio/[context].ex` | `lib/portfolio/photography.ex`
Aggregate | `lib/portfolio/[context]/[name].ex` | `lib/portfolio/photography/album.ex`
Repository | `lib/portfolio/[context]/repositories/` | `lib/portfolio/photography/repositories/album_repository.ex`
Value Object | `lib/portfolio/[context]/value_objects/` | `lib/portfolio/photography/value_objects/slug.ex`
Domain Service | `lib/portfolio/services/[context]/` | `lib/portfolio/services/photography/photo_upload_service.ex`
Domain Event | `lib/portfolio/[context]/events.ex` | `lib/portfolio/photography/events.ex`
Event Handler | `lib/portfolio/[context]/event_handlers/` | `lib/portfolio/photography/event_handlers/album_published_handler.ex`

---

## Résumé Architecture

### Métriques par Contexte

Métrique | Photography | Auth | User | Communication
---|---|---|---|---
Business Rules | 13 | 7 | 6 | 10
Aggregates | 3 | 2 | 1 | 3
Domain Services | 4 | 2 | 1 | 2
Domain Events | 5+ | 4 | 2 | 2
Patterns appliqués | Composite, N-N, Soft Delete | Rate Limiting, Sessions | RBAC, Email VO | RGPD, Async

### Classification Domaines

Contexte | Type | Justification | Priorité
---|---|---|---
Photography | Core Domain | Différenciation métier, valeur client | Très haute
Auth | Supporting Domain | Support Core, commodité | Haute
User | Supporting Domain | Support Auth/Photography | Haute
Communication | Supporting Domain | Support marketing/notification | Moyenne

---

## Références

### Livres

- Domain-Driven Design, Eric Evans (Blue Book)
- Implementing Domain-Driven Design, Vaughn Vernon (Red Book)
- Domain-Driven Design Distilled, Vaughn Vernon

### Articles

- [DDD Reference](https://www.domainlanguage.com/ddd/reference/) - Eric Evans
- [Bounded Context](https://martinfowler.com/bliki/BoundedContext.html) - Martin Fowler
- [Aggregate Design Canvas](https://github.com/ddd-crew/aggregate-design-canvas)

### ADRs Connexes

- ADR-003: Domain-Driven Design Adoption
- ADR-010: Storage Strategy
- ADR-013: Async Processing
- ADR-016: Composite Pattern
- ADR-020: Magic Link Auth
- ADR-030: Event-Driven Communication
- ADR-040: Caching Strategy

### Code Base

- Répertoire principal: `lib/portfolio/`
- Tests: `test/portfolio/`
- Documentation ADRs: `docs/adr/`
- Documentation DDD: `docs/ddd/` (ce répertoire)

---

Date de création: 2025-11-12
Dernière révision: 2025-11-12
Auteur: Équipe Portfolio
