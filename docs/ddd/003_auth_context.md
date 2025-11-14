# 003 - Auth Context (Supporting Domain)

Date: 2025-11-12

## Responsabilités

Le Auth Context gère l'authentification des utilisateurs via un mécanisme passwordless. Responsabilités :
- Génération et validation MagicLinks (liens de connexion sécurisés)
- Gestion sessions authentifiées
- Rate limiting connexions
- Expiration automatique

## Ubiquitous Language

**MagicLink** : Mécanisme d'authentification passwordless par token unique envoyé par email (terme technique).

**Lien de connexion sécurisé** : Terme public désignant le MagicLink dans les communications utilisateur.

**TokenConnexion** : Jeton unique (32 bytes aléatoires cryptographiquement sûrs, encodé Base64 URL-safe, 256 bits entropie) identifiant un MagicLink.

**Session** : Session authentifiée d'un utilisateur avec expiration par inactivité (2 heures configurable) et durée maximale de 24 heures.

**TokenSession** : Jeton unique (32 bytes aléatoires cryptographiquement sûrs, encodé Base64 URL-safe, 256 bits entropie) identifiant une session.

**Expiration** : Date/heure limite de validité d'un token.

## Architecture

### Aggregates

```
┌─────────────────────────────────┐
│  MagicLink (Root)               │
│  - id: UUID                     │
│  - token: UUID v4               │
│  - email: String                │
│  - expires_at: DateTime         │
│  - used: Boolean                │
│  - inserted_at: DateTime        │
└─────────────────────────────────┘

┌─────────────────────────────────┐
│  Session (Root)                 │
│  - id: UUID                     │
│  - token: UUID v4               │
│  - utilisateur_id: UUID (FK)    │
│  - expires_at: DateTime         │
│  - metadata: JSONB              │
│  - inserted_at: DateTime        │
└─────────────────────────────────┘
```

### Entities

**MagicLink** : Aggregate Root éphémère (durée de vie : 15 minutes).

**Session** : Aggregate Root avec expiration par inactivité (2h) et durée maximale (24h).

### Value Objects

**TokenConnexion** : Token aléatoire cryptographiquement sûr (32 bytes, encodé Base64 URL-safe, 256 bits entropie).

**TokenSession** : Token aléatoire cryptographiquement sûr (32 bytes, encodé Base64 URL-safe, 256 bits entropie).

**Expiration** : DateTime UTC calculé lors création (MagicLink +15min, Session inactivité +2h, max 24h).

**Email** : String validé format email (référence User Context).

**SessionMetadata** : JSONB contenant adresse IP et user-agent pour audit.

### Diagrammes Aggregates Détaillés

```
┌───────────────────────────────────────────────────────────────┐
│ MagicLink (Aggregate Root)                                    │
├───────────────────────────────────────────────────────────────┤
│ Attributs:                                                    │
│  - id: UUID                                                   │
│  - token: String (32 bytes crypto aléatoires, Base64, 256b)  │
│  - email: String (format validé)                             │
│  - expires_at: DateTime (UTC, +15 minutes)                   │
│  - used: Boolean (défaut false)                              │
│  - inserted_at: DateTime                                      │
├───────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                           │
│  + créer(email) -> MagicLink                                 │
│  + valider_utilisation() -> {:ok, MagicLink} | {:error, ...} │
│  + marquer_utilisé() -> {:ok, MagicLink}                     │
│  + est_valide?() -> boolean                                  │
│  + est_expiré?() -> boolean                                  │
├───────────────────────────────────────────────────────────────┤
│ Invariants:                                                   │
│  [PA-001] Rate limiting: Max 5 créations/heure par email     │
│  [PA-002] Expiration: Invalide après 15 minutes              │
│  [PA-003] Usage unique: used=true après consommation         │
│  [PA-004] Token unique: Aucune collision possible            │
└───────────────────────────────────────────────────────────────┘

┌───────────────────────────────────────────────────────────────┐
│ Session (Aggregate Root)                                      │
├───────────────────────────────────────────────────────────────┤
│ Attributs:                                                    │
│  - id: UUID                                                   │
│  - token: String (32 bytes crypto aléatoires, Base64, 256b)  │
│  - utilisateur_id: UUID (FK → User Context)                  │
│  - last_activity_at: DateTime (UTC, prolongation auto)       │
│  - metadata: JSONB (ip_address, user_agent)                  │
│  - inserted_at: DateTime                                      │
├───────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                           │
│  + créer(utilisateur_id, metadata) -> Session                │
│  + valider() -> {:ok, Session} | {:error, ...}               │
│  + révoquer() -> {:ok, Session}                              │
│  + prolonger() -> {:ok, Session}                             │
│  + est_valide?() -> boolean                                  │
│  + est_expirée?() -> boolean                                 │
├───────────────────────────────────────────────────────────────┤
│ Invariants:                                                   │
│  [PA-005] Expiration: Inactivité 2h (configurable), max 24h  │
│  [PA-006] Token unique: Aucune collision possible            │
│  [PA-007] Révocation cascade: Suspension → toutes sessions   │
└───────────────────────────────────────────────────────────────┘

Relations:
  Session →[N:1] Utilisateur (User Context)
  MagicLink → [event: MagicLinkUtilisé] → Session (création après validation)
```

