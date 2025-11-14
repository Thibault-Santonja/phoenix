# ADR-022: Gestion des Sessions Utilisateur

Statut: Accepté
Date: 2025-07

## Contexte

Apr�s une authentification réussie via magic link, il est nécessaire de maintenir une session utilisateur pour éviter de redemander l'authentification � chaque requête. La gestion des sessions doit équilibrer plusieurs contraintes :

- Sécurité : empêcher le vol de session, limiter l'impact d'une compromission
- Expérience utilisateur : ne pas forcer des reconnexions trop fréquentes
- Performance : minimiser les requêtes � la base de données
- Scalabilité : supporter plusieurs appareils par utilisateur
- Maintenance : nettoyer automatiquement les sessions expirées

Plusieurs approches existent pour gérer les sessions :

- Sessions côté serveur avec tokens en DB (stockage persistant)
- Sessions JWT stateless (pas de stockage serveur)
- Sessions Redis (stockage en mémoire)
- Sessions Phoenix par défaut (cookie signé uniquement)

Ce projet utilise une approche hybride : tokens de session stockés en base de données avec cache Cachex pour optimiser les performances.

## Décision

Le syst�me utilise des sessions persistantes stockées en base de données avec les caractéristiques suivantes :
- Token cryptographiquement sécurisé de 32 bytes
- Expiration par inactivité (2 heures configurable)
- Prolongation automatique � chaque requête
- Cache Cachex (1h TTL) pour réduire la charge DB
- Nettoyage automatique via GenServer toutes les heures
- Support multi-device avec révocation sélective

### Architecture du syst�me de sessions

#### 1. Schéma UserSession

Le schéma `Portfolio.Auth.UserSession` modélise les sessions utilisateur :

```elixir
schema "user_sessions" do
  belongs_to :user, User
  field :token, :string
  field :last_activity_at, :utc_datetime
  timestamps(type: :utc_datetime, updated_at: false)
end
```

Champs principaux :
- `token` : identifiant unique de la session (32 bytes, Base64 URL-safe)
- `last_activity_at` : timestamp de la derni�re activité pour gérer l'expiration

Hachage des tokens :
- Les tokens sont automatiquement hachés via `hash_token/1` dans le changeset
- Utilisation de SHA-256 pour le hachage cryptographique

```elixir
def changeset(user_session, attrs) do
  user_session
  |> cast(attrs, [:user_id, :token, :last_activity_at])
  |> validate_required([:user_id, :token, :last_activity_at])
  |> hash_token()  # Hachage automatique du token
  |> unique_constraint(:token)
end

@spec hash_token_value(String.t()) :: String.t()
def hash_token_value(token) do
  :crypto.hash(:sha256, token)
  |> Base.encode16(case: :lower)
end

defp hash_token(%Ecto.Changeset{valid?: true, changes: %{token: token}} = changeset) do
  put_change(changeset, :token, hash_token_value(token))
end

defp hash_token(changeset), do: changeset
```

- `user_id` : référence � l'utilisateur avec cascade delete

Fonction clé :
- `expired?/1` : vérifie si la session a dépassé le délai d'inactivité configuré

#### 2. SessionService

Le service `Portfolio.Auth.SessionService` g�re le cycle de vie des sessions :

Création et récupération :
- `create_session/1` : crée une session avec token sécurisé apr�s connexion
- `get_session_by_token/1` : récup�re et valide une session (supprime si expirée)
- `get_session!/1` : récup�re une session par ID
- `list_user_sessions/1` : liste toutes les sessions d'un utilisateur

