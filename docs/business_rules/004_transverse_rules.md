# 004 - Règles Métier Transversales

Date: 2025-11-12

Ce document détaille les règles métier transversales applicables à tous les contextes. Ces règles concernent l'architecture, la sécurité, et les patterns communs.

## RT-001 : Gestion Erreurs Domain Events

**Catégorie** : Règle architecture

**Description** : Comportement système si handler domain event échoue.

**Règle** : Échec handler ne bloque pas émetteur event (best-effort delivery).

**Implémentation** :
```elixir
# Émission event (Photography Context)
Phoenix.PubSub.broadcast(
  Portfolio.PubSub,
  "photography:events",
  {:album_published, album_data}
)
# → Retourne immédiatement, succès garanti

# Handler event (Communication Context)
def handle_info({:album_published, album_data}, state) do
  try do
    NotificationService.creer_notification_album(album_data)
  rescue
    error ->
      Logger.error("Échec handler AlbumPublished: #{inspect(error)}")
      # Pas de crash handler
  end
  
  {:noreply, state}
end
```

**Comportement** :
- Émetteur event : Publication non bloquante, retour immédiat
- Handler event : Try-catch global, logging erreurs
- Pas de retry automatique (events best-effort)
- Supervision : Si handler crash → restart automatique (OTP)

**Monitoring** : Alertes si taux erreurs handlers > 5%.

