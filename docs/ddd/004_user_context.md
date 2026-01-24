# 004 - User Context (Supporting Domain)

Date: 2025-11-12

## Responsabilités

Le User Context gère les utilisateurs du système. Responsabilités :
- Gestion utilisateurs et profils
- Rôles et permissions (RBAC)
- Statut compte (actif, suspendu)

## Ubiquitous Language

**Utilisateur** : Personne utilisant le système (propriétaire portfolio pour l'instant, potentiellement visiteurs avec compte futur).

**Profil** : Informations personnelles (nom, photo).

**Rôle** : Permission globale définissant capacités utilisateur (admin, user).

**Statut** : État du compte (active = peut se connecter, suspended = bloqué).

**Email** : Identifiant unique de l'utilisateur, validé format RFC 5322.

## Architecture

### Aggregate

```
┌──────────────────────────────────┐
│  Utilisateur (Root)              │
│  - id: UUID                      │
│  - email: String (unique)        │
│  - nom: String                   │
│  - photo_url: String             │
│  - role: Enum                    │
│  - statut: Enum                  │
│  - inserted_at: DateTime         │
│  - updated_at: DateTime          │
└──────────────────────────────────┘
```

### Entity

**Utilisateur** : Aggregate Root représentant une personne.

### Value Objects

**Email** : String validé format RFC 5322 (regex simplifié), converti en minuscules, unique.

**Nom** : String libre (nom complet ou pseudo).

**PhotoURL** : String URL vers image de profil.

**Rôle** : Enum (admin, user)
- admin : Toutes permissions (gestion albums, projets, publications, utilisateurs)
- user : Lecture seule contenus publiés

**StatutUtilisateur** : Enum (active, suspended)
- active : Peut se connecter et utiliser système
- suspended : Connexion bloquée, sessions révoquées

### Diagrammes Aggregates Détaillés

```
┌──────────────────────────────────────────────────────────────────┐
│ Utilisateur (Aggregate Root)                                     │
├──────────────────────────────────────────────────────────────────┤
│ Attributs:                                                       │
│  - id: UUID                                                      │
│  - email: String (unique, normalisé minuscules)                 │
│  - nom: String (nom complet ou pseudo)                          │
│  - photo_url: String (URL image profil)                         │
│  - role: Enum (admin, user)                                     │
│  - statut: Enum (active, suspended)                             │
│  - inserted_at: DateTime                                         │
│  - updated_at: DateTime                                          │
├──────────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                              │
│  + créer(email, nom, role) -> Utilisateur                       │
│  + modifier_profil(nom, photo_url) -> {:ok, Utilisateur}        │
│  + suspendre() -> {:ok, Utilisateur}                            │
│  + réactiver() -> {:ok, Utilisateur}                            │
│  + changer_role(role) -> {:ok, Utilisateur}                     │
│  + est_actif?() -> boolean                                      │
│  + est_admin?() -> boolean                                      │
│  + peut_administrer?() -> boolean                               │
├──────────────────────────────────────────────────────────────────┤
│ Invariants:                                                      │
│  [PU-001] Email unique: Un seul utilisateur par email           │
│  [PU-002] Format email valide: RFC 5322 simplifié               │
│  [PU-003] Rôle par défaut: user (seul admin crée admin)         │
│  [PU-004] Statut par défaut: active                             │
│  [PU-005] Suspension → révocation sessions (event)              │
│  [PU-006] Admin unique: Au moins 1 admin obligatoire            │
└──────────────────────────────────────────────────────────────────┘

Relations:
  Session →[N:1] Utilisateur (Auth Context)
  Album →[N:1] Utilisateur (Photography Context, propriétaire)
  Projet →[N:1] Utilisateur (Photography Context, propriétaire)
  Notification →[N:1] Utilisateur (Communication Context, destinataire)
```

### Repository

**UtilisateurRepository**
- Création utilisateur
- Recherche par ID
- Recherche par email (login)
- Mise à jour profil
- Suspension compte

### Domain Service

**UserService**
- Création utilisateur avec validation email unique
- Modification profil
- Suspension compte (révocation sessions via Auth Context)

## Règles Métier (Invariants)

### Utilisateur

**PU-001 : Email unique**
- Contrainte : Un seul utilisateur par adresse email
- Implémentation : Index unique sur colonne email
- Validation : Vérification avant insert
- Erreur : Conflit si email existe déjà

**PU-002 : Format email valide**
- Contrainte : Email doit respecter format RFC 5322 (simplifié)
- Validation : Regex basique (présence @, domaine)
- Normalisation : Conversion en minuscules avant stockage

**PU-003 : Rôle par défaut**
- Règle : Nouvel utilisateur créé avec rôle user par défaut
- Override : Seul admin peut créer autre admin

**PU-004 : Statut par défaut**
- Règle : Nouvel utilisateur créé avec statut active
- Changement : Seul admin peut suspendre

**PU-005 : Suspension révoque sessions**
- Règle : Changement statut active → suspended révoque toutes sessions actives
- Implémentation : Event UtilisateurSuspendu diffusé vers Auth Context
- Conséquence : Déconnexion immédiate sur tous appareils

**PU-006 : Admin unique**
- Règle : Au moins un admin doit exister (bootstrap)
- Contrainte : Impossible de supprimer dernier admin
- Validation : Comptage admins avant suppression

## Domain Events

### Cycle de vie Utilisateur

**UtilisateurCréé**
- Données : utilisateur_id, email, nom, role, statut
- Déclenche : Initialisation permissions

**UtilisateurModifié**
- Données : utilisateur_id, profil (nom, photo_url)
- Conséquence : Mise à jour affichage

**UtilisateurSuspendu**
- Données : utilisateur_id, suspendu_le, raison (optionnel)
- Diffusé vers : Auth Context
- Déclenche : Révocation toutes sessions (déconnexion forcée)

## Patterns Appliqués

### Repository Pattern

Abstraction persistence :
- UtilisateurRepository gère accès table utilisateurs
- Services utilisent repository (pas Ecto direct)

### Value Object Email

Encapsulation validation et normalisation :
- Validation format
- Normalisation (lowercase)
- Immuabilité

### RBAC (Role-Based Access Control)

Permissions basées sur rôles (ADR 021) :
- admin : Toutes permissions
- user : Lecture seule (consultation contenus publiés)

Évolution future possible : permissions plus granulaires (création albums, modération commentaires).

## Dépendances Externes

### Auth Context
- Auth référence utilisateur_id dans Session
- User fournit validation email existence
- Event UtilisateurSuspendu → révocation sessions
- Relation Customer-Supplier et Publisher-Subscriber

### Photography Context
- Photography référence utilisateur_id (propriétaire albums/projets)
- User fournit informations utilisateur pour affichage
- Relation Customer-Supplier

### Communication Context
- Communication référence utilisateur_id pour notifications
- User fournit email et préférences
- Relation Customer-Supplier

## Incohérences Actuelles

**État actuel :**
- User fusionné dans Auth context (lib/portfolio/auth/)
- Pas de UtilisateurRepository (Ecto direct)
- Value Object Email documenté mais absent

**État cible :**
- Extraire User vers context dédié (lib/portfolio/user/)
- Créer UtilisateurRepository
- Créer Email Value Object
- Refactorer services pour utiliser repository

Priorité : Important (séparation concerns)

## API Publique (Signatures)

### UtilisateurRepository

```elixir
@doc "Crée un nouveau utilisateur avec email, nom et rôle"
@spec create(map()) :: {:ok, Utilisateur.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère utilisateur par ID"
@spec get(binary()) :: Utilisateur.t() | nil

@doc "Récupère utilisateur par email (login)"
@spec get_by_email(String.t()) :: Utilisateur.t() | nil

@doc "Liste tous utilisateurs (admin)"
@spec list() :: [Utilisateur.t()]

@doc "Compte utilisateurs admins (vérification admin unique)"
@spec count_admins() :: non_neg_integer()

@doc "Met à jour profil utilisateur (nom, photo)"
@spec update(Utilisateur.t(), map()) :: {:ok, Utilisateur.t()} | {:error, Ecto.Changeset.t()}

@doc "Change statut utilisateur (suspension/réactivation)"
@spec change_statut(Utilisateur.t(), atom()) :: {:ok, Utilisateur.t()} | {:error, Ecto.Changeset.t()}

@doc "Change rôle utilisateur (seul admin autorisé)"
@spec change_role(Utilisateur.t(), atom()) :: {:ok, Utilisateur.t()} | {:error, Ecto.Changeset.t()}

@doc "Supprime utilisateur (vérifie admin unique)"
@spec delete(Utilisateur.t()) :: {:ok, Utilisateur.t()} | {:error, String.t()}
```

### UserService

```elixir
@doc "Crée utilisateur avec validation email unique"
@spec creer_utilisateur(String.t(), String.t(), atom()) :: {:ok, Utilisateur.t()} | {:error, String.t()}

@doc "Modifie profil utilisateur (nom, photo)"
@spec modifier_profil(binary(), map()) :: {:ok, Utilisateur.t()} | {:error, String.t()}

@doc "Suspend compte utilisateur (révoque sessions via Auth)"
@spec suspendre_compte(binary(), String.t() | nil) :: {:ok, Utilisateur.t()} | {:error, String.t()}

@doc "Réactive compte suspendu"
@spec reactiver_compte(binary()) :: {:ok, Utilisateur.t()} | {:error, String.t()}

@doc "Change rôle utilisateur (admin seulement)"
@spec changer_role(binary(), atom()) :: {:ok, Utilisateur.t()} | {:error, String.t()}

@doc "Vérifie si utilisateur est admin"
@spec est_admin?(binary()) :: boolean()

@doc "Valide email unique avant création"
@spec email_disponible?(String.t()) :: boolean()
```

## Documents Liés

- Vue d'ensemble : docs/ddd/001_vue_ensemble.md
- Auth Context : docs/ddd/003_auth_context.md
- ADR 021 : Role-Based Access Control
- ADR 032 : Repository Pattern
- Schéma DB : tmp/schema_database_ddd.sql (section 1)
