# 002 - Photography Context (Core Domain)

Date: 2025-11-12

## Responsabilités

Le Photography Context est le domaine métier central du système. Il gère :
- Photographies et variantes (traitement images AVIF)
- Albums datés (événements ponctuels)
- Projets hiérarchiques (collections thématiques)
- Publication et dépublication de contenus

## Ubiquitous Language

**Photographie** : Image photographique avec identité propre, partageable entre collections.

**Empreinte** : Signature numérique SHA256 du fichier permettant détection des doublons.

**Variante** : Version redimensionnée d'une photographie (4 tailles : original, large 1920px, medium 1024px, thumbnail 320px).

**État Traitement** : Statut du traitement serveur : pending (en attente) → processing (en cours) → completed (terminé) ou failed (échec).

**Album** : Collection de photographies datée représentant un événement ponctuel (mariage, voyage, shooting).

**Projet** : Collection thématique hiérarchique sans date obligatoire (Photo de rue, Portrait).

**Couverture** : Photographie représentant visuellement un album ou projet.

**Slug** : Identifiant URL-friendly généré depuis le titre.

**Statut Publication** : État de publication (draft, pending_publication, published, unpublished).

## Architecture

### Aggregates

```
┌─────────────────────────────────────┐
│  Photographie (Root)                │
│  - id: UUID                         │
│  - empreinte: SHA256                │
│  - titre: String                    │
│  - etat_traitement: Enum            │
│  │                                   │
│  └─► Variantes (Entity faible, 1-N) │
│      - format: AVIF                 │
│      - taille: Enum                 │
│      - url: String                  │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  Album (Root)                       │
│  - id: UUID                         │
│  - titre: String                    │
│  - description: Text                │
│  - date_album: Date                 │
│  - statut: Enum                     │
│  │                                   │
│  ├─► Photographies (N-N)            │
│  │    via album_photographies       │
│  │                                   │
│  └─► Couverture (0-1)               │
└─────────────────────────────────────┘

┌─────────────────────────────────────┐
│  Projet (Root)                      │
│  - id: UUID                         │
│  - titre: String                    │
│  - description: Text                │
│  - statut: Enum                     │
│  - parent_id: UUID (self-ref)       │
│  - profondeur: Integer              │
│  │                                   │
│  ├─► Photographies (N-N)            │
│  │    via projet_photographies      │
│  │                                   │
│  ├─► Couverture (0-1)               │
│  │                                   │
│  └─► Sous-Projets (0-N)             │
│       hiérarchie illimitée          │
└─────────────────────────────────────┘
```

### Entities

**Photographie** : Aggregate Root avec identité stable, partageable entre collections.

**Variante** : Entity faible possédée par Photographie (cascade delete).

### Value Objects

**Empreinte** : SHA256 (64 caractères hexadécimaux).

**ÉtatTraitement** : Enum (pending, processing, completed, failed).

**Titre** : String validé (3-255 caractères).

**Description** : String validé (7-8191 caractères).

**Slug** : String URL-friendly (généré depuis titre, unique).

**StatutPublication** : Enum (draft, pending_publication, published, unpublished).

## Diagrammes Aggregates Détaillés

### Aggregate Photographie

