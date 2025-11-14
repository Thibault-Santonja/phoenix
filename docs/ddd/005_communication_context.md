# 005 - Communication Context (Supporting Domain)

Date: 2025-11-12

## Responsabilités

Le Communication Context gère toutes les communications email du système. Responsabilités :
- Notifications transactionnelles (album publié, projet publié)
- Newsletter périodique avec contenu personnalisé
- Gestion abonnés avec double opt-in (RGPD)
- Envoi emails via abstraction provider

## Ubiquitous Language

**Notification** : Email transactionnel déclenché par un événement métier (publication album, projet).

**Newsletter** : Email périodique contenant du contenu personnalisé (texte, albums/projets récents, liens externes artistes).

**Abonné** : Personne inscrite aux notifications avec confirmation email (double opt-in).

**TypeNotification** : Catégorie notification (album_publie, projet_publie, newsletter).

**StatutEnvoi** : État envoi email (pending, sent, failed).

**TokenDésinscription** : Jeton unique permettant désinscription depuis email (lien unsubscribe).

**TokenConfirmation** : Jeton unique pour confirmer inscription abonné.

## Architecture

### Aggregates

```
┌───────────────────────────────────┐
│  Notification (Root)              │
│  - id: UUID                       │
│  - destinataire: Email            │
│  - type: Enum                     │
│  - sujet: String                  │
│  - contenu: HTML                  │
│  - statut: Enum                   │
│  - envoye_le: DateTime            │
│  - erreur: String (si failed)     │
└───────────────────────────────────┘

┌───────────────────────────────────┐
│  Newsletter (Root)                │
│  - id: UUID                       │
│  - titre: String                  │
│  - contenu_personnalise: Markdown │
│  - statut: Enum                   │
│  - date_envoi: DateTime           │
│  │                                 │
│  ├─► Albums inclus (N-N)          │
│  │                                 │
│  └─► Projets inclus (N-N)         │
└───────────────────────────────────┘

┌───────────────────────────────────┐
│  Abonné (Entity)                  │
│  - id: UUID                       │
│  - email: String (unique)         │
│  - statut: Enum                   │
│  - token_confirmation: UUID       │
│  - token_desinscription: UUID     │
│  - date_confirmation: DateTime    │
└───────────────────────────────────┘
```

### Entities

**Notification** : Aggregate Root représentant un email transactionnel.

**Newsletter** : Aggregate Root représentant une campagne email périodique.

**Abonné** : Entity standalone (pas de children) représentant un inscrit.

### Value Objects

**Email** : String validé format RFC 5322.

**TypeNotification** : Enum (album_publie, projet_publie, newsletter).

**StatutEnvoi** : Enum (pending = en attente job Oban, sent = envoyé avec succès, failed = échec).

**StatutAbonnement** : Enum (pending_confirmation = en attente clic, active = confirmé, unsubscribed = désinscrit).

**ContenuEmail** : HTML généré depuis template HEEx.

**TokenConfirmation** : UUID v4 unique pour confirmation inscription.

**TokenDésinscription** : UUID v4 unique pour désinscription (lien dans footer email).

### Diagrammes Aggregates Détaillés

