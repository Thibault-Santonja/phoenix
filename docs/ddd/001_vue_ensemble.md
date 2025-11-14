# 001 - Vue d'Ensemble Architecture DDD

Date: 2025-11-12

## Contexte

Portfolio photographique personnel permettant la gestion d'albums datés, de projets photographiques hiérarchiques, l'authentification passwordless et l'envoi de notifications aux abonnés.

## Architecture Bounded Contexts

Le système est organisé en 4 Bounded Contexts selon les principes Domain-Driven Design :

```
┌──────────────────────────────────────────┐
│     PHOTOGRAPHY (Core Domain)            │
│     Gestion photographies, albums,       │
│     projets hiérarchiques                │
└──────────────────────────────────────────┘
          │
          │ Domain Events
          │ (AlbumPublié, ProjetPublié)
          │
          ├────────────────┐
          │                │
          ▼                ▼
┌──────────────────┐  ┌─────────────────────┐
│  COMMUNICATION   │  │      USER           │
│  (Supporting)    │  │  (Supporting)       │
│                  │  │                     │
│  Notifications   │  │  Gestion            │
│  Newsletter      │  │  utilisateurs       │
└──────────────────┘  └─────────────────────┘
                              ▲
                              │
                              │ Référence utilisateur_id
                              │
                      ┌───────────────┐
                      │     AUTH      │
                      │  (Supporting) │
                      │               │
                      │  MagicLinks   │
                      │  Sessions     │
                      └───────────────┘
```

### Relations Context Map

- Photography → Communication : Publisher-Subscriber via Domain Events
- Photography → User : Customer-Supplier via utilisateur_id
- Auth → User : Customer-Supplier via utilisateur_id
- Communication → User : Customer-Supplier via utilisateur_id

Aucune dépendance directe entre contexts. Communication uniquement par Domain Events ou références ID.

## Décisions Stratégiques

### DS-001 : Photographie comme Entity

La Photographie possède une identité propre indépendante des albums et projets. Cette décision permet :
- Partage d'une même photographie entre plusieurs collections
- Cycle de vie propre avec soft delete sur 7 jours
- Détection des doublons par empreinte SHA256
- Modification des métadonnées après création

Implications : Tables de jointure N-N, PhotographieRepository dédié.

### DS-002 : Album et Projet comme Aggregates distincts

Deux Aggregates séparés plutôt qu'une hiérarchie de classes car :
- Règles métier différentes (Album = date obligatoire, Projet = thématique libre)
- Structure différente (Album plat, Projet hiérarchique illimité)
- Publication différente (Projet avec cascade vers parents)

### DS-003 : Architecture 4 Bounded Contexts

Séparation en 4 contexts plutôt que 2 ou 3 pour :
- Séparation claire des responsabilités (SRP)
- Testabilité isolée de chaque contexte
- Évolution indépendante (changement système email sans impact sur Auth)
- Complexité raisonnable (pragmatisme)

### DS-004 : Soft Delete avec Hard Delete différé

Protection contre suppressions accidentelles :
- Marquage deleted_at lors de la suppression
- Conservation 7 jours
- Job Oban automatique pour hard delete
- Queries filtrées WHERE deleted_at IS NULL

### DS-005 : Publication conditionnelle

Pattern inspiré de YouTube :
- Si photographies en traitement lors de demande de publication → statut pending_publication
- Job Oban vérifie périodiquement l'état des photographies
- Publication automatique dès que toutes photographies sont completed

## Ubiquitous Language

### Photography Context

**Photographie** : Image photographique avec identité propre, partageable entre plusieurs collections.

**Album** : Collection de photographies datée représentant un événement ponctuel (mariage, voyage, shooting).

**Projet** : Collection thématique hiérarchique de photographies sans date obligatoire (Photo de rue, Portrait).

**Empreinte** : Signature numérique SHA256 unique permettant la détection des doublons.

**Variante** : Version redimensionnée d'une photographie (original AVIF, large 1920px, medium 1024px, thumbnail 320px).

**État Traitement** : Statut du traitement serveur (pending → processing → completed ou failed).

**Couverture** : Photographie représentant visuellement un album ou projet (par défaut : première photographie).

### Auth Context

**MagicLink** : Mécanisme d'authentification passwordless par email (terme technique).

**Lien de connexion sécurisé** : Terme public pour MagicLink.

