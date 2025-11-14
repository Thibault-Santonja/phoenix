# ADR-021 : Role-Based Access Control (RBAC)

Statut: Accepté
Date: 2025-07

## Contexte

Le contrôle d'accès est un élément fondamental de toute application nécessitant une authentification. Il existe plusieurs approches pour gérer les autorisations :

- Role-Based Access Control (RBAC) : autorisations basées sur des rôles prédéfinis
- Attribute-Based Access Control (ABAC) : autorisations basées sur des attributs et des règles
- Access Control Lists (ACL) : listes d'autorisations par ressource
- Policy-Based Access Control : politiques déclaratives avec bibliothèques comme Bodyguard ou Canada

Pour ce portfolio personnel avec un nombre limité d'utilisateurs et des besoins d'autorisation simples, le choix s'est porté sur un système RBAC minimaliste avec deux rôles uniquement : `:admin` et `:user`.

## Décision

Le système utilise un modèle RBAC simplifié avec deux rôles définis au niveau du schéma User via Ecto.Enum. L'autorisation est vérifiée à trois niveaux (plugs, LiveView hooks, router) pour assurer une défense en profondeur.

### Architecture du système RBAC

#### 1. Modèle de rôles

Le schéma `Portfolio.Auth.User` définit les rôles possibles :

```elixir
schema "users" do
  field :email, :string
  field :name, :string
  field :role, Ecto.Enum, values: [:admin, :user], default: :user
  # ...
end
```

Rôles actuels :
- `:user` : utilisateur standard, accès limité (prévu pour newsletter future)
- `:admin` : administrateur, accès complet à l'interface d'administration

Justification de l'approche Ecto.Enum :
- Simplicité : pas besoin d'une table `roles` séparée pour deux rôles
- Performance : les rôles sont stockés directement dans la table users
- Pragmatisme : suffisant pour les besoins actuels du portfolio

#### 2. Vérification des autorisations multi-niveaux

Le système implémente une défense en profondeur avec trois niveaux de vérification :

##### Niveau 1 : Plugs pour Controllers

Le module `PortfolioWeb.Plugs.RequireAuth` fournit plusieurs plugs :

```elixir
# Récupération de l'utilisateur courant
plug RequireAuth, :fetch_current_user

# Vérification de l'authentification
plug RequireAuth, :require_authenticated_user

# Vérification du rôle admin
plug RequireAuth, :require_admin_role
```

Fonctionnalités clés :
- `fetch_current_user/2` : récupère l'utilisateur depuis la session avec cache Cachex (1h TTL)
- `require_authenticated_user/2` : redirige vers `/login` si non authentifié
- `require_admin_role/2` : vérifie `user.role in [:admin]`, redirige vers `/` sinon

##### Niveau 2 : LiveView hooks

Le module `PortfolioWeb.UserAuth` fournit des hooks `on_mount` pour les LiveViews :

```elixir
# Utilisateur optionnel (pages publiques)
on_mount: [{PortfolioWeb.UserAuth, :mount_current_user}]

# Authentification requise
on_mount: [{PortfolioWeb.UserAuth, :ensure_authenticated}]

# Redirection si déjà authentifié (page login)
on_mount: [{PortfolioWeb.UserAuth, :redirect_if_user_is_authenticated}]
```

Note importante : le hook `:ensure_authenticated` vérifie uniquement l'authentification, pas le rôle. La vérification du rôle admin est déléguée au niveau router via `live_session`.

##### Niveau 3 : Router avec pipelines

Le router `PortfolioWeb.Router` définit des pipelines spécialisées :

```elixir
# Pipeline pour pages d'authentification
pipeline :auth_pages do
  plug RequireAuth, :fetch_current_user
  plug RequireAuth, :redirect_if_user_is_authenticated
end

# Pipeline pour controllers admin
pipeline :require_authenticated_admin do
  plug RequireAuth, :fetch_current_user
  plug RequireAuth, :require_authenticated_user
  plug RequireAuth, :require_admin_role
end

# Pipeline pour LiveViews admin
pipeline :admin_live do
  # Auth gérée par on_mount
end
```

Configuration des routes admin :

```elixir
scope "/admin", PortfolioWeb.Admin, as: :admin do
  pipe_through :admin_live

  live_session :require_authenticated_admin,
    on_mount: [{PortfolioWeb.UserAuth, :ensure_authenticated}] do
    live "/", DashboardLive.Index, :index
    live "/users", UserLive.Index, :index
    # ...
  end
end
```