```
┌──────────────────────────────────────────────────────────────────┐
│ Notification (Aggregate Root)                                    │
├──────────────────────────────────────────────────────────────────┤
│ Attributs:                                                       │
│  - id: UUID                                                      │
│  - destinataire: String (email)                                 │
│  - type: Enum (album_publie, projet_publie, newsletter)         │
│  - sujet: String                                                │
│  - contenu: Text (HTML)                                         │
│  - statut: Enum (pending, sent, failed)                         │
│  - envoye_le: DateTime                                          │
│  - erreur: String (nullable)                                    │
│  - inserted_at: DateTime                                         │
├──────────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                              │
│  + créer(destinataire, type, sujet, contenu) -> Notification    │
│  + marquer_envoyée() -> {:ok, Notification}                     │
│  + marquer_échec(erreur) -> {:ok, Notification}                 │
│  + est_envoyée?() -> boolean                                    │
│  + peut_réessayer?() -> boolean                                 │
├──────────────────────────────────────────────────────────────────┤
│ Invariants:                                                      │
│  [PC-001] Envoi asynchrone via Oban (pas synchrone)             │
│  [PC-002] Retry échecs temporaires (max 3 tentatives)           │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ Newsletter (Aggregate Root)                                      │
├──────────────────────────────────────────────────────────────────┤
│ Attributs:                                                       │
│  - id: UUID                                                      │
│  - titre: String                                                │
│  - contenu_personnalise: Text (Markdown)                        │
│  - statut: Enum (draft, scheduled, sent)                        │
│  - date_envoi: DateTime (programmée)                            │
│  - envoye_le: DateTime (effective)                              │
│  - nombre_destinataires: Integer                                 │
│  - taux_succes: Float                                           │
│  - inserted_at: DateTime                                         │
├──────────────────────────────────────────────────────────────────┤
│ Relations:                                                       │
│  - albums_inclus: [Album] (N-N via newsletter_albums)           │
│  - projets_inclus: [Projet] (N-N via newsletter_projets)        │
├──────────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                              │
│  + créer(titre, contenu) -> Newsletter                          │
│  + ajouter_album(album_id) -> {:ok, Newsletter}                 │
│  + ajouter_projet(projet_id) -> {:ok, Newsletter}               │
│  + programmer(date_envoi) -> {:ok, Newsletter}                  │
│  + envoyer() -> {:ok, Newsletter}                               │
│  + marquer_envoyée(stats) -> {:ok, Newsletter}                  │
│  + generer_html() -> String                                     │
├──────────────────────────────────────────────────────────────────┤
│ Invariants:                                                      │
│  [PC-003] Contenu personnalisé (texte + albums/projets + liens) │
│  [PC-004] Programmation future possible (date_envoi)            │
│  [PC-005] Envoi massif par batch (100 abonnés/batch)            │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│ Abonné (Entity standalone)                                       │
├──────────────────────────────────────────────────────────────────┤
│ Attributs:                                                       │
│  - id: UUID                                                      │
│  - email: String (unique)                                       │
│  - statut: Enum (pending_confirmation, active, unsubscribed)    │
│  - token_confirmation: UUID v4 (unique)                         │
│  - token_desinscription: UUID v4 (unique)                       │
│  - date_inscription: DateTime                                    │
│  - date_confirmation: DateTime (nullable)                        │
│  - date_desinscription: DateTime (nullable)                      │
├──────────────────────────────────────────────────────────────────┤
│ Méthodes Publiques:                                              │
│  + inscrire(email) -> Abonné                                    │
│  + confirmer() -> {:ok, Abonné}                                 │
│  + désinscrire() -> {:ok, Abonné}                               │
│  + est_actif?() -> boolean                                      │
│  + est_en_attente?() -> boolean                                 │
├──────────────────────────────────────────────────────────────────┤
│ Invariants:                                                      │
│  [PC-006] Double opt-in obligatoire (RGPD Art. 6.1.a)           │
│  [PC-007] Email unique                                           │
│  [PC-008] Désinscription facile (lien footer email)             │
│  [PC-009] Données minimales (email + dates seulement)           │
│  [PC-010] Droit accès et effacement (RGPD)                      │
└──────────────────────────────────────────────────────────────────┘

Relations:
  Newsletter →[N:N] Album (Photography Context, inclusion newsletter)
  Newsletter →[N:N] Projet (Photography Context, inclusion newsletter)
  Notification → [event listener] AlbumPublié (Photography Context)
  Notification → [event listener] ProjetPublié (Photography Context)
```

### Repositories

**NotificationRepository**
- Création notification
- Listing par type, statut, destinataire
- Statistiques envois (taux succès)

**NewsletterRepository**
- Création newsletter
- Programmation envoi (date future)
- Listing newsletters envoyées
- Gestion associations albums/projets inclus

**AbonnéRepository**
- Inscription nouvel abonné
- Recherche par email
- Recherche par token confirmation/désinscription
- Confirmation inscription (changement statut)
- Désinscription
- Listing abonnés actifs

### Domain Services

**NotificationService**
- Écoute Domain Events Photography (AlbumPublié, ProjetPublié)
- Génération contenu email depuis template
- Récupération liste destinataires (propriétaire + abonnés actifs)
- Création Notification (statut pending)
- Déclenchement job Oban SendNotificationWorker