**Session** : Session authentifiée d'un utilisateur avec expiration par inactivité (2 heures configurable) et durée maximale de 24 heures.

### User Context

**Utilisateur** : Personne utilisant le système.

**Rôle** : Permission globale (admin = toutes permissions, user = lecture seule).

### Communication Context

**Notification** : Email transactionnel déclenché par un événement (album publié, projet publié).

**Newsletter** : Email périodique avec contenu personnalisé (texte libre + albums/projets + liens externes).

**Abonné** : Personne inscrite aux notifications avec double opt-in.

## Règles Métier Critiques

### Photography

**PM-001** : Unicité empreinte - Une seule photographie par empreinte SHA256, index unique, réutilisation si existe.

**PM-002** : Partage N-N - Une photographie peut appartenir à plusieurs albums et projets simultanément via tables de jointure.

**PM-003** : Contrainte suppression photographie - Impossible de supprimer si des références existent dans albums ou projets.

**PM-004** : Soft delete 7 jours - Marquage deleted_at lors suppression, conservation 7 jours, job Oban automatique pour hard delete.

**PM-005** : Règle publication album - Conditions : minimum 1 photographie + titre + description + date + toutes photographies en état completed. Si photos en processing → statut pending_publication.

**PM-006** : Recommandation quantité - Recommandation non bloquante : 5 à 30 photographies par album (validation warning uniquement).

**PM-007** : Ordre photographies - Par défaut chronologique (date_prise), override manuel possible via colonne position.

**PM-008** : Couverture automatique - Par défaut première photographie, override manuel possible, couverture doit appartenir à l'album/projet.

**PM-009** : Règle publication projet - Conditions : (minimum 1 photographie OU minimum 1 sous-projet) + titre + description + toutes photos completed + tous parents publiés.

**PM-010** : Hiérarchie illimitée - Profondeur maximale aucune limite, détection cycles obligatoire, calcul profondeur automatique.

**PM-011** : Contrainte suppression projet - Impossible de supprimer projet si sous-projets existent.

**PM-012** : Publication cascade parents - Si projet publié, tous parents doivent être publiés (récursion automatique vers racine).

**PM-013** : Dépublication cascade enfants - Dépublication projet dépublie automatiquement tous sous-projets (récursion vers feuilles).

### Auth

**PA-001** : Rate limiting - Maximum 5 MagicLinks par email par heure, protection spam et brute-force (ADR 020).

**PA-002** : Expiration MagicLink - Durée de validité : 15 minutes après création, token inutilisable après expiration.

**PA-003** : Usage unique - Token MagicLink invalidé après première utilisation (colonne used = true).

**PA-004** : Token MagicLink unique - Index unique sur colonne token, génération 32 bytes crypto aléatoires (256 bits entropie).

**PA-005** : Expiration session - Expiration par inactivité : 2 heures sans activité (configurable). Durée maximale : 24 heures. Prolongation automatique last_activity_at.

**PA-006** : Token session unique - Index unique sur colonne token, génération 32 bytes crypto aléatoires (256 bits entropie).

**PA-007** : Révocation cascade - Suspension utilisateur révoque toutes sessions actives (déconnexion immédiate tous appareils).

### User

**PU-001** : Email unique - Un seul utilisateur par adresse email, index unique, validation avant insert.

**PU-002** : Format email valide - Email doit respecter format RFC 5322 (simplifié), normalisation minuscules avant stockage.

**PU-003** : Rôle par défaut - Nouvel utilisateur créé avec rôle user par défaut. Seul admin peut créer autre admin.

**PU-004** : Statut par défaut - Nouvel utilisateur créé avec statut active. Seul admin peut suspendre.

**PU-005** : Suspension révoque sessions - Changement statut active → suspended révoque toutes sessions actives via event (déconnexion immédiate).

**PU-006** : Admin unique - Au moins un admin doit exister (bootstrap). Impossible de supprimer dernier admin.

### Communication

**PC-001** : Envoi asynchrone - Notifications envoyées via job Oban (pas synchrone) pour performance, pas de blocage HTTP.

**PC-002** : Retry échecs temporaires - Tentatives répétées si erreur temporaire (Oban max_attempts = 3, backoff exponentiel).

**PC-003** : Contenu personnalisé - Newsletter contient texte libre Markdown + sélection albums/projets + liens externes.