### Repositories

**MagicLinkRepository**
- Création MagicLink avec token et expiration
- Recherche par token
- Comptage créations récentes par email (rate limiting)
- Marquage utilisé après consommation

**SessionRepository**
- Création session avec token et expiration
- Recherche par token
- Suppression session (déconnexion)
- Révocation toutes sessions utilisateur (suspension compte)
- Cleanup sessions expirées (job quotidien)

### Domain Services

**MagicLinkService**
- Validation rate limiting (max 5 liens/heure par email)
- Génération token unique
- Calcul expiration (15 minutes)
- Émission event MagicLinkCréé
- Déclenchement envoi email (Communication Context)

**SessionService**
- Création session après validation MagicLink
- Génération token unique
- Gestion expiration (inactivité 2h, max 24h)
- Prolongation automatique (last_activity_at)
- Validation session (token + expiration)
- Révocation sessions

## Règles Métier (Invariants)

### MagicLink

**PA-001 : Rate limiting**
- Limite : Maximum 5 MagicLinks par email par heure
- Objectif : Protection contre spam et attaques brute-force
- Implémentation : Comptage créations depuis now() - 1 heure
- Réponse : Erreur explicite si limite atteinte
- Référence : ADR 020

**PA-002 : Expiration 15 minutes**
- Durée validité : 15 minutes après création
- Validation : Comparaison expires_at avec now()
- Conséquence : Token inutilisable après expiration

**PA-003 : Usage unique**
- Contrainte : Token invalidé après première utilisation
- Implémentation : Colonne used (boolean)
- Validation : Vérifier used = false avant acceptation
- Mise à jour : used = true après consommation

**PA-004 : Token unique**
- Contrainte : Un token ne peut être réutilisé
- Implémentation : Index unique sur colonne token
- Génération : UUID v4 (collision probabilité négligeable)

### Session

**PA-005 : Expiration par inactivité et durée maximale**
- Expiration inactivité : 2 heures sans activité (configurable via SESSION_EXPIRATION_SECONDS)
- Durée maximale : 24 heures (cookie max_age)
- Validation : Comparaison last_activity_at avec now()
- Prolongation automatique : last_activity_at mis à jour à chaque requête
- Cleanup automatique : GenServer horaire supprime sessions expirées

**PA-006 : Token unique**
- Contrainte : Un token session ne peut être réutilisé
- Implémentation : Index unique sur colonne token
- Génération : UUID v4

**PA-007 : Révocation cascade**
- Règle : Suspension utilisateur révoque toutes sessions actives
- Implémentation : DELETE WHERE utilisateur_id = ?
- Conséquence : Déconnexion immédiate sur tous appareils

## Domain Events

### Cycle de vie MagicLink

**MagicLinkCréé**
- Données : token, email, expires_at, tentatives_restantes
- Diffusé vers : Communication Context (envoi email lien)
- Déclenche : Notification email avec URL /auth/verify?token={token}

**MagicLinkUtilisé**
- Données : token, email, utilisateur_id, utilisé_le
- Déclenche : Création Session

### Cycle de vie Session

**SessionCréée**
- Données : session_id, token, utilisateur_id, last_activity_at, metadata
- Conséquence : Utilisateur authentifié

**SessionRévoquée**
- Données : session_id, révoquée_le
- Cause : Déconnexion manuelle ou suspension utilisateur

**SessionExpirée**
- Données : session_id, expirée_le
- Déclenche : Job cleanup quotidien

## Patterns Appliqués

### Repository Pattern