**Justification** :
- Découplage fort entre contextes
- Performance (pas d'attente handlers)
- Résilience (échec handler n'impacte pas émetteur)

**Alternative considérée** : Event sourcing avec replay (complexité non justifiée actuellement).

## RT-002 : Idempotence Repositories

**Catégorie** : Règle technique

**Description** : Opérations repository doivent être idempotentes quand possible.

**Règle** : create avec contrainte unique → retourner existant si collision.

**Exemple : PM-001 Empreinte Photographie**
```elixir
def create(attrs) do
  %Photographie{}
  |> Photographie.changeset(attrs)
  |> Repo.insert(on_conflict: :nothing, conflict_target: :empreinte)
  |> case do
    {:ok, photo} -> 
      {:ok, photo}
    {:error, changeset} ->
      # Si conflit empreinte, récupérer existante
      case Repo.get_by(Photographie, empreinte: attrs.empreinte) do
        nil -> {:error, changeset}
        existing -> {:ok, existing}
      end
  end
end
```

**Avantages** :
- Gestion gracieuse collisions
- Pas d'erreur si doublon (PM-001)
- Simplification logique métier

**Cas usage** :
- Upload même photo plusieurs fois → réutilisation
- Retry requête après timeout → pas de doublon

**Exceptions** : Règles métier requérant unicité stricte (email utilisateur).

## RT-003 : Transaction Boundaries

**Catégorie** : Règle architecture

**Description** : Opérations aggregate doivent être transactionnelles.

**Règle** : Modifications multiples tables même aggregate → Ecto.Multi.

**Exemple : PM-012 Publication Cascade Parents**
```elixir
def publier_avec_cascade(projet_id) do
  Multi.new()
  |> Multi.run(:parents, fn repo, _changes ->
    parents = get_ancetres_non_publies(projet_id)
    {:ok, parents}
  end)
  |> Multi.run(:publier_parents, fn repo, %{parents: parents} ->
    Enum.reduce_while(parents, {:ok, []}, fn parent, {:ok, acc} ->
      case update(parent, %{statut: :published}) do
        {:ok, updated} -> {:cont, {:ok, [updated | acc]}}
        {:error, changeset} -> {:halt, {:error, changeset}}
      end
    end)
  end)
  |> Multi.update(:publier_projet, fn %{parents: parents} ->
    projet = get(projet_id)
    Projet.changeset(projet, %{statut: :published})
  end)
  |> Multi.run(:emit_events, fn repo, %{publier_parents: parents, publier_projet: projet} ->
    Enum.each(parents, &emit_projet_publie/1)
    emit_projet_publie(projet)
    {:ok, :emitted}
  end)
  |> Repo.transaction()
  |> case do
    {:ok, %{publier_projet: projet}} -> {:ok, projet}
    {:error, _failed_operation, changeset, _changes} -> {:error, changeset}
  end
end
```

**Propriétés ACID** :
- Atomicité : Tout ou rien (rollback si échec)
- Cohérence : Invariants respectés
- Isolation : Transactions concurrentes isolées
- Durabilité : Commit persisté

**Cas usage** :
- Publication cascade (PM-012, PM-013)
- Soft delete avec références (PM-003)
- Création album avec photographies

**Isolation level** : READ COMMITTED (défaut PostgreSQL).

## RT-004 : Validation Permissions RBAC

**Catégorie** : Règle sécurité

**Description** : Vérification permissions avant opérations sensibles.

**Règle** : Admin uniquement pour création/modification/suppression albums/projets.

**Implémentation Router** :
```elixir
# lib/portfolio_web/router.ex
scope "/admin", PortfolioWeb.Admin do
  pipe_through [:browser, :require_authenticated_user, :require_admin]
  
  live "/albums", AlbumLive.Index, :index
  live "/albums/new", AlbumLive.New, :new
  live "/albums/:id/edit", AlbumLive.Edit, :edit
end
```

**Plug require_admin** :
```elixir
def require_admin(conn, _opts) do
  user = conn.assigns.current_scope.user
  
  if user.role == :admin do
    conn
  else
    conn
    |> put_flash(:error, "Accès refusé. Permissions insuffisantes.")
    |> redirect(to: "/")
    |> halt()
  end
end
```

**Validation niveau service** :
```elixir
def create_album(current_scope, attrs) do
  with :ok <- validate_admin(current_scope.user),
       {:ok, album} <- AlbumRepository.create(attrs) do
    {:ok, album}
  end
end

defp validate_admin(%{role: :admin}), do: :ok
defp validate_admin(_), do: {:error, "Permissions insuffisantes"}
```

**Double validation** :
1. Router : Bloque accès routes admin (HTTP 403)
2. Service : Vérifie permissions métier (sécurité défense en profondeur)

**Permissions par rôle** :
- admin : CRUD albums/projets/utilisateurs, publication, suppression
- user : Lecture contenus publiés uniquement

**Audit** : Logging tentatives accès non autorisées.

**Référence** : ADR-021 Role-Based Access Control.

## RT-005 : Classification Erreurs Domaine vs Techniques

**Catégorie** : Règle architecture

**Description** : Distinction claire entre erreurs métier (domaine) et erreurs techniques (infrastructure).

**Types d'erreurs** :

**Erreurs Domaine (DomainError)** :
- Violation règles métier (PM-XXX, PA-XXX, etc.)
- Validation métier échouée
- État invalide aggregate
- Exemples :
  - "Album doit contenir minimum 1 photo" (PM-005)
  - "Email déjà utilisé" (PU-001)
  - "Magic link expiré" (PA-002)

**Erreurs Techniques (TechnicalError)** :
- Erreur base de données (Ecto.QueryError)
- Timeout réseau
- Erreur système fichiers (File.Error)
- Erreur service externe (S3, EmailProvider)

**Implémentation** :
```elixir
defmodule Portfolio.DomainError do
  defexception [:message, :code, :details]
  
  def exception(opts) do
    %__MODULE__{
      message: Keyword.fetch!(opts, :message),
      code: Keyword.get(opts, :code),
      details: Keyword.get(opts, :details, %{})
    }
  end
end

# Usage
def publier_album(album_id) do
  album = get_album(album_id)
  
  if count_photos(album_id) == 0 do
    raise DomainError, 
      message: "Album doit contenir minimum 1 photo",
      code: :album_empty,
      details: %{album_id: album_id, rule: "PM-005"}
  end
  
  # ...
end
```

**Gestion erreurs** :
- DomainError : Message utilisateur clair, HTTP 422 Unprocessable Entity
- TechnicalError : Message générique, HTTP 500 Internal Server Error, logging détaillé

**Référence** : ADR existante sur gestion erreurs.

## RT-006 : Messages Erreur Internationalisés

**Catégorie** : Règle qualité

**Description** : Tous messages utilisateur doivent être traduits (i18n).

**Règle** : Utilisation Gettext pour internationalisation français/anglais.

**Structure** :
```
priv/gettext/
├── default.pot                    # Template messages
├── fr/LC_MESSAGES/default.po      # Traductions françaises
└── en/LC_MESSAGES/default.po      # Traductions anglaises
```

**Implémentation** :
```elixir
# Changeset erreur
def changeset(album, attrs) do
  album
  |> cast(attrs, [:titre])
  |> validate_required([:titre], message: dgettext("errors", "can't be blank"))
  |> validate_length(:titre, 
      min: 3, 
      message: dgettext("errors", "must be at least %{count} characters", count: 3)
    )
end

# Controller/LiveView
def handle_event("save", params, socket) do
  case AlbumService.create(socket.assigns.current_scope, params) do
    {:ok, album} ->
      {:noreply, 
        socket
        |> put_flash(:info, gettext("Album created successfully"))
        |> push_navigate(to: ~p"/admin/albums")}
    
    {:error, %DomainError{message: message}} ->
      {:noreply, put_flash(socket, :error, message)}
  end
end
```

**Messages clairs** :
- Explicites : "Titre trop court (minimum 3 caractères)"
- Pas de jargon technique : "Album must contain at least one photo"
- Actionnable : "Veuillez ajouter une photo avant publication"

**Langues supportées** :
- Français (défaut)
- Anglais

**Fallback** : Si traduction manquante → langue par défaut (français).

## RT-007 : Monitoring Utilisation Stockage

**Catégorie** : Règle opérationnelle

**Description** : Surveillance utilisation espace disque pour prévenir saturation.

**Métriques collectées** :
- Espace total utilisé (photos + variantes)
- Nombre fichiers stockés
- Espace par utilisateur (futur quota)
- Taille moyenne photo
- Croissance hebdomadaire

**Implémentation Telemetry** :
```elixir
defmodule Portfolio.StorageMetrics do
  def collect_metrics do
    storage_path = Application.get_env(:portfolio, :storage_path)
    
    metrics = %{
      total_size_bytes: calculate_directory_size(storage_path),
      total_files: count_files(storage_path),
      photos_count: Repo.aggregate(Photographie, :count),
      variants_per_photo: 4,  # 2 WebP + 2 AVIF
      average_photo_size: calculate_average_size()
    }
    
    :telemetry.execute(
      [:portfolio, :storage, :metrics],
      metrics,
      %{}
    )
    
    metrics
  end
end

# Scheduled job (daily)
defmodule Portfolio.Workers.StorageMetricsWorker do
  use Oban.Worker, queue: :monitoring
  
  @impl Oban.Worker
  def perform(_job) do
    metrics = Portfolio.StorageMetrics.collect_metrics()
    
    # Alert si > 80% capacité
    if metrics.total_size_bytes > disk_capacity() * 0.8 do
      notify_admin("Storage usage critical: #{metrics.total_size_bytes} bytes")
    end
    
    :ok
  end
end
```

**Dashboard monitoring** :
- Affichage utilisation stockage admin
- Graphique évolution temporelle
- Alertes si seuils dépassés

**Alertes** :
- Warning : > 80% capacité
- Critical : > 90% capacité
- Action : Nettoyage photos soft deleted, compression aggressive

**Quota futur** : Préparation quota utilisateur 20 GB (BR-033 POC).

---

## Règles Transversales Appliquées

### Tous les Contexts

**Logging structuré** : Logger.metadata pour traçabilité (request_id, user_id, context).

**Validation entrées** : Sanitization systématique inputs utilisateur (protection XSS, injection SQL via Ecto).

**Gestion timezone** : Toutes dates stockées UTC, conversion locale affichage uniquement.

**Soft delete global** : Colonne deleted_at sur toutes tables principales (albums, projets, photos, users).

**Audit trail** : Colonnes inserted_at, updated_at sur toutes tables (timestamps Ecto).

**UUID primary keys** : Toutes tables utilisent UUID v4 (sécurité, distribution).

### Performance

**N+1 queries** : Préchargement associations via Ecto preload (éviter lazy loading).

**Index database** : Index sur colonnes fréquemment requêtées (slug, empreinte, statut, deleted_at).

**Cache stratégique** : Cachex pour hiérarchies projets, contenus publiés (TTL 1h).

**Pagination** : Limite 50 items par défaut, curseur pour grandes collections.

### Sécurité

**Content Security Policy** : Headers CSP restrictifs (protection XSS).

**HTTPS only** : Redirection automatique HTTP → HTTPS en production.

**Cookie sécurisé** : HTTP-only, Secure, SameSite=Lax pour sessions.

**Rate limiting global** : Nginx limite 100 req/min par IP (protection DDoS basique).

**Input validation** : Validation stricte tous inputs (types, longueurs, formats).

**SQL injection** : Requêtes paramétrées uniquement (Ecto query binding).

## Documents Liés

- Vue d'ensemble : docs/ddd/001_vue_ensemble.md
- Photography Context : docs/ddd/002_photography_context.md
- Auth Context : docs/ddd/003_auth_context.md
- User Context : docs/ddd/004_user_context.md
- Communication Context : docs/ddd/005_communication_context.md
- ADR 021 : Role-Based Access Control
- ADR 032 : Repository Pattern