**NewsletterService**
- Création newsletter avec contenu markdown personnalisé
- Sélection albums/projets à inclure
- Programmation envoi (date future)
- Génération contenu HTML avec preview albums/projets
- Envoi massif à tous abonnés actifs

**EmailSenderService**
- Abstraction envoi via EmailProvider (Port)
- Implémentations : Swoosh (prod), Mock (test)
- Retry automatique en cas échec temporaire
- Logging erreurs

## Règles Métier (Invariants)

### Notification

**PC-001 : Envoi asynchrone**
- Règle : Notifications envoyées via job Oban (pas synchrone)
- Objectif : Performance (pas de blocage requête HTTP)
- Implémentation : Création notification statut pending, job traite queue

**PC-002 : Retry échecs temporaires**
- Règle : Tentatives répétées si erreur temporaire (timeout réseau)
- Configuration Oban : max_attempts = 3, backoff exponentiel
- Statut final : failed si échec définitif après retries

### Newsletter

**PC-003 : Contenu personnalisé**
- Règle : Newsletter contient texte libre + sélection albums/projets + liens externes
- Format entrée : Markdown (contenu_personnalise)
- Format sortie : HTML généré avec template

**PC-004 : Programmation future**
- Règle : Newsletter peut être programmée à date future
- Implémentation : Oban job delayed (schedule_in)
- Statut : draft → scheduled → sent

**PC-005 : Envoi massif optimisé**
- Règle : Envoi par batch pour performance (éviter timeout)
- Implémentation : Traitement par groupe de 100 abonnés
- Suivi : Compteur succès/échecs par campagne

### Abonné

**PC-006 : Double opt-in obligatoire (RGPD)**
- Règle : Inscription nécessite confirmation par email
- Processus : Inscription → statut pending_confirmation → email envoyé → clic lien → statut active
- Conformité : Article 6(1)(a) RGPD (consentement explicite)

**PC-007 : Email unique**
- Contrainte : Un seul abonné par adresse email
- Implémentation : Index unique sur colonne email
- Validation : Vérification avant insert

**PC-008 : Désinscription facile**
- Règle : Lien désinscription dans footer de chaque email
- URL : /newsletter/unsubscribe?token={token_desinscription}
- Action : Changement statut active → unsubscribed
- Conservation : Email conservé avec statut (historique, pas suppression immédiate)

**PC-009 : Données minimales (RGPD)**
- Données collectées : email + date_inscription + date_confirmation
- Pas de données : nom, prénom, adresse IP, tracking ouverture
- Base légale : Consentement explicite

**PC-010 : Droit accès et effacement (RGPD)**
- Droit accès : Email avec lien vers page affichant données (email + dates)
- Droit effacement : Suppression définitive sur demande (pas soft delete pour abonnés)
- Délai : Traitement sous 30 jours

## Domain Events

### Événements écoutés (depuis Photography)

**AlbumPublié** (externe)
- Source : Photography Context
- Données reçues : album_id, titre, slug, url_public, couverture_url, utilisateur_id
- Action : Création Notification type album_publie pour propriétaire + abonnés

**ProjetPublié** (externe)
- Source : Photography Context
- Données reçues : projet_id, titre, slug, url_public, couverture_url, utilisateur_id
- Action : Création Notification type projet_publie

### Événements émis

**NotificationEnvoyée**
- Données : notification_id, type, destinataire, statut (sent/failed), erreur
- Utilisation : Statistiques, monitoring

**NewsletterProgrammée**
- Données : newsletter_id, date_envoi, nombre_abonnés
- Utilisation : Suivi campagnes

**NewsletterEnvoyée**
- Données : newsletter_id, envoyée_le, nombre_destinataires, taux_succès
- Utilisation : Analytics

**AbonnéInscrit**
- Données : abonné_id, email, token_confirmation, statut
- Déclenche : Envoi email confirmation

**AbonnementConfirmé**
- Données : abonné_id, email, confirmé_le
- Utilisation : Suivi conversions

**AbonnéDésinscrit**
- Données : abonné_id, email, désinscrit_le
- Utilisation : Analytics churn