Abstraction persistence pour testabilité :
- MagicLinkRepository gère accès table magic_links
- SessionRepository gère accès table sessions
- Services utilisent repositories (pas Ecto direct)

### Rate Limiting Pattern

Protection spam via comptage temporel :
- Fenêtre glissante 1 heure
- Comptage créations par email
- Rejet si limite dépassée (réponse 429 Too Many Requests)

### Token Pattern

Génération tokens sécurisés :
- UUID v4 (128 bits entropie)
- Stockage côté serveur (pas JWT)
- Validation requiert accès DB (révocation possible)

## Dépendances Externes

### User Context
- Référence utilisateur_id dans Session
- Validation existence email lors création MagicLink
- Relation Customer-Supplier

### Communication Context
- Émission event MagicLinkCréé
- Communication envoie email lien connexion
- Relation Publisher-Subscriber

## Incohérences Actuelles

**État actuel :**
- MagicLinkService utilise Ecto direct (pas de repository)
- SessionService utilise Ecto direct (pas de repository)
- User fusionné dans Auth context

**État cible :**
- Créer MagicLinkRepository
- Créer SessionRepository
- Refactorer services pour utiliser repositories
- Extraire User vers context dédié

Priorité : Important (ADR 032 Repository Pattern)

## API Publique (Signatures)

### MagicLinkRepository

```elixir
@doc "Crée un nouveau MagicLink avec token unique et expiration 15 minutes"
@spec create(map()) :: {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère MagicLink par token"
@spec get_by_token(String.t()) :: MagicLink.t() | nil

@doc "Compte créations récentes pour rate limiting (fenêtre glissante 1h)"
@spec count_recent_by_email(String.t(), DateTime.t()) :: non_neg_integer()

@doc "Marque MagicLink comme utilisé (usage unique)"
@spec mark_as_used(MagicLink.t()) :: {:ok, MagicLink.t()} | {:error, Ecto.Changeset.t()}

@doc "Supprime MagicLinks expirés (cleanup quotidien)"
@spec delete_expired() :: {non_neg_integer(), nil}
```

### SessionRepository

```elixir
@doc "Crée nouvelle session avec token unique et last_activity_at initial"
@spec create(map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère session par token"
@spec get_by_token(String.t()) :: Session.t() | nil

@doc "Récupère session par ID avec préchargement utilisateur"
@spec get(binary()) :: Session.t() | nil

@doc "Supprime session (déconnexion manuelle)"
@spec delete(Session.t()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}

@doc "Révoque toutes sessions actives d'un utilisateur (suspension)"
@spec revoke_all_for_user(binary()) :: {non_neg_integer(), nil}

@doc "Supprime sessions expirées (cleanup quotidien)"
@spec delete_expired() :: {non_neg_integer(), nil}

@doc "Liste sessions actives d'un utilisateur"
@spec list_active_for_user(binary()) :: [Session.t()]
```

### MagicLinkService

```elixir
@doc "Génère et envoie MagicLink par email (rate limiting appliqué)"
@spec generer_et_envoyer(String.t()) :: {:ok, MagicLink.t()} | {:error, String.t()}

@doc "Valide token MagicLink et retourne email si valide"
@spec valider_token(String.t()) :: {:ok, String.t()} | {:error, String.t()}

@doc "Consomme MagicLink et crée session utilisateur"
@spec consommer_et_creer_session(String.t(), map()) :: {:ok, Session.t()} | {:error, String.t()}
```

### SessionService

```elixir
@doc "Crée session pour utilisateur avec metadata (IP, user-agent)"
@spec creer_session(binary(), map()) :: {:ok, Session.t()} | {:error, Ecto.Changeset.t()}

@doc "Valide session par token (vérifie expiration)"
@spec valider_session(String.t()) :: {:ok, Session.t()} | {:error, String.t()}

@doc "Révoque session spécifique (déconnexion)"
@spec revoquer_session(String.t()) :: {:ok, Session.t()} | {:error, String.t()}

@doc "Révoque toutes sessions utilisateur (suspension compte)"
@spec revoquer_toutes_sessions(binary()) :: {:ok, non_neg_integer()}
```

## Documents Liés

- Vue d'ensemble : docs/ddd/001_vue_ensemble.md
- User Context : docs/ddd/004_user_context.md
- Communication Context : docs/ddd/005_communication_context.md
- ADR 020 : Magic Link Passwordless Auth
- ADR 032 : Repository Pattern
- Schéma DB : tmp/schema_database_ddd.sql (section 2)