Maintenance :
- `update_session_activity/1` : met � jour `last_activity_at` pour prolonger la session
- `delete_session/1` : supprime une session (logout d'un appareil)
- `delete_all_user_sessions/1` : supprime toutes les sessions d'un utilisateur
- `delete_all_user_sessions_except/2` : logout des autres appareils uniquement
- `delete_expired_sessions/0` : nettoyage des sessions expirées (job périodique)

#### 3. Génération des tokens

Les tokens sont générés de mani�re cryptographiquement sécurisée :

```elixir
defp generate_token do
  :crypto.strong_rand_bytes(32)
  |> Base.url_encode64(padding: false)
end
```

Caractéristiques :
- 32 octets de données aléatoires via `:crypto.strong_rand_bytes/1`
- Encodage Base64 URL-safe sans padding
- Espace de clés : 2^256 possibilités (résistant aux attaques par force brute)
- Unicité garantie par contrainte `unique_constraint(:token)` en DB

Note sur le stockage :
- Les tokens sont hachés avec SHA-256 avant stockage en base de données (comme les mots de passe)
- Implémentation via `hash_token/1` dans `UserSession.changeset/2`
- Le token original est conservé en clair dans le cookie côté client uniquement
- Décision de hacher les tokens pour renforcer la sécurité :
  - En cas de compromission DB, les tokens ne sont pas directement exploitables
  - Les attaquants ne peuvent pas se connecter avec les hash stockés
  - Le cookie reste configuré avec `httponly` et `secure` (protection XSS/interception)
  - Invalidation possible via révocation manuelle si nécessaire
  - Léger overhead de hachage acceptable pour le gain de sécurité

#### 4. Configuration des durées

Deux durées distinctes sont configurées :

##### Durée d'inactivité de session (2 heures par défaut)

Configuration dans `config/config.exs` :
```elixir
config :portfolio, :auth,
  session_expiration_seconds: 2 * 60 * 60  # 2 heures
```

Cette durée détermine quand une session expire par inactivité. Si l'utilisateur n'effectue aucune requête pendant 2 heures, il devra se reconnecter.

Surcharge possible via variable d'environnement `SESSION_EXPIRATION_SECONDS` dans `config/runtime.exs`.

Justification du choix (2 heures) :
- Compromis entre sécurité (limite l'exposition d'une session volée) et UX
- Suffisant pour une session de travail continue
- En dessous des standards bancaires (15-30 min) mais adapté � un portfolio personnel
- Choix quelque peu arbitraire basé sur l'expérience utilisateur souhaitée

##### Durée maximale du cookie (24 heures)

Configuration dans `config/config.exs` :
```elixir
config :portfolio, :session,
  max_age_seconds: 24 * 60 * 60  # 24 heures
```

Cette durée détermine la durée de vie maximale du cookie dans le navigateur.

Interaction entre les deux durées :
- Si l'utilisateur est actif : `last_activity_at` est mis � jour � chaque requête, la session reste valide indéfiniment (jusqu'� 24h max)
- Si l'utilisateur est inactif : apr�s 2h sans activité, la session expire même si le cookie est encore valide
- Le cookie de 24h agit comme une limite supérieure : apr�s 24h, l'utilisateur doit se reconnecter même s'il est resté actif

Résultat en pratique :
- Session quasi-permanente pour un utilisateur actif (renouvellement automatique)
- Expiration apr�s 2h d'inactivité (sécurité)
- Reconnexion obligatoire apr�s 24h maximum (rotation des tokens)

#### 5. Prolongation automatique des sessions

La prolongation s'effectue � deux niveaux :

##### Niveau Plug (RequireAuth)

Le plug `RequireAuth.fetch_current_user/2` met � jour automatiquement `last_activity_at` � chaque requête authentifiée :

```elixir
defp assign_user_from_session(conn, session) do
  update_session_activity_async(session)

  conn
  |> assign(:current_user, session.user)
  |> assign(:current_session, session)
end

defp update_session_activity_async(session) do
  if Mix.env() == :test do
    Auth.update_session_activity(session)
  else
    Task.start(fn -> Auth.update_session_activity(session) end)
  end
end
```

Mécanisme :
- En test : synchrone pour garantir la cohérence des tests
- En production : asynchrone via `Task.start/1` pour ne pas bloquer la requête

Optimisation recommandée (throttling) :
```elixir
defp update_session_activity_async(session) do
  time_since_last_activity = DateTime.diff(DateTime.utc_now(), session.last_activity_at)

  # Mettre � jour seulement si > 5 minutes depuis derni�re activité
  if time_since_last_activity > 300 do
    if Mix.env() == :test do
      Auth.update_session_activity(session)
    else
      Task.start(fn -> Auth.update_session_activity(session) end)
    end
  end
end
```

Bénéfices du throttling :
- Réduit les écritures DB de ~90% (1 écriture toutes les 5 min au lieu de chaque requête)
- Maintient une précision suffisante pour l'expiration (marge de 5 min acceptable)
- Impact négligeable sur la sécurité (une session volée reste valide 5 min de plus maximum)