```
┌──────────────────────────────────────────────────────────────────────┐
│ Photographie (Aggregate Root)                                        │
├──────────────────────────────────────────────────────────────────────┤
│ Attributs:                                                           │
│   + id: UUID                                                         │
│   + empreinte: Empreinte (VO) - SHA256                              │
│   + titre: Titre (VO) - 3-255 chars                                 │
│   + metadata_exif: Map                                               │
│   + date_prise: DateTime                                             │
│   + etat_traitement: ÉtatTraitement (VO)                             │
│   + deleted_at: DateTime (nullable)                                  │
├──────────────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                                  │
│   + changeset(attrs: map()) → Changeset.t()                          │
│   + modifier_titre(nouveau_titre: String.t())                        │
│     → {:ok, t()} | {:error, Changeset.t()}                          │
│   + marquer_traitee() → {:ok, t()}                                   │
│   + peut_etre_supprimee?() → boolean()                               │
├──────────────────────────────────────────────────────────────────────┤
│ Invariants:                                                          │
│   - Empreinte unique (index DB)                                      │
│   - Titre 3-255 caractères                                           │
│   - Suppression bloquée si références existent                       │
│   - État traitement: pending → processing → completed | failed       │
└──────────────────────────────────────────────────────────────────────┘
                         │ 1
                         │ owns
                         │ 1..*
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│ Variante (Entity Faible)                                             │
├──────────────────────────────────────────────────────────────────────┤
│ Attributs:                                                           │
│   + id: UUID                                                         │
│   + photographie_id: UUID (FK)                                       │
│   + format: Format (VO) - AVIF                                       │
│   + taille: Taille (VO) - original/large/medium/thumbnail            │
│   + url: URL (VO)                                                    │
│   + largeur: Integer                                                 │
│   + hauteur: Integer                                                 │
│   + poids_octets: Integer                                            │
├──────────────────────────────────────────────────────────────────────┤
│ Cycle de vie:                                                        │
│   - Créée lors traitement photographie (Oban worker)                 │
│   - Supprimée en cascade avec photographie (ON DELETE CASCADE)       │
└──────────────────────────────────────────────────────────────────────┘

                         ▲
                         │ N
                         │ references
                         │ N
                         │
┌──────────────────────────────────────────────────────────────────────┐
│ Album (Aggregate Root)                                               │
├──────────────────────────────────────────────────────────────────────┤
│ Attributs:                                                           │
│   + id: UUID                                                         │
│   + titre: Titre (VO) - 3-255 chars                                 │
│   + description: Description (VO) - 7-8191 chars                     │
│   + date_album: DateAlbum (VO) - année ou année+mois                │
│   + slug: Slug (VO) - unique                                         │
│   + statut: StatutPublication (VO)                                   │
│   + couverture_id: UUID (nullable, FK Photographie)                  │
│   + utilisateur_id: UUID (FK)                                        │
│   + deleted_at: DateTime (nullable)                                  │
├──────────────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                                  │
│   + changeset(attrs: map()) → Changeset.t()                          │
│   + peut_etre_publie?() → :ok | {:error, :validation_failed}        │
│   + ajouter_photographie(photographie_id: UUID)                      │
│     → {:ok, t()} | {:error, term()}                                 │
│   + retirer_photographie(photographie_id: UUID)                      │
│     → {:ok, t()} | {:error, term()}                                 │
│   + definir_couverture(photographie_id: UUID)                        │
│     → {:ok, t()} | {:error, term()}                                 │
├──────────────────────────────────────────────────────────────────────┤
│ Invariants:                                                          │
│   - Publication: ≥1 photo + titre + description + date               │
│   - Toutes photos en état completed pour publier                     │
│   - Couverture doit appartenir à l'album                             │
│   - Slug unique généré depuis titre                                  │
└──────────────────────────────────────────────────────────────────────┘
                         │ N
                         │ references via
                         │ album_photographies
                         │ N
                         ▼
                   [Photographie]

┌──────────────────────────────────────────────────────────────────────┐
│ Projet (Aggregate Root - Composite Pattern)                          │
├──────────────────────────────────────────────────────────────────────┤
│ Attributs:                                                           │
│   + id: UUID                                                         │
│   + titre: Titre (VO)                                                │
│   + description: Description (VO)                                    │
│   + slug: Slug (VO)                                                  │
│   + statut: StatutPublication (VO)                                   │
│   + parent_id: UUID (nullable, FK self-reference)                    │
│   + profondeur: Integer (dénormalisé)                                │
│   + couverture_id: UUID (nullable, FK Photographie)                  │
│   + utilisateur_id: UUID (FK)                                        │
│   + deleted_at: DateTime (nullable)                                  │
├──────────────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                                  │
│   + changeset(attrs: map()) → Changeset.t()                          │
│   + peut_etre_publie?() → :ok | {:error, :validation_failed}        │
│   + a_du_contenu?() → boolean()                                      │
│   + parents_publies?() → boolean()                                   │
│   + peut_etre_supprime?() → boolean()                                │
├──────────────────────────────────────────────────────────────────────┤
│ Invariants:                                                          │
│   - Publication: (≥1 photo OU ≥1 sous-projet) + tous parents publiés│
│   - Suppression bloquée si sous-projets existent                     │
│   - Pas de cycle (trigger DB + validation app)                       │
│   - Profondeur calculée automatiquement                              │
└──────────────────────────────────────────────────────────────────────┘
         │ 1                        │ N
         │ parent                   │ references via
         │                          │ projet_photographies
         ▼ 0..1                     │ N
    [Projet parent]                 ▼
                              [Photographie]
```