**PC-004** : Programmation future - Newsletter peut être programmée à date future (Oban delayed jobs, statut draft → scheduled → sent).

**PC-005** : Envoi massif optimisé - Envoi par batch de 100 abonnés pour performance (éviter timeout).

**PC-006** : Double opt-in obligatoire (RGPD) - Inscription nécessite confirmation par email (statut pending_confirmation → active après clic).

**PC-007** : Email unique - Un seul abonné par adresse email, index unique, validation avant insert.

**PC-008** : Désinscription facile - Lien désinscription dans footer de chaque email, changement statut active → unsubscribed.

**PC-009** : Données minimales (RGPD) - Données collectées : email + dates uniquement. Pas de nom, IP, tracking ouverture.

**PC-010** : Droit accès et effacement (RGPD) - Droit accès via page affichant données. Droit effacement sur demande (suppression définitive sous 30 jours).

### Transverse

**RT-001** : UUID v4 - Tous les identifiants primaires utilisent UUID v4 (binary_id) pour identité distribuée et prévention collision.

**RT-002** : Soft Delete - Protection 7 jours : marquage deleted_at lors suppression, conservation 7 jours, job Oban automatique pour hard delete.

**RT-003** : Timestamps UTC - Tous les timestamps en UTC (utc_datetime) via Ecto.

**RT-004** : Empreinte SHA-256 - Hash SHA-256 tronqué à 16 caractères hexadécimaux pour détection doublons fichiers.

**RT-005** : Traitement asynchrone - Jobs lourds (image processing, emails) via Oban pour non-blocage HTTP.

**RT-006** : Formats images - 3 variantes WebP (400px, 768px, 1280px) + 1 variante AVIF (1920px) pour responsive design Tailwind.

**RT-007** : Stockage local - Fichiers stockés localement avec migration cloud déclenchée à 10GB (seuil avant saturation VPS).

**RT-008** : Migration UUIDv7 (futur) - Migration planifiée de UUID v4 vers UUID v7 pour tri chronologique natif et performance indexes B-tree améliorée. UUID v7 intègre timestamp permettant inserts séquentiels (vs random v4) réduisant fragmentation index. Migration transparente (même type binary_id PostgreSQL). Priorité : faible (optimisation performance préventive). Voir ADR-004 Notes.

Détails des règles métier : voir docs/business_rules/

## Architecture Aggregates

### Photography Context

**Aggregate Photographie** (Root)
- Variantes (Entity faible, 1-N)

**Aggregate Album** (Root)
- Référence Photographies via album_photographies (N-N)
- Référence Couverture (1 photographie optionnelle)

**Aggregate Projet** (Root)
- Référence Parent via parent_id (self-reference, arbre hiérarchique)
- Référence Photographies via projet_photographies (N-N)
- Référence Couverture (1 photographie optionnelle)

### Auth Context

**Aggregate MagicLink** (Root)

**Aggregate Session** (Root)

### User Context

**Aggregate Utilisateur** (Root)

### Communication Context

**Aggregate Notification** (Root)

**Aggregate Newsletter** (Root)

**Entity Abonné** (standalone)

## Value Objects Principaux

### Photography
- Empreinte (SHA256)
- ÉtatTraitement (enum)
- Titre (3-255 chars)
- Description (7-8191 chars)
- Slug (URL-friendly)
- StatutPublication (enum)
- DateAlbum (année ou année+mois)

### Auth
- TokenConnexion (32 bytes crypto aléatoires, Base64 URL-safe, 256 bits)
- TokenSession (32 bytes crypto aléatoires, Base64 URL-safe, 256 bits)
- Expiration (DateTime)

### User
- Email (validation RFC 5322)
- Rôle (enum)

### Communication
- TypeNotification (enum)
- StatutEnvoi (enum)

## Repositories

Chaque Aggregate possède son Repository pour abstraction de la persistence (ADR 032).

### Photography Context
- PhotographieRepository
- AlbumRepository
- ProjetRepository

### Auth Context
- MagicLinkRepository
- SessionRepository

### User Context
- UtilisateurRepository

### Communication Context
- NotificationRepository
- NewsletterRepository
- AbonnéRepository

## Domain Services

Services encapsulant la logique métier impliquant plusieurs Aggregates.

### Photography Context
- PhotoUploadService : Upload + détection doublon + association
- AlbumPublicationService : Publication avec validation règles métier
- ProjetPublicationService : Publication avec cascade parents
- ProjetHierarchyService : Construction arbre, détection cycles