## Patterns Appliqués

### Publisher-Subscriber (Event Listener)

Écoute événements Photography :
- Subscription Phoenix.PubSub "photography:events"
- Handler AlbumPublishedListener
- Handler ProjetPublishedListener
- Découplage : Communication ne dépend pas de Photography

### Anti-Corruption Layer (EmailProvider)

Port EmailProvider abstrait implémentations :
- Swoosh (production)
- Mock (tests)
- Interface uniforme : send_email(to, subject, body, opts)

Permet changement provider (Sendgrid, Mailgun, AWS SES) sans impact domaine.

### Repository Pattern

Abstraction persistence :
- NotificationRepository
- NewsletterRepository
- AbonnéRepository

### Template Pattern

Génération emails via templates HEEx :
- album_published.html.heex
- projet_published.html.heex
- newsletter.html.heex
- confirmation_email.html.heex

Variables injectées : %{titre: "...", url: "...", ...}

### Job Queue Pattern (Oban)

Envoi asynchrone via jobs :
- SendNotificationWorker (notification transactionnelle)
- SendNewsletterWorker (campagne newsletter)
- Retry automatique, backoff exponentiel

## Dépendances Externes

### Photography Context
- Écoute Domain Events (AlbumPublié, ProjetPublié)
- Récupère URLs albums/projets pour inclusion newsletter
- Relation Publisher-Subscriber

### User Context
- Référence utilisateur_id (propriétaire albums/projets)
- Récupère email utilisateur pour notification
- Relation Customer-Supplier

## Incohérences Actuelles

**État actuel :**
- Communication Context inexistant
- Notifications gérées directement dans Photography
- Pas de newsletter implémentée
- Pas de gestion abonnés

**État cible :**
- Créer Communication Context complet
- Extraire notifications de Photography
- Implémenter newsletter avec contenu personnalisé
- Implémenter gestion abonnés avec double opt-in

Priorité : Moyen (fonctionnalité future)

## API Publique (Signatures)

### NotificationRepository

```elixir
@doc "Crée nouvelle notification avec statut pending"
@spec create(map()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère notification par ID"
@spec get(binary()) :: Notification.t() | nil

@doc "Liste notifications par type"
@spec list_by_type(atom()) :: [Notification.t()]

@doc "Liste notifications par destinataire"
@spec list_by_destinataire(String.t()) :: [Notification.t()]

@doc "Liste notifications par statut"
@spec list_by_statut(atom()) :: [Notification.t()]

@doc "Marque notification comme envoyée"
@spec mark_sent(Notification.t(), DateTime.t()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}

@doc "Marque notification comme échec avec erreur"
@spec mark_failed(Notification.t(), String.t()) :: {:ok, Notification.t()} | {:error, Ecto.Changeset.t()}

@doc "Calcule statistiques envois (taux succès)"
@spec calcul_stats() :: %{total: integer(), sent: integer(), failed: integer(), taux_succes: float()}
```

### NewsletterRepository

```elixir
@doc "Crée nouvelle newsletter"
@spec create(map()) :: {:ok, Newsletter.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère newsletter par ID avec associations"
@spec get(binary()) :: Newsletter.t() | nil

@doc "Liste newsletters par statut"
@spec list_by_statut(atom()) :: [Newsletter.t()]

@doc "Liste newsletters envoyées (historique)"
@spec list_sent() :: [Newsletter.t()]

@doc "Met à jour statut newsletter"
@spec update_statut(Newsletter.t(), atom()) :: {:ok, Newsletter.t()} | {:error, Ecto.Changeset.t()}

@doc "Ajoute album à newsletter"
@spec add_album(Newsletter.t(), binary()) :: {:ok, Newsletter.t()} | {:error, Ecto.Changeset.t()}

@doc "Ajoute projet à newsletter"
@spec add_projet(Newsletter.t(), binary()) :: {:ok, Newsletter.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère albums inclus avec préchargement"
@spec preload_albums(Newsletter.t()) :: Newsletter.t()

@doc "Récupère projets inclus avec préchargement"
@spec preload_projets(Newsletter.t()) :: Newsletter.t()

@doc "Marque newsletter envoyée avec statistiques"
@spec mark_sent(Newsletter.t(), map()) :: {:ok, Newsletter.t()} | {:error, Ecto.Changeset.t()}
```