## API Publique (Signatures)

### PhotographieRepository

```elixir
@doc "Crée une nouvelle photographie"
@spec create(map()) :: {:ok, Photographie.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère photographie par ID"
@spec get(binary()) :: Photographie.t() | nil

@doc "Récupère photographie par empreinte SHA256"
@spec get_by_empreinte(binary()) :: Photographie.t() | nil

@doc "Liste toutes photographies non supprimées"
@spec list(keyword()) :: [Photographie.t()]

@doc "Liste photographies orphelines (aucune référence album/projet)"
@spec list_orphelines() :: [Photographie.t()]

@doc "Liste photographies soft deleted"
@spec list_soft_deleted() :: [Photographie.t()]

@doc "Met à jour photographie"
@spec update(Photographie.t(), map()) :: {:ok, Photographie.t()} | {:error, Ecto.Changeset.t()}

@doc "Soft delete photographie (bloquée si références existent)"
@spec soft_delete(Photographie.t()) :: {:ok, Photographie.t()} | {:error, String.t()}

@doc "Restaure photographie soft deleted"
@spec restore(binary()) :: {:ok, Photographie.t()} | {:error, term()}

@doc "Hard delete photographie (appelé par Oban worker)"
@spec hard_delete(Photographie.t()) :: {:ok, Photographie.t()} | {:error, term()}

@doc "Preload variantes"
@spec preload_variantes(Photographie.t()) :: Photographie.t()
```

### AlbumRepository

```elixir
@doc "Crée nouvel album"
@spec create(map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère album par ID avec associations"
@spec get(binary()) :: Album.t() | nil

@doc "Récupère album par slug"
@spec get_by_slug(String.t()) :: Album.t() | nil

@doc "Liste albums publiés (tri chronologique)"
@spec list_published() :: [Album.t()]

@doc "Liste albums en attente de publication"
@spec list_pending_publication() :: [Album.t()]

@doc "Liste albums soft deleted"
@spec list_soft_deleted() :: [Album.t()]

@doc "Met à jour album"
@spec update(Album.t(), map()) :: {:ok, Album.t()} | {:error, Ecto.Changeset.t()}

@doc "Ajoute photographies à album"
@spec ajouter_photographies(Album.t(), [binary()]) :: {:ok, Album.t()} | {:error, term()}

@doc "Retire photographie de album"
@spec retirer_photographie(Album.t(), binary()) :: {:ok, Album.t()} | {:error, term()}

@doc "Soft delete album"
@spec soft_delete(Album.t()) :: {:ok, Album.t()} | {:error, term()}

@doc "Restaure album soft deleted"
@spec restore(binary()) :: {:ok, Album.t()} | {:error, term()}

@doc "Hard delete album"
@spec hard_delete(Album.t()) :: {:ok, Album.t()} | {:error, term()}
```

### ProjetRepository