Observation : la vérification du rôle admin pour les LiveViews n'est actuellement pas implémentée dans le hook `on_mount`. Le système repose sur la convention que seules les routes sous `/admin` nécessitent le rôle admin, mais il n'y a pas de vérification programmatique dans `UserAuth.ensure_authenticated/4`.

#### 3. Assignation et modification des rôles

##### Attribution initiale des rôles

Tout nouvel utilisateur créé reçoit par défaut le rôle `:user` :

```elixir
def registration_changeset(user, attrs) do
  user
  |> cast(attrs, [:email, :name])
  |> validate_required([:email])
  |> validate_email()
  |> put_change(:role, :user)  # Rôle par défaut
  |> unique_constraint(:email)
end
```

En production, la création automatique d'utilisateurs est désactivée. Seuls les utilisateurs existants peuvent s'authentifier via magic link.

##### Bootstrap de l'admin initial

Le premier administrateur est créé automatiquement au démarrage via :

1. Seeds (`priv/repo/seeds.exs`) : crée/promeut l'admin avec email configuré
2. Bootstrap Worker (`Portfolio.Bootstrap.Worker`) : exécute le bootstrap au démarrage avec retry automatique

Configuration de l'email admin :
- Variable d'environnement `ADMIN_EMAIL` en production
- Valeur par défaut : `thibault.santonja@pm.me`

Le bootstrap utilise `User.bootstrap_admin_changeset/2`, le seul changeset autorisant la création directe d'un utilisateur avec rôle `:admin`.

##### Modification des rôles par l'admin

L'interface admin (`/admin/users`) permet aux administrateurs de :
- Modifier le rôle d'un utilisateur (`:user` ↔ `:admin`)
- Modifier le nom d'un utilisateur
- Supprimer un utilisateur
- Révoquer toutes les sessions d'un utilisateur

La modification s'effectue via `Auth.update_user_as_admin/2` qui utilise `User.admin_changeset/2` :

```elixir
def admin_changeset(user, attrs) do
  user
  |> cast(attrs, [:role, :name])
  |> validate_required([:role])
  |> validate_inclusion(:role, [:admin, :user])
  |> validate_length(:name, min: 2, max: 100)
end
```

Note : l'email n'est jamais modifiable pour des raisons de sécurité et de principe de responsabilité unique (SRP).

### Permissions et restrictions

#### Permissions actuelles

Le système actuel n'implémente pas de permissions granulaires. Les autorisations sont binaires :

- Rôle `:user` : accès limité (prévu pour newsletter future)
- Rôle `:admin` : accès complet à toutes les fonctionnalités d'administration
  - Gestion des albums
  - Gestion des photos
  - Gestion des utilisateurs
  - Modification des rôles
  - Suppression d'utilisateurs
  - Accès aux métriques LiveDashboard