### Communication Context
- NotificationService : Envoi notifications transactionnelles
- NewsletterService : Envoi newsletters périodiques
- EmailSenderService : Abstraction envoi emails

## Domain Events

### Photography Context émet
- PhotographieAjoutée
- PhotographieTraitée
- PhotographieModifiée
- PhotographieSuppriméeSoft
- AlbumCréé
- AlbumPublié
- AlbumDépublié
- AlbumSuppriméSoft
- ProjetCréé
- ProjetPublié
- ProjetAttaché (changement parent)
- ProjetDépublié
- ProjetSuppriméSoft

### Auth Context émet
- MagicLinkCréé
- MagicLinkUtilisé
- SessionCréée
- SessionExpirée

### User Context émet
- UtilisateurCréé
- UtilisateurModifié
- UtilisateurSuspendu

### Communication Context émet
- NotificationEnvoyée
- NewsletterProgrammée
- NewsletterEnvoyée
- AbonnéInscrit
- AbonnéDésinscrit

## Patterns Architecturaux

### Composite Pattern (Projets)

Permet la construction d'une hiérarchie illimitée de projets avec interface uniforme.

Un Projet peut contenir :
- Des photographies directement
- Des sous-projets (eux-mêmes des Projets)

Exemple : "Photo de rue" → "Nighthawks" → "Japon" → "Tokyo" (profondeur illimitée)

Implémentation via self-reference (parent_id) et calcul de profondeur pour optimisation.

### Repository Pattern (ADR 032)

Abstraction de la couche de persistence permettant :
- Testabilité via mocks
- Migration de base de données facilitée
- Encapsulation des requêtes complexes

Séparation stricte : Aggregate (logique métier) / Repository (accès données).

### Soft Delete Pattern

Protection contre suppressions accidentelles :
- Ajout colonne deleted_at (nullable)
- Soft delete : mise à jour deleted_at avec timestamp
- Hard delete : suppression physique après délai (7 jours)
- Jobs Oban automatiques pour nettoyage
- Queries filtrées WHERE deleted_at IS NULL

### Anti-Corruption Layer (ACL)

Protection contre dépendances externes via interfaces (Ports).

Exemples :
- Portfolio.Photography.Ports.Storage (LocalStorage dev, CloudflareStorage prod)
- Portfolio.Communication.Ports.EmailProvider (Swoosh prod, Mock test)

Permet changement d'implémentation sans impact sur le domaine.

### CQRS Léger

Séparation Commandes (write) et Queries (read) :

Commandes (write) :
- Passent par les Aggregates
- Appliquent les invariants métier
- Émettent des Domain Events

Queries (read) :
- Passent par les Query Objects
- Optimisées pour lectures (preloads, joins)
- Pas d'invariants

Pas de séparation physique des bases de données (pragmatisme).

### Publisher-Subscriber (Domain Events)

Communication inter-contexts via Phoenix.PubSub :
- Photography publie AlbumPublié, ProjetPublié
- Communication souscrit et envoie notifications
- Pas de dépendance directe entre contexts

## Incohérences Actuelles

Écarts entre état actuel du code et modèle DDD cible :

**Priorité Critique**
- Photographie traitée comme Value Object imbriqué au lieu d'Entity indépendante
- Projet Aggregate inexistant
- Tables N-N (album_photographies, projet_photographies) manquantes

**Priorité Importante**
- Repositories manquants dans Auth context (MagicLinkRepository, SessionRepository)
- User context fusionné dans Auth context
- Communication context inexistant

**Priorité Moyenne**
- Soft delete non implémenté
- Statut pending_publication inexistant
- Email Value Object documenté mais absent

Plan de migration détaillé : voir tmp/notes_strategiques_ddd.md section 13

## Documents Liés

- ADR 003 : Adoption Domain-Driven Design
- ADR 032 : Repository Pattern Data Access
- ADR 020 : Magic Link Passwordless Auth
- ADR 021 : Role-Based Access Control
- Event Storming complet : tmp/event_storming_complet.md
- Schéma base de données : tmp/schema_database_ddd.sql
- Context Photography : docs/ddd/002_photography_context.md
- Context Auth : docs/ddd/003_auth_context.md
- Context User : docs/ddd/004_user_context.md
- Context Communication : docs/ddd/005_communication_context.md