```elixir
@doc "Crée nouveau projet"
@spec create(map()) :: {:ok, Projet.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère projet par ID avec associations"
@spec get(binary()) :: Projet.t() | nil

@doc "Récupère projet par slug"
@spec get_by_slug(String.t()) :: Projet.t() | nil

@doc "Liste projets racines publiés (parent_id NULL)"
@spec get_racines_publiees() :: [Projet.t()]

@doc "Liste enfants d'un projet"
@spec get_enfants(binary()) :: [Projet.t()]

@doc "Récupère ancêtres (chemin racine → actuel)"
@spec get_ancetres(Projet.t()) :: [Projet.t()]

@doc "Met à jour projet"
@spec update(Projet.t(), map()) :: {:ok, Projet.t()} | {:error, Ecto.Changeset.t()}

@doc "Attache projet à nouveau parent (validation cycle)"
@spec attacher_a_parent(Projet.t(), binary()) :: 
  {:ok, Projet.t()} | {:error, :cycle_detecte | term()}

@doc "Détache projet (devient racine)"
@spec detacher_projet(Projet.t()) :: {:ok, Projet.t()} | {:error, term()}

@doc "Vérifie si projet peut être supprimé (aucun enfant)"
@spec peut_etre_supprime?(binary()) :: boolean()

@doc "Soft delete projet"
@spec soft_delete(Projet.t()) :: {:ok, Projet.t()} | {:error, term()}

@doc "Restaure projet soft deleted"
@spec restore(binary()) :: {:ok, Projet.t()} | {:error, term()}

@doc "Hard delete projet"
@spec hard_delete(Projet.t()) :: {:ok, Projet.t()} | {:error, term()}
```

### PhotoUploadService

```elixir
@doc """
Upload fichier et associe à collection (album ou projet).
Détecte doublons par empreinte, lance traitement variantes.
"""
@spec upload_et_associer(
  fichier_binary :: binary(),
  attrs :: map(),
  collection_id :: binary(),
  collection_type :: :album | :projet
) :: {:ok, Photographie.t()} | {:error, term()}

@doc "Calcule empreinte SHA256"
@spec calculer_empreinte(binary()) :: {:ok, binary()}

@doc "Obtient ou crée photographie (détection doublon)"
@spec obtenir_ou_creer_photographie(binary(), binary(), map()) :: 
  {:ok, Photographie.t()} | {:error, term()}
```

### AlbumPublicationService

```elixir
@doc """
Publie album si validation OK, sinon met en pending_publication.
Émet Domain Event AlbumPublié.
"""
@spec publier(binary()) :: 
  {:ok, Album.t()} | {:ok, :pending_publication} | {:error, term()}

@doc "Dépublie album"
@spec depublier(binary()) :: {:ok, Album.t()} | {:error, term()}

@doc "Programme publication différée (si photos en traitement)"
@spec programmer_publication_differee(binary()) :: {:ok, Oban.Job.t()}
```

### ProjetPublicationService

```elixir
@doc """
Publie projet avec cascade parents (tous parents doivent être publiés).
Émet Domain Event ProjetPublié.
"""
@spec publier(binary()) :: {:ok, Projet.t()} | {:error, term()}

@doc """
Dépublie projet avec cascade enfants (tous enfants dépubliés).
"""
@spec depublier(binary()) :: {:ok, Projet.t()} | {:error, term()}

@doc "Publie parents si nécessaire (récursif)"
@spec publier_parents_si_necessaire(Projet.t()) :: {:ok, [binary()]} | {:error, term()}

@doc "Dépublie enfants (récursif)"
@spec depublier_enfants(binary()) :: {:ok, integer()}
```

### ProjetHierarchyService

```elixir
@doc "Construit arbre complet projets publiés (avec cache)"
@spec construire_arbre_complet() :: [map()]

@doc "Génère breadcrumb (chemin racine → actuel)"
@spec get_breadcrumb(binary()) :: [Projet.t()]

@doc "Vérifie si déplacement crée cycle"
@spec peut_deplacer?(binary(), binary()) :: boolean()

@doc "Invalide cache arbre"
@spec invalider_cache() :: :ok
```

**DateAlbum** : Date avec précision variable (année seule ou année+mois).

### Repositories

**PhotographieRepository**
- Gestion CRUD Photographies
- Recherche par empreinte (détection doublons)
- Listing photographies orphelines (aucune référence)
- Soft delete et hard delete

**AlbumRepository**
- Gestion CRUD Albums
- Recherche par slug
- Listing albums publiés (tri chronologique)
- Gestion associations photographies (N-N)

**ProjetRepository**
- Gestion CRUD Projets
- Recherche projets racines (parent_id NULL)
- Listing enfants d'un projet
- Récupération ancêtres (breadcrumb)
- Attachement/détachement parent
- Détection cycles hiérarchie