### AbonnéRepository

```elixir
@doc "Crée nouvel abonné avec statut pending_confirmation"
@spec create(map()) :: {:ok, Abonné.t()} | {:error, Ecto.Changeset.t()}

@doc "Récupère abonné par ID"
@spec get(binary()) :: Abonné.t() | nil

@doc "Récupère abonné par email"
@spec get_by_email(String.t()) :: Abonné.t() | nil

@doc "Récupère abonné par token confirmation"
@spec get_by_confirmation_token(String.t()) :: Abonné.t() | nil

@doc "Récupère abonné par token désinscription"
@spec get_by_unsubscribe_token(String.t()) :: Abonné.t() | nil

@doc "Liste abonnés actifs (confirmés)"
@spec list_active() :: [Abonné.t()]

@doc "Liste abonnés en attente confirmation"
@spec list_pending() :: [Abonné.t()]

@doc "Confirme inscription abonné"
@spec confirm(Abonné.t()) :: {:ok, Abonné.t()} | {:error, Ecto.Changeset.t()}

@doc "Désinscrit abonné"
@spec unsubscribe(Abonné.t()) :: {:ok, Abonné.t()} | {:error, Ecto.Changeset.t()}

@doc "Supprime abonné définitivement (RGPD droit effacement)"
@spec delete(Abonné.t()) :: {:ok, Abonné.t()} | {:error, Ecto.Changeset.t()}

@doc "Compte abonnés actifs"
@spec count_active() :: non_neg_integer()
```

### NotificationService

```elixir
@doc "Crée notification transactionnelle (écoute AlbumPublié)"
@spec creer_notification_album(map()) :: {:ok, Notification.t()} | {:error, String.t()}

@doc "Crée notification transactionnelle (écoute ProjetPublié)"
@spec creer_notification_projet(map()) :: {:ok, Notification.t()} | {:error, String.t()}

@doc "Récupère liste destinataires (propriétaire + abonnés actifs)"
@spec get_destinataires(binary()) :: [String.t()]

@doc "Génère contenu HTML depuis template"
@spec generer_contenu_html(atom(), map()) :: String.t()

@doc "Déclenche envoi via Oban"
@spec envoyer_notification(binary()) :: {:ok, Oban.Job.t()}
```

### NewsletterService

```elixir
@doc "Crée newsletter avec contenu personnalisé"
@spec creer_newsletter(String.t(), String.t()) :: {:ok, Newsletter.t()} | {:error, String.t()}

@doc "Ajoute album à newsletter"
@spec ajouter_album(binary(), binary()) :: {:ok, Newsletter.t()} | {:error, String.t()}

@doc "Ajoute projet à newsletter"
@spec ajouter_projet(binary(), binary()) :: {:ok, Newsletter.t()} | {:error, String.t()}

@doc "Programme envoi newsletter à date future"
@spec programmer_envoi(binary(), DateTime.t()) :: {:ok, Newsletter.t()} | {:error, String.t()}

@doc "Génère HTML complet avec preview albums/projets"
@spec generer_html_complet(binary()) :: String.t()

@doc "Envoie newsletter à tous abonnés actifs (par batch)"
@spec envoyer_newsletter(binary()) :: {:ok, map()} | {:error, String.t()}
```

### EmailSenderService

```elixir
@doc "Envoie email via provider (abstraction)"
@spec send_email(String.t(), String.t(), String.t(), keyword()) :: {:ok, term()} | {:error, String.t()}

@doc "Retry envoi en cas échec temporaire"
@spec retry_failed_email(binary()) :: {:ok, term()} | {:error, String.t()}

@doc "Valide format email destinataire"
@spec valid_email?(String.t()) :: boolean()
```

## Documents Liés

- Vue d'ensemble : docs/ddd/001_vue_ensemble.md
- Photography Context : docs/ddd/002_photography_context.md
- User Context : docs/ddd/004_user_context.md
- Schéma DB : tmp/schema_database_ddd.sql (section 4)