##### Niveau LiveView (UserAuth)

Le hook `UserAuth.mount_current_user/2` met également � jour l'activité lors du montage des LiveViews :

```elixir
defp mount_current_user(socket, session) do
  case session["session_token"] do
    nil ->
      assign(socket, :current_user, nil)

    session_token ->
      case Auth.get_session_by_token(session_token) do
        nil ->
          assign(socket, :current_user, nil)

        user_session ->
          Auth.update_session_activity(user_session)

          socket
          |> assign(:current_user, user_session.user)
          |> assign(:current_session, user_session)
      end
  end
end
```

#### 6. Cache Cachex pour optimisation

Le syst�me utilise Cachex pour mettre en cache les sessions et réduire la charge sur la base de données.

##### Configuration du cache

Dans `application.ex` :
```elixir
{Cachex, name: :portfolio_cache, limit: 1000}
```

Limite de 1000 entrées :
- Suffisant pour ~100 utilisateurs simultanés
- Chaque utilisateur = 1 session en cache
- Espace restant pour autres caches (albums, photos)
- Éviction LRU automatique si limite atteinte

##### Utilisation dans RequireAuth

```elixir
defp fetch_session_with_cache(session_token) do
  cache_key = {:session, session_token}

  case Cachex.fetch(:portfolio_cache, cache_key, fn ->
         get_session_for_cache(session_token)
       end) do
    {:ok, session} -> session
    {:commit, session} -> session
    {:ignore, nil} -> nil
    _ -> nil
  end
end

defp get_session_for_cache(session_token) do
  case Auth.get_session_by_token(session_token) do
    nil ->
      {:ignore, nil}  # Ne pas mettre en cache les sessions invalides

    session ->
      {:commit, session, ttl: :timer.hours(1)}  # Cache 1 heure
  end
end
```

TTL du cache : 1 heure
- Compromis entre performance et fraîcheur des données
- Les modifications de rôle/permissions se propagent en maximum 1h
- Invalidation manuelle lors des opérations critiques (révocation, changement de rôle)

##### Désactivation du cache en test

```elixir
if Mix.env() == :test do
  Auth.get_session_by_token(session_token)
else
  fetch_session_with_cache(session_token)
end
```

Raison : éviter la pollution du cache entre les tests et garantir la prévisibilité.

#### 7. Invalidation du cache

Le cache doit être invalidé dans plusieurs situations critiques :

##### Lors du logout

Dans `AuthController.logout/2` :
```elixir
if session_token do
  Cachex.del(:portfolio_cache, {:session, session_token})

  case Auth.get_session_by_token(session_token) do
    nil -> :ok
    session -> Auth.delete_session(session)
  end
end
```

##### Lors de la révocation par l'admin

Implémentation recommandée dans `Auth.delete_all_user_sessions/1` :
```elixir
def delete_all_user_sessions(%User{id: user_id}) do
  # Récupérer les tokens avant suppression pour invalider le cache
  tokens =
    UserSession
    |> where([s], s.user_id == ^user_id)
    |> select([s], s.token)
    |> Repo.all()

  # Supprimer les sessions
  result =
    UserSession
    |> where([s], s.user_id == ^user_id)
    |> Repo.delete_all()

  # Invalider le cache pour chaque token
  Enum.each(tokens, fn token ->
    Cachex.del(:portfolio_cache, {:session, token})
  end)

  result
end
```

Importance critique :
- Sans invalidation, une session révoquée reste active jusqu'� 1h (TTL du cache)
- Probl�me de sécurité : un admin qui révoque un utilisateur s'attend � un effet immédiat
- Même logique pour `delete_all_user_sessions_except/2`

##### Lors du changement de rôle

Implémentation recommandée dans `UserService.update_user_as_admin/2` :
```elixir
def update_user_as_admin(user, attrs) do
  result = user
  |> User.admin_changeset(attrs)
  |> Repo.update()

  case result do
    {:ok, updated_user} ->
      # Si changement de rôle, invalider toutes les sessions en cache
      if Map.get(attrs, "role") || Map.get(attrs, :role) do
        invalidate_user_sessions_cache(user.id)
      end
      {:ok, updated_user}
    error -> error
  end
end

defp invalidate_user_sessions_cache(user_id) do
  tokens =
    UserSession
    |> where([s], s.user_id == ^user_id)
    |> select([s], s.token)
    |> Repo.all()

  Enum.each(tokens, fn token ->
    Cachex.del(:portfolio_cache, {:session, token})
  end)
end
```