### Domain Services

**PhotoUploadService**
- Upload fichier binaire
- Calcul empreinte SHA256
- Détection doublon (réutilisation si empreinte identique)
- Création associations album/projet
- Déclenchement traitement variantes (job Oban)

**AlbumPublicationService**
- Validation règles publication
- Changement statut (draft → published ou pending_publication)
- Émission Domain Event AlbumPublié
- Programmation publication différée si photos en traitement

**ProjetPublicationService**
- Validation règles publication
- Publication cascade parents (tous parents doivent être publiés)
- Changement statut
- Émission Domain Event ProjetPublié
- Dépublication cascade enfants

**ProjetHierarchyService**
- Construction arbre complet (navigation)
- Génération breadcrumb (chemin racine → actuel)
- Validation déplacements (détection cycles)
- Mise à jour profondeur enfants (récursif)

## Règles Métier (Invariants)

### Photographie

**PM-001 : Unicité empreinte**
- Contrainte : Une seule photographie par empreinte SHA256
- Implémentation : Index unique sur colonne empreinte
- Validation : Vérification avant insert, réutilisation si existe

**PM-002 : Partage N-N**
- Règle : Une photographie peut appartenir à plusieurs albums et projets
- Implémentation : Tables de jointure album_photographies, projet_photographies
- Conséquence : Suppression album ne supprime pas photographie

**PM-003 : Contrainte suppression**
- Règle : Impossible de supprimer photographie si références existent
- Validation : Compter références avant delete
- Exception levée si count > 0

**PM-004 : Soft delete 7 jours**
- Règle : Marquage deleted_at lors suppression, conservation 7 jours
- Cleanup automatique : Job Oban HardDeletePhotographieWorker (scheduled +7 jours)
- Queries filtrées : WHERE deleted_at IS NULL

### Album

**PM-005 : Règle publication album**
Conditions obligatoires :
- Minimum 1 photographie associée
- Titre présent (3-255 chars)
- Description présente (7-8191 chars)
- Date présente (année ou année+mois)
- Toutes photographies en état completed

Si conditions non remplies (photos en processing) :
- Statut → pending_publication
- Job Oban vérifie périodiquement
- Publication automatique dès que toutes photos completed