Justification : pour un portfolio personnel avec utilisateurs limités, un système de permissions granulaires (ex: `can_create_album`, `can_delete_photo`) serait de la sur-ingénierie (principe YAGNI - You Aren't Gonna Need It).

## Problèmes identifiés et recommandations

### 1. Absence de vérification du rôle admin dans les LiveView hooks

Problème : le hook `UserAuth.ensure_authenticated/4` vérifie uniquement l'authentification, pas le rôle admin. Il repose sur la convention que les routes sous `/admin` sont réservées aux admins, mais sans validation programmatique.

Risque : si une route admin est mal configurée dans le router, un utilisateur simple pourrait y accéder.

Recommandation :
- Créer un hook dédié `:require_admin_role` dans `UserAuth`
- Utiliser ce hook dans la `live_session :require_authenticated_admin`
- Alternative : combiner les vérifications dans un hook unique `:ensure_admin`

Priorité : moyenne (le système actuel fonctionne grâce aux conventions de routing strictes)

### 2. Auto-modification des rôles possible

Problème : un administrateur peut actuellement modifier son propre rôle via l'interface `/admin/users`. Rien n'empêche un admin de se rétrograder en `:user`.

Risque : un admin pourrait accidentellement se retirer ses droits, ou un compte admin compromis pourrait être rétrogradé par l'attaquant.

Recommandation :
- Ajouter une validation dans `UserLive.Index.handle_event("save_user", ...)` :
  ```elixir
  if user.id == socket.assigns.current_user.id do
    {:noreply, put_flash(socket, :error, "Vous ne pouvez pas modifier votre propre rôle")}
  else
    # Procéder à la modification
  end
  ```

Priorité : haute (protection de base contre erreurs humaines et compromission)

### 3. Suppression du dernier admin possible (VIOLATION PU-006 - URGENT)

**Statut : RÈGLE MÉTIER NON IMPLÉMENTÉE**

Problème : rien n'empêche actuellement la suppression du dernier administrateur du système, y compris l'admin initial créé via le bootstrap. Cela viole la Business Rule **PU-006 : Admin unique** qui stipule "Au moins un admin doit exister. Impossible de supprimer dernier admin."

Risque : si le dernier admin est supprimé, l'accès à l'interface d'administration devient impossible. Il faudrait intervenir manuellement en base de données ou via un script pour recréer un admin.

Implémentation obligatoire (URGENT) :
- Avant suppression, vérifier que ce n'est pas le dernier admin :
  ```elixir
  def handle_event("delete_user", %{"user-id" => user_id}, socket) do
    user = Enum.find(socket.assigns.users, &(&1.id == user_id))

    if user.role == :admin && Auth.count_admin_users() == 1 do
      {:noreply, put_flash(socket, :error, "Impossible de supprimer le dernier administrateur")}
    else
      # Procéder à la suppression
    end
  end
  ```
- Alternative plus stricte : interdire la suppression de l'admin bootstrap spécifiquement :
  ```elixir
  bootstrap_admin_email = System.get_env("ADMIN_EMAIL") || "thibault.santonja@pm.me"

  if user.email == bootstrap_admin_email do
    {:noreply, put_flash(socket, :error, "L'administrateur principal ne peut pas être supprimé")}
  else
    # Procéder à la suppression
  end
  ```

Priorité : **CRITIQUE - URGENT** (violation Business Rule PU-006, protection contre verrouillage du système)

Référence : docs/ddd/004_user_context.md - PU-006

### 4. Absence de logs d'audit

Problème : aucun système de logs d'audit n'est actuellement implémenté. Les actions sensibles suivantes ne sont pas tracées :
- Modification de rôle d'un utilisateur
- Création/suppression d'utilisateurs
- Révocation de sessions
- Connexions/déconnexions

Risque : en cas de problème de sécurité ou d'erreur administrative, impossible de retracer qui a fait quoi et quand.

Recommandation :
- Court terme : ajouter des logs simples via `Logger.info` dans les fonctions critiques :
  ```elixir
  def update_user_as_admin(user, attrs) do
    Logger.info("Admin action: updating user #{user.id} with attrs: #{inspect(attrs)}")
    # ... reste du code
  end
  ```
- Moyen terme : implémenter un système d'audit dédié avec table `audit_logs` :
  ```elixir
  schema "audit_logs" do
    field :action, :string
    field :resource_type, :string
    field :resource_id, :binary_id
    field :changes, :map
    belongs_to :performed_by, User
    timestamps(updated_at: false)
  end
  ```
- Long terme : utiliser une bibliothèque d'audit comme `PaperTrail` ou `Ecto.Audit`

Priorité : moyenne (nice-to-have pour traçabilité, pas critique pour la sécurité immédiate)

### 5. Séparation de la logique d'autorisation

Observation : la logique d'autorisation est actuellement dupliquée entre `RequireAuth` (plugs pour controllers) et `UserAuth` (hooks pour LiveViews).

Analyse :
- Avantages actuels :
  - Séparation claire entre Controller et LiveView (respect des conventions Phoenix)
  - Chaque module a une responsabilité unique
- Inconvénients :
  - Duplication de logique (récupération de session, vérification d'authentification)
  - Risque de divergence entre les deux implémentations
  - Maintenance plus complexe (changements à répliquer)

Recommandation :
- Extraire la logique commune dans un module dédié `Portfolio.Auth.Authorization` :
  ```elixir
  defmodule Portfolio.Auth.Authorization do
    def get_current_user(session_token) do
      # Logique commune de récupération
    end

    def authenticated?(user), do: user != nil
    def admin?(user), do: user && user.role == :admin
  end
  ```
- Faire appel à ce module depuis `RequireAuth` et `UserAuth`

Priorité : basse (optimisation technique, pas de bug ou risque de sécurité)

## Alternatives considérées

### Système de permissions granulaires

Approche :
- Table `permissions` avec permissions comme `create_album`, `delete_photo`, `manage_users`
- Table de jointure `user_permissions` ou `role_permissions`
- Vérification via `user_has_permission?(user, :create_album)`

Avantages :
- Flexibilité maximale pour gérer des autorisations fines
- Séparation des rôles et des permissions (un rôle peut avoir plusieurs permissions)
- Évolutivité pour cas d'usage complexes

Inconvénients :
- Complexité accrue (3 tables, logique de vérification plus complexe)
- Over-engineering pour un portfolio personnel
- Maintenance plus lourde

Décision : rejeté pour l'instant selon le principe YAGNI. Pourra être ajouté à l'avenir si les besoins évoluent.

### Bibliothèques de politiques (Bodyguard, Canada)

Approche :
- Définir des politiques déclaratives pour chaque ressource
- Vérification via `Bodyguard.permit?(user, :delete, photo)`

Avantages :
- Approche idiomatique Elixir
- Politiques testables indépendamment
- Logique d'autorisation centralisée

Inconvénients :
- Dépendance externe supplémentaire
- Courbe d'apprentissage
- Complexité inutile pour deux rôles simples

Décision : rejeté pour l'instant. Pourra être considéré si le système de permissions devient plus complexe.

### Table roles séparée

Approche :
- Table `roles` avec id, name, description
- Relation `belongs_to :role` dans User
- Possibilité d'ajouter des rôles dynamiquement

Avantages :
- Plus évolutif pour ajouter de nouveaux rôles
- Métadonnées sur les rôles (description, permissions liées, etc.)
- Gestion des rôles via interface admin

Inconvénients :
- Complexité supplémentaire (jointure requise)
- Over-engineering pour deux rôles fixes
- Pas de besoin identifié pour des rôles dynamiques

Décision : rejeté selon le principe YAGNI. Ecto.Enum est suffisant pour les besoins actuels.

## Évolutions futures prévues

### Court terme (priorité haute)
1. Implémenter la protection contre auto-modification de rôle
2. Implémenter la protection contre suppression du dernier admin
3. Créer un hook dédié `:require_admin_role` pour les LiveViews

### Moyen terme (priorité moyenne)
1. Ajouter des logs d'audit pour les actions sensibles
2. Renommer le rôle `:user` en quelque chose de plus explicite (ex: `:subscriber`)
3. Ajouter de nouveaux rôles si nécessaire :
   - `:editor` : peut gérer les contenus mais pas les utilisateurs
   - `:viewer` : accès en lecture seule à l'admin

### Long terme (évolutions potentielles)
1. Implémenter un système de permissions granulaires si les besoins deviennent plus complexes
2. Considérer l'utilisation de Bodyguard ou Canada pour des politiques déclaratives
3. Implémenter un système d'audit complet avec table dédiée

## Conséquences

### Positives

- Système simple et pragmatique adapté aux besoins actuels
- Code facile à comprendre et à maintenir
- Performance optimale (pas de jointures, Ecto.Enum)
- Défense en profondeur avec trois niveaux de vérification
- Bootstrap automatique de l'admin au démarrage

### Négatives

- Absence de vérification programmatique du rôle admin dans les LiveView hooks (repose sur conventions de routing)
- Auto-modification de rôle possible (risque de sécurité identifié)
- Suppression du dernier admin possible (risque de verrouillage du système)
- Pas de logs d'audit pour traçabilité
- Duplication de logique entre `RequireAuth` et `UserAuth`

### Neutres

- Système non évolutif pour permissions granulaires (acceptable selon principe YAGNI)
- Deux rôles uniquement (suffisant pour besoins actuels)
- Approprié pour un portfolio personnel avec utilisateurs limités

## Références

- Documentation Phoenix plugs : https://hexdocs.pm/phoenix/plug.html
- Documentation Phoenix LiveView hooks : https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#on_mount/1
- OWASP Access Control : https://owasp.org/www-community/Access_Control
- Bodyguard : https://github.com/schrockwell/bodyguard
- Canada : https://github.com/jarednorman/canada
- Fichiers concernés :
  - `lib/portfolio/auth/user.ex`
  - `lib/portfolio_web/plugs/require_auth.ex`
  - `lib/portfolio_web/live/user_auth.ex`
  - `lib/portfolio_web/router.ex`
  - `lib/portfolio_web/live/admin/user_live/index.ex`
  - `lib/portfolio/bootstrap/bootstrap.ex`
  - `priv/repo/seeds.exs`