Importance critique :
- Sans invalidation, un utilisateur promu admin ou rétrogradé garde l'ancien rôle en cache pendant 1h
- Risque de sécurité : escalade ou perte de privil�ges non immédiate
- Alternative : recharger l'utilisateur � chaque requête (impact performance)

#### 8. Nettoyage automatique des sessions expirées

##### SessionCleaner GenServer

Le module `Portfolio.Auth.SessionCleaner` nettoie périodiquement les sessions expirées :

```elixir
use GenServer

@cleanup_interval_ms 60 * 60 * 1000  # 1 heure

def init(_opts) do
  schedule_cleanup()
  {:ok, %{}}
end

def handle_info(:cleanup, state) do
  perform_cleanup()
  schedule_cleanup()
  {:noreply, state}
end

defp perform_cleanup do
  case Auth.delete_expired_sessions() do
    {0, nil} ->
      Logger.debug("[SessionCleaner] No expired sessions to delete")
    {count, nil} ->
      Logger.info("[SessionCleaner] Deleted #{count} expired session(s)")
  end
end
```

Caractéristiques :
- GenServer simple et léger (faible empreinte mémoire)
- Nettoyage toutes les heures (configurable)
- Logs pour monitoring
- Gestion des erreurs avec rescue

Démarrage dans le supervision tree (`application.ex:26`) :
```elixir
Portfolio.Auth.SessionCleaner
```

Recommandations d'amélioration :

1. Réduire l'intervalle � 30 minutes :
```elixir
@cleanup_interval_ms 30 * 60 * 1000
```
Justification : avec expiration de 2h, les sessions expirées restent maximum 2h30 au lieu de 3h.

2. Migrer vers Oban.Plugins.Cron pour cohérence architecturale :
```elixir
# config/config.exs
config :portfolio, Oban,
  plugins: [
    {Oban.Plugins.Cron,
      crontab: [
        {"*/30 * * * *", Portfolio.Workers.CleanupExpiredSessionsWorker},
        {"0 2 * * *", Portfolio.Workers.CleanupExpiredMagicLinksWorker}
      ]
    }
  ]
```

Avantages Oban :
- Cohérence avec l'architecture existante (Oban déj� utilisé)
- Meilleure observabilité (Oban Web UI)
- Retry automatique en cas d'échec
- Configuration centralisée des jobs périodiques

##### Logique de suppression

Dans `SessionService.delete_expired_sessions/0` :
```elixir
def delete_expired_sessions do
  expiry_seconds = UserSession.session_expiration_seconds()

  expiry_date =
    DateTime.utc_now()
    |> DateTime.add(-expiry_seconds, :second)
    |> DateTime.truncate(:second)

  UserSession
  |> where([s], s.last_activity_at < ^expiry_date)
  |> Repo.delete_all()
end
```

Requête SQL simple et efficace : une seule requête DELETE avec clause WHERE.

#### 9. Support multi-device

Le syst�me supporte plusieurs sessions simultanées par utilisateur :

##### Cas d'usage

- Utilisateur connecté sur desktop + mobile
- Utilisateur avec plusieurs navigateurs
- Admin avec plusieurs onglets ouverts

##### Fonctionnalités

1. Liste des sessions actives :
```elixir
Auth.list_user_sessions(user.id)
# Retourne toutes les sessions triées par last_activity_at
```

2. Logout d'un appareil spécifique :
```elixir
Auth.delete_session(session)
# Supprime uniquement la session courante
```

3. Logout de tous les appareils :
```elixir
Auth.delete_all_user_sessions(user)
# Utile en cas de compromission suspectée
```

4. Logout des autres appareils :
```elixir
Auth.delete_all_user_sessions_except(user, current_session.id)
# Garde la session actuelle, révoque les autres
```

##### Interface admin

L'interface `/admin/users` permet de :
- Voir les utilisateurs et leurs informations
- Révoquer toutes les sessions d'un utilisateur via bouton "Revoke sessions"
- Implémenter via `UserLive.Index.handle_event("revoke_sessions", ...)`