**PM-006 : Recommandation quantité**
- Recommandation non bloquante : 5 à 30 photographies
- Validation warning uniquement (pas d'erreur)

**PM-007 : Ordre photographies**
- Par défaut : chronologique (date_prise ou date_upload)
- Override manuel : colonne position dans album_photographies
- Position indexée pour performance

**PM-008 : Couverture automatique**
- Par défaut : première photographie de l'album
- Override manuel : sélection photographie spécifique
- Contrainte : couverture doit appartenir à l'album

### Projet

**PM-009 : Règle publication projet**
Conditions obligatoires :
- (Minimum 1 photographie OU minimum 1 sous-projet)
- Titre présent
- Description présente
- Si photos : toutes en état completed
- Tous parents publiés (cascade up automatique)

**PM-010 : Hiérarchie illimitée**
- Profondeur maximale : aucune limite technique
- Détection cycles : obligatoire (trigger DB + validation app)
- Calcul profondeur : automatique lors insert/update

**PM-011 : Contrainte suppression projet**
- Règle : Impossible de supprimer projet si sous-projets existent
- Validation : Compter enfants WHERE parent_id = projet.id
- Exception levée si count > 0

**PM-012 : Publication cascade parents**
- Règle : Si projet publié, tous parents doivent être publiés
- Implémentation : Récursion vers racine, publication automatique parents
- Conséquence : Publication enfant peut publier toute branche parente

**PM-013 : Dépublication cascade enfants**
- Règle : Dépublication projet dépublie tous sous-projets
- Implémentation : Récursion vers feuilles, dépublication automatique
- Conséquence : Cohérence hiérarchie (pas de projet publié avec parent dépublié)

## Domain Events

### Cycle de vie Photographie

**PhotographieAjoutée**
- Données : photographie_id, empreinte, titre, metadata, associée_à (album/projet)
- Déclenche : Job ImageVariantWorker

**PhotographieTraitée**
- Données : photographie_id, variantes (4 URLs), durée_traitement
- Déclenche : Vérification publication parent si pending_publication

**PhotographieModifiée**
- Données : photographie_id, ancien_titre, nouveau_titre
- Déclenche : Invalidation cache

**PhotographieDépubliée**
- Données : photographie_id, retirée_de (liste albums/projets)

**PhotographieSuppriméeSoft**
- Données : photographie_id, date_suppression_définitive (+7j)
- Déclenche : Job HardDeletePhotographieWorker (delayed 7 jours)

**PhotographieSuppriméeHard**
- Données : photographie_id, fichiers_supprimés (liste URLs variantes)

### Cycle de vie Album

**AlbumCréé**
- Données : album_id, titre, slug, date, utilisateur_id, statut (draft)

**AlbumPublié**
- Données : album_id, titre, slug, url_public, nombre_photos, couverture_url
- Diffusé vers : Communication Context (notifications abonnés)
- Déclenche : Invalidation cache albums_published

**AlbumDépublié**
- Données : album_id, raison (optionnel)

**AlbumSuppriméSoft**
- Données : album_id, nombre_photos_déréférencées, date_suppression_définitive
- Déclenche : Job HardDeleteAlbumWorker + vérification photos orphelines

**AlbumSuppriméeHard**
- Données : album_id, photographies_orphelines (liste IDs à nettoyer)

### Cycle de vie Projet

**ProjetCréé**
- Données : projet_id, titre, slug, parent_id, profondeur, utilisateur_id

**ProjetAttaché**
- Données : projet_id, ancien_parent_id, nouveau_parent_id, nouvelle_profondeur
- Déclenche : Mise à jour profondeur enfants (récursif)

**ProjetPublié**
- Données : projet_id, titre, slug, parent_id, url_public, nombre_photos, nombre_sous_projets, parents_publiés (cascade)
- Diffusé vers : Communication Context
- Déclenche : Invalidation cache projets_hierarchy

**ProjetDépublié**
- Données : projet_id, sous_projets_dépubliés (cascade)

**ProjetSuppriméSoft**
- Données : projet_id, nombre_photos_déréférencées

**ProjetSuppriméHard**
- Données : projet_id, photographies_orphelines

## Patterns Appliqués

### Composite Pattern (Projets)

Structure récursive permettant hiérarchie illimitée :
- Un Projet contient des Photographies (feuilles)
- Un Projet contient des Sous-Projets (composites)
- Interface uniforme (Publication, Dépublication)

Implémentation :
- Self-reference via parent_id
- Profondeur dénormalisée (performance)
- Détection cycles (trigger + validation app)

### Repository Pattern

Abstraction persistence séparant domaine et infrastructure :
- Aggregates : logique métier pure
- Repositories : accès données, requêtes complexes
- Testabilité via mocks

### Soft Delete Pattern

Protection suppressions accidentelles :
- Colonne deleted_at (nullable)
- Soft delete : UPDATE deleted_at = NOW()
- Hard delete : DELETE physique après 7 jours (job Oban)
- Queries : WHERE deleted_at IS NULL

### Anti-Corruption Layer (Storage)

Port Storage abstrait implémentations :
- LocalStorage (développement)
- CloudflareStorage (production, ADR 044)

Permet changement stockage sans impact domaine.

## Dépendances Externes

### User Context
- Référence utilisateur_id (propriétaire albums/projets)
- Relation Customer-Supplier

### Communication Context
- Émission Domain Events (AlbumPublié, ProjetPublié)
- Relation Publisher-Subscriber

## Documents Liés

- Vue d'ensemble : docs/ddd/001_vue_ensemble.md
- Règles métier détaillées : docs/business_rules/001_photography_rules.md
- Event Storming : tmp/event_storming_complet.md (sections 1.1 à 1.3)
- Schéma DB : tmp/schema_database_ddd.sql (section 3)
- ADR 032 : Repository Pattern
- ADR 044 : CDN Strategy Cloudflare