Amélioration future recommandée :
- Afficher la liste des sessions actives par utilisateur avec détails :
  - Derni�re activité
  - User agent (navigateur/appareil)
  - Adresse IP
  - Bouton de révocation sélective
- Notification email lors de nouvelle connexion (détection d'activité suspecte)

#### 10. Sécurité du cookie de session

Le cookie Phoenix est configuré dans `endpoint.ex` :

```elixir
@session_options [
  store: :cookie,
  key: "_portfolio_key",
  signing_salt: "sisdz80o",
  same_site: "Lax",
  secure: true,          # HTTPS uniquement
  http_only: true,       # Inaccessible via JavaScript
  compress: true,
  max_age: 24 * 60 * 60
]
```

Flags de sécurité critiques :

##### `http_only: true`

Protection contre XSS (Cross-Site Scripting) :
- JavaScript ne peut pas lire le cookie via `document.cookie`
- Même si un attaquant injecte du JS malveillant, il ne peut pas voler le token de session
- Protection essentielle pour les applications web modernes

##### `secure: true`

Protection contre interception en transit :
- Le cookie n'est envoyé que sur connexions HTTPS
- Empêche l'interception du token en clair via HTTP
- Doit être activé en production

Note : en développement local (HTTP), ce flag peut poser probl�me. Solution :
```elixir
secure: Application.get_env(:portfolio, :env) == :prod
```

##### `same_site: "Lax"`

Protection contre CSRF (Cross-Site Request Forgery) :
- Le cookie n'est pas envoyé lors de requêtes cross-site (depuis un autre domaine)
- Exception : requêtes GET de navigation (pour permettre les liens externes)
- Compromis acceptable entre sécurité et UX

Alternatives :
- `"Strict"` : sécurité maximale mais UX dégradée (pas de cookie sur liens externes)
- `"None"` : pas de protection CSRF (� éviter)

Choix de `"Lax"` justifié pour un portfolio personnel avec navigation naturelle.

##### Headers de sécurité supplémentaires

Dans `endpoint.ex` via `put_secure_headers/2` :
- `Content-Security-Policy` : limite les sources de scripts/styles
- `X-Frame-Options: DENY` : empêche l'inclusion dans des frames (clickjacking)
- `X-Content-Type-Options: nosniff` : empêche le MIME sniffing
- `Strict-Transport-Security` : force HTTPS
- `X-XSS-Protection` : protection XSS navigateur (legacy)

#### 11. Cascade delete et suppression d'utilisateur

La contrainte de clé étrang�re est configurée avec cascade delete :

```sql
-- Migration 20251025182253_create_user_sessions.exs
add :user_id, references(:users, type: :binary_id, on_delete: :delete_all)
```

Comportement :
- Lors de la suppression d'un utilisateur via `Auth.delete_user(user)`
- Toutes les sessions associées sont automatiquement supprimées par Postgres
- Pas besoin d'appeler manuellement `delete_all_user_sessions/1`

Avantage :
- Garantie d'intégrité référentielle au niveau DB
- Pas de sessions orphelines en cas d'erreur applicative
- Simplicité du code (pas de logique de nettoyage manuel)

Note importante :
- Le cache Cachex n'est PAS automatiquement invalidé lors du cascade delete
- Recommandation : invalider le cache manuellement dans `UserService.delete_user/1` :
```elixir
def delete_user(user) do
  # Invalider le cache avant suppression
  invalidate_user_sessions_cache(user.id)

  Repo.delete(user)
end
```

#### 12. Événements domaine et monitoring

Le `SessionService` émet un événement `SessionCreated` lors de la création :

```elixir
defp publish_session_created_event(session, user) do
  expires_at = DateTime.add(session.last_activity_at, 30, :day)

  DomainEvents.publish(:session_created, %SessionCreated{
    session_id: session.id,
    user_id: user.id,
    email: user.email,
    created_at: session.inserted_at,
    expires_at: expires_at
  })
end
```

Utilisation actuelle :
- Événement capturé par les event handlers
- Logging basique
- Base pour analytics futures

Événements manquants recommandés :
- `SessionDeleted` : lors du logout volontaire
- `SessionRevoked` : lors de la révocation par un admin
- `SessionExpired` : lors du nettoyage automatique (optionnel)

Cas d'usage futurs :
- Notification email lors de nouvelle connexion (détection activité suspecte)
- Monitoring des patterns de connexion (analytics)
- Alertes en cas de tentatives de connexion multiples
- Tableau de bord d'activité utilisateur

## Alternatives considérées

### Sessions JWT (JSON Web Tokens)

Approche :
- Token stateless signé contenant les informations utilisateur
- Pas de stockage serveur nécessaire
- Vérification par signature cryptographique

Avantages :
- Scalabilité horizontale parfaite (pas d'état partagé)
- Pas de requêtes DB pour vérifier la session
- Indépendance des services (microservices friendly)

Inconvénients :
- Impossible de révoquer un token avant expiration
- Taille du token plus grande (payload + signature)
- Données utilisateur potentiellement obsol�tes (rôle, permissions)
- Gestion de la rotation des tokens complexe

Décision : rejeté car la révocation instantanée est critique pour ce projet (admin peut bannir un utilisateur).

### Sessions Redis

Approche :
- Stockage des sessions en mémoire Redis
- Expiration automatique via TTL Redis
- Performance maximale

Avantages :
- Tr�s rapide (mémoire vs disque)
- Expiration native (pas de job de nettoyage)
- Scalabilité horizontale avec Redis Cluster

Inconvénients :
- Dépendance externe supplémentaire (Redis)
- Complexité opérationnelle (backup, failover)
- Over-engineering pour un portfolio personnel avec trafic limité
- Coût additionnel en production

Décision : rejeté selon principe YAGNI. Cachex fournit un compromis suffisant avec cache mémoire local.

### Sessions Phoenix par défaut (cookie signé uniquement)

Approche :
- Toutes les données de session dans le cookie
- Pas de stockage serveur
- Signature pour garantir l'intégrité

Avantages :
- Simplicité maximale
- Pas de DB ni cache nécessaire
- Scalabilité parfaite

Inconvénients :
- Impossible de révoquer une session
- Taille du cookie limitée (4KB)
- Données sensibles dans le cookie (même si signées)
- Pas de traçabilité des sessions actives

Décision : rejeté car la révocation est une exigence fonctionnelle (interface admin).

## Probl�mes identifiés et correctifs

### 1. Cookie manquant `httponly` et `secure` (CRITIQUE)

Probl�me initial : le cookie ne spécifiait pas les flags de sécurité critiques.

Risque :
- Sans `httponly` : XSS peut voler le token de session
- Sans `secure` : token interceptable en HTTP

Correctif appliqué :
```elixir
@session_options [
  # ... autres options
  secure: true,
  http_only: true
]
```

Priorité : CRITIQUE (corrigé)

### 2. Cache non invalidé lors de révocation admin (HAUTE)

Probl�me initial : lors de la révocation via `/admin/users`, le cache Cachex n'était pas invalidé.

Risque : session révoquée reste active jusqu'� 1h (TTL cache).

Correctif appliqué : ajout de l'invalidation dans `delete_all_user_sessions/1` et `delete_all_user_sessions_except/2`.

Priorité : HAUTE (corrigé)

### 3. Rôle utilisateur pas rechargé apr�s modification (HAUTE)

Probl�me initial : changement de rôle non reflété immédiatement (cache 1h).

Risque : escalade ou perte de privil�ges non immédiate.

Correctif appliqué : invalidation du cache lors du changement de rôle dans `update_user_as_admin/2`.

Priorité : HAUTE (corrigé)

### 4. Tokens hachés avec SHA-256 (implémenté)

Observation : les tokens de session sont maintenant hachés avec SHA-256 avant stockage en DB.

Analyse :
- Pour magic links : acceptable de stocker en clair (usage unique, courte durée)
- Pour sessions : hachage implémenté pour renforcer la sécurité

Implémentation :
- Hachage automatique via `hash_token/1` dans `UserSession.changeset/2`
- Utilisation de SHA-256 (:crypto.hash(:sha256, token))
- Token original conservé uniquement dans le cookie côté client
- En cas de compromission DB, les tokens ne sont pas directement exploitables

Avantages :
- Protection en cas de compromission de la base de données
- Les attaquants ne peuvent pas se connecter avec les hash stockés
- Overhead de hachage minimal (acceptable pour le gain de sécurité)
- Cookie toujours configuré avec `httponly` + `secure`

Priorité : IMPLÉMENTÉ (amélioration de sécurité appliquée)

Probl�me : mise � jour DB � chaque requête (charge inutile).

Optimisation appliquée : throttling de 5 minutes (update seulement si > 5 min depuis derni�re activité).

Bénéfice : réduction de ~90% des écritures DB.

Priorité : MOYENNE (optimisation performance, corrigé)

### 6. Cleanup interval trop long (mineure)

Observation : nettoyage toutes les heures � sessions expirées restent jusqu'� 3h (2h expiration + 1h cleanup).

Amélioration : réduction � 30 minutes (maximum 2h30).

Priorité : BASSE (amélioration mineure, corrigé)

### 7. Migration vers Oban.Plugins.Cron (architecture)

Observation : GenServer custom alors qu'Oban est déj� utilisé.

Amélioration : migration vers Oban.Plugins.Cron pour cohérence.

Avantages :
- Architecture unifiée
- Meilleure observabilité
- Retry automatique

Priorité : MOYENNE (amélioration architecture, corrigé)

### 8. Documentation des durées incohérente (doc)

Observation : commentaires mentionnent 1h, 30j alors que config = 2h.

Correctif : mise � jour des commentaires pour refléter la config réelle (2h).

Priorité : BASSE (documentation, corrigé)

## Conséquences

### Positives

- Sécurité renforcée avec flags cookie `httponly` + `secure`
- Révocation instantanée des sessions (critique pour admin)
- Support multi-device naturel (plusieurs sessions par utilisateur)
- Performance optimisée via cache Cachex avec invalidation appropriée
- Nettoyage automatique des sessions expirées
- Traçabilité via événements domaine
- Expérience utilisateur fluide (prolongation automatique)
- Cascade delete garantit l'intégrité référentielle
- Architecture testable (désactivation cache en test)

### Négatives

- Tokens stockés en clair (risque accepté, documenté)
- Complexité du syst�me de cache avec invalidation manuelle
- Charge DB pour `update_session_activity` (mitigée par throttling)
- Dépendance � Cachex pour performance (mais léger)
- Delay potentiel dans propagation des changements (max 5 min avec throttling)

### Neutres

- Sessions persistantes en DB (vs Redis/JWT) : adapté au contexte portfolio
- Durée d'expiration 2h : compromis arbitraire sécurité/UX
- Cookie 24h max : force rotation réguli�re des tokens
- Cleanup toutes les 30 min : équilibre maintenance/performance

## Évolutions futures

### Court terme (implémenté)
1. Ajouter flags `httponly` + `secure` au cookie
2. Invalider cache lors de révocation admin
3. Invalider cache lors de changement de rôle
4. Implémenter throttling des updates `last_activity_at`
5. Migrer vers Oban.Plugins.Cron
6. Réduire cleanup interval � 30 min
7. Clarifier documentation des durées

### Moyen terme (améliorations)
1. Ajouter événements `SessionDeleted`, `SessionRevoked`, `SessionExpired`
2. Interface admin : afficher sessions actives par utilisateur avec révocation sélective
3. Capturer User Agent et IP dans UserSession pour traçabilité
4. Notification email lors de nouvelle connexion (détection activité suspecte)

### Long terme (si nécessaire)
1. Implémenter hachage SHA256 des tokens si exigences sécurité augmentent
2. Tableau de bord d'analytics des connexions
3. Géolocalisation des connexions avec alertes
4. Support Remember Me avec sessions longue durée (si demandé)

## Références

- Phoenix Sessions : https://hexdocs.pm/phoenix/sessions.html
- Cookie Security : https://owasp.org/www-community/controls/SecureCookieAttribute
- Cachex : https://hexdocs.pm/cachex/
- Oban : https://hexdocs.pm/oban/
- OWASP Session Management : https://cheatsheetseries.owasp.org/cheatsheets/Session_Management_Cheat_Sheet.html
- Fichiers concernés :
  - `lib/portfolio/auth/user_session.ex`
  - `lib/portfolio/auth/session_service.ex`
  - `lib/portfolio/auth/session_cleaner.ex`
  - `lib/portfolio_web/plugs/require_auth.ex`
  - `lib/portfolio_web/live/user_auth.ex`
  - `lib/portfolio_web/endpoint.ex`
  - `lib/portfolio_web/controllers/auth_controller.ex`
  - `config/config.exs`
  - `config/runtime.exs`
