# ADR-024: Protection CSRF (Cross-Site Request Forgery)

Statut: Accepté
Date: 2025-07

## Contexte

### Qu'est-ce qu'une attaque CSRF ?

Imaginez ce scénario : vous êtes connecté � votre interface admin sur `thibaultsan.com`. Pendant que vous naviguez, vous visitez un site malveillant `evil.com`. Ce site contient un formulaire invisible qui soumet automatiquement une requête vers votre admin :

```html
<!-- Sur evil.com -->
<form action="https://thibaultsan.com/admin/users/123" method="POST">
  <input type="hidden" name="role" value="user" />
</form>
<script>document.forms[0].submit();</script>
```

**Sans protection CSRF**, votre navigateur enverrait automatiquement votre cookie de session avec cette requête. Le serveur vous reconnaîtrait comme admin et exécuterait l'action (ici : rétrograder un admin en user).

**Avec protection CSRF**, la requête est rejetée car elle ne contient pas le token secret que seul votre vrai site peut générer.

### Les différentes protections possibles

Plusieurs mécanismes existent pour se protéger contre CSRF :

1. Token CSRF : token secret inclus dans chaque formulaire/requête
2. SameSite cookie : empêche l'envoi du cookie depuis un autre site
3. Origin/Referer header : vérifie la provenance de la requête
4. Double submit cookie : compare un cookie avec un header

Phoenix combine **Token CSRF** + **SameSite cookie** pour une protection en profondeur.

## Décision

Le syst�me utilise la protection CSRF native de Phoenix (`protect_from_forgery`) sur toutes les pipelines browser, complétée par le cookie `SameSite=Lax`. Phoenix LiveView gén�re automatiquement des tokens CSRF pour les WebSockets.

### Architecture de la protection CSRF

#### 1. Configuration dans les pipelines

Toutes les pipelines browser incluent `plug :protect_from_forgery` :

```elixir
# Router.ex - Pipeline browser
pipeline :browser do
  plug :fetch_session
  plug :fetch_live_flash
  plug :put_root_layout, html: {PortfolioWeb.Layouts, :root}
  plug :protect_from_forgery          # � Protection CSRF activée
  plug :put_secure_browser_headers
  plug PortfolioWeb.Plugs.RequireAuth, :fetch_current_user
end
```

Cette configuration est répliquée sur toutes les pipelines : `:amvcc`, `:photography`, `:tech`, `:auth_pages`, `:require_authenticated_admin`, `:admin_live`.

Pourquoi sur toutes les pipelines ?

Même les pages publiques peuvent contenir des formulaires (ex: newsletter future). Activer la protection CSRF partout garantit qu'aucun endpoint n'est oublié.

#### 2. Le plug protect_from_forgery en détail

Le plug `Plug.CSRFProtection` (appelé via `:protect_from_forgery`) effectue les actions suivantes :

**� chaque requête GET** :
1. Gén�re un token CSRF unique lié � la session
2. Stocke le token dans la session Phoenix
3. Le token est accessible via `get_csrf_token/0`

**� chaque requête POST/PUT/PATCH/DELETE** :
1. Vérifie la présence du token CSRF dans les param�tres ou headers
2. Compare le token reçu avec celui stocké en session
3. Si correspondance : requête autorisée
4. Si mismatch ou absent : erreur 403 Forbidden

**Exemples de requêtes valides** :

```elixir
# Formulaire classique (HTML form)
<form method="post" action="/admin/albums">
  <input type="hidden" name="_csrf_token" value="<%= get_csrf_token() %>" />
  <!-- autres champs -->
</form>

# Requête AJAX
fetch('/admin/albums', {
  method: 'POST',
  headers: {
    'x-csrf-token': document.querySelector("meta[name='csrf-token']").content,
    'Content-Type': 'application/json'
  },
  body: JSON.stringify({...})
})
```

**Exemple de requête rejetée** :

```bash
# Depuis evil.com (pas de token)
curl -X POST https://thibaultsan.com/admin/users/123 \
  -H "Cookie: _portfolio_key=..." \
  -d "role=user"

# Réponse : 403 Forbidden (CSRF token mismatch)
```

#### 3. Meta tag CSRF dans les layouts

Tous les layouts injectent le token CSRF dans un meta tag :

```heex
<!-- layouts/root.html.heex (ligne 8) -->
<meta name="csrf-token" content={get_csrf_token()} />
```

� quoi sert ce meta tag ?

Ce meta tag permet aux scripts JavaScript d'accéder au token CSRF pour les requêtes AJAX. Phoenix LiveView l'utilise automatiquement pour sécuriser les WebSockets.

**Utilisation par LiveView** :

Dans `assets/js/app.js` (ligne 73-80) :

```javascript
let csrfToken = document
  .querySelector("meta[name='csrf-token']")
  .getAttribute("content");

let liveSocket = new LiveSocket("/live", Socket, {
  params: {
    _csrf_token: csrfToken,  // � Token envoyé au serveur
  },
  hooks: Hooks,
});
```

Le token est automatiquement inclus dans tous les messages WebSocket entre le client et le serveur. Phoenix vérifie ce token � chaque événement `phx-click`, `phx-submit`, etc.

**Utilisation personnalisée (si AJAX custom)** :

Si vous ajoutez du code JavaScript qui fait des requêtes POST/PUT/DELETE, vous devez inclure le token :

```javascript
// Exemple : requête AJAX custom
async function deleteAlbum(albumId) {
  const csrfToken = document
    .querySelector("meta[name='csrf-token']")
    .getAttribute("content");

  const response = await fetch(`/api/albums/${albumId}`, {
    method: 'DELETE',
    headers: {
      'X-CSRF-Token': csrfToken,
      'Content-Type': 'application/json'
    }
  });

  return response.json();
}
```

**Actuellement**, aucun code JavaScript custom ne fait de requêtes AJAX modifiantes. Tout passe par LiveView, donc le meta tag n'est utilisé que par LiveView.

#### 4. Phoenix LiveView et CSRF

Phoenix LiveView gén�re **deux types de tokens** pour une protection compl�te :

##### Token CSRF classique (formulaires)

Pour les formulaires LiveView (`<.simple_form for={@form} phx-submit="...">`), Phoenix gén�re automatiquement un champ caché `_csrf_token` :

```heex
<!-- Template -->
<.simple_form for={@form} phx-submit="request_link">
  <.input field={@form[:email]} type="email" label="Email" />
</.simple_form>

<!-- HTML généré -->
<form phx-submit="request_link">
  <input type="hidden" name="_csrf_token" value="Fkj8s..." />
  <input name="email_form[email]" type="email" />
</form>
```

Ce token prot�ge la soumission initiale du formulaire (avant que le WebSocket soit établi).

##### Token LiveView (WebSocket)

Une fois la connexion WebSocket établie, tous les événements `phx-click`, `phx-submit`, `phx-change` sont protégés par le token LiveView inclus dans les param�tres de connexion (vu plus haut dans app.js).

**Illustration du flux complet** :

```
1. User charge /login (GET)
   �
2. Phoenix gén�re token CSRF � meta tag
   �
3. LiveView démarre � lit le token du meta tag
   �
4. WebSocket se connecte avec token
   �
5. User clique "Envoyer" (phx-submit)
   �
6. Message WebSocket contient le token
   �
7. Serveur vérifie le token � OK ou 403
```

**Avantage** : protection transparente, aucun code � écrire manuellement.

#### 5. Actions sensibles protégées

Toutes les actions sensibles de l'application utilisent LiveView et sont donc automatiquement protégées :

##### Logout (method="delete")

Le composant de déconnexion utilise `method="delete"` :

```heex
<!-- core_components.ex ligne 850 -->
<.link
  href={~p"/logout"}
  method="delete"
  class="text-sm text-gray-600 hover:text-gray-900 font-medium"
>
  Déconnexion
</.link>
```

Phoenix gén�re automatiquement un formulaire avec token CSRF :

```html
<!-- HTML généré par Phoenix -->
<a href="/logout" data-method="delete" data-csrf="Abc123..." data-to="/logout">
  Déconnexion
</a>
<form method="post" action="/logout" style="display:none">
  <input type="hidden" name="_method" value="delete" />
  <input type="hidden" name="_csrf_token" value="Abc123..." />
</form>
```

Lors du clic, JavaScript soumet le formulaire avec le token. Protection CSRF garantie.

##### Delete user/album/photo (phx-click)

Les suppressions utilisent `phx-click` :

```heex
<!-- user_live/index.html.heex ligne 107 -->
<button
  phx-click="confirm_delete"
  phx-value-user-id={user.id}
  class="text-red-600 hover:text-red-900"
>
  <.icon name="hero-trash" />
</button>

<!-- album_live/index.html.heex ligne 231 -->
<a
  href="#"
  phx-click="delete"
  phx-value-id={album.id}
  data-confirm={gettext("admin.albums.index.delete_confirm")}
  class="text-red-600 hover:text-red-900"
>
  Supprimer
</a>
```

Ces événements transitent par le WebSocket LiveView, donc protégés par le token LiveView (aucun token visible dans le HTML, tout dans le WebSocket).

##### Upload de photos (LiveView upload)

L'upload utilise `allow_upload` et `consume_uploaded_entries` :

```elixir
# album_live/edit.ex ligne 29
def mount(%{"id" => id}, _session, socket) do
  album = Photography.get_album!(id, preload: [:photos])

  {:ok,
   socket
   |> assign(:album, album)
   |> allow_upload(:photos,
     accept: ~w(.jpg .jpeg .png .webp),
     max_entries: 20,
     max_file_size: 10_000_000,
     auto_upload: true
   )}
end

# Handler
def handle_event("upload", _params, socket) do
  uploads = consume_uploaded_entries(socket, :photos, fn %{path: path}, entry ->
    {:ok, %{path: path, client_name: entry.client_name}}
  end)
  # ...
end
```

L'upload de fichiers via LiveView utilise des chunks envoyés par WebSocket, tous protégés par le token LiveView. Aucune requête multipart classique, donc pas besoin de token CSRF dans les headers d'upload.

**Résumé** : toutes les actions modifiantes (POST/PUT/PATCH/DELETE) passent par LiveView WebSocket � protection CSRF automatique 

#### 6. Cookie SameSite et CSRF

Le cookie de session est configuré avec `SameSite=Lax` :

```elixir
# endpoint.ex ligne 11
@session_options [
  store: :cookie,
  key: "_portfolio_key",
  signing_salt: "sisdz80o",
  same_site: "Lax",  # � Protection CSRF complémentaire
  secure: true,
  http_only: true,
  # ...
]
```

### Comprendre SameSite : le guide complet

L'attribut `SameSite` contrôle quand le navigateur envoie le cookie avec les requêtes. C'est une protection CSRF native des navigateurs modernes.

#### SameSite=Strict (sécurité maximale)

**Comportement** :
- Cookie envoyé **uniquement** pour les requêtes same-site (même domaine)
- Cookie **jamais** envoyé pour les requêtes cross-site

**Exemple concret** :

```
Scénario : User connecté sur thibaultsan.com, cookie présent
         : User reçoit un email avec lien vers thibaultsan.com/admin

1. User clique sur le lien depuis Gmail
   �
2. Requête GET vers thibaultsan.com/admin
   �
3. SameSite=Strict � Cookie PAS envoyé (requête cross-site depuis Gmail)
   �
4. Serveur ne reconnaît pas l'utilisateur
   �
5. Redirect vers /login
   �
6. User doit se reconnecter (mauvaise UX)
```

**Avantages** :
-  Protection CSRF maximale (aucune requête cross-site autorisée)
-  Même les requêtes GET sont protégées

**Inconvénients** :
-  UX dégradée : déconnecté � chaque lien externe
-  Incompatible avec magic links par email (notre cas !)
-  Problématique pour OAuth redirects

**Cas d'usage** : applications bancaires, admin critiques sans liens externes.

#### SameSite=Lax (notre choix)

**Comportement** :
- Cookie envoyé pour requêtes same-site (comme Strict)
- Cookie envoyé pour navigation top-level GET cross-site
- Cookie **pas** envoyé pour POST/PUT/DELETE cross-site
- Cookie **pas** envoyé pour requêtes AJAX cross-site

**Exemple concret** :

```
Scénario 1 : Magic link par email (notre cas principal)

1. User reçoit email avec magic link
   https://thibaultsan.com/auth/magic/Abc123
   �
2. User clique (navigation GET cross-site depuis Gmail)
   �
3. SameSite=Lax � Cookie envoyé (navigation GET autorisée)
   �
4. Serveur crée la session
   �
5. User connecté directement (bonne UX) 
```

```
Scénario 2 : Attaque CSRF depuis evil.com

1. User connecté sur thibaultsan.com
   �
2. User visite evil.com (site malveillant)
   �
3. evil.com tente un POST vers thibaultsan.com/admin/users
   �
4. SameSite=Lax � Cookie PAS envoyé (POST cross-site interdit)
   �
5. Serveur rejette (pas de session)
   �
6. Attaque échoue 
```

**Avantages** :
-  Protection CSRF pour toutes les requêtes modifiantes (POST/PUT/DELETE)
-  UX préservée pour les liens externes (GET navigation)
-  Compatible avec magic links email
-  Recommandé par OWASP

**Inconvénients** :
-  Pas de protection CSRF sur GET avec side effects
  - Solution : ne jamais faire d'actions modifiantes en GET (bonne pratique)
  - Exemple � éviter : `GET /admin/users/123/delete`
  - Correct : `DELETE /admin/users/123`

**Cas d'usage** : la plupart des applications web modernes.

#### SameSite=None (déconseillé)

**Comportement** :
- Cookie envoyé dans **toutes** les requêtes (same-site et cross-site)
- Aucune protection CSRF native

**Cas d'usage** : iframes, embeds cross-domain (rare).

**Obligatoire** : utiliser avec `Secure=true` (HTTPS uniquement).

**Notre contexte** : non nécessaire.

### Tableau comparatif

| Attribut | Protection CSRF | UX Magic Links | Navigation externe | Recommandation |
|----------|----------------|----------------|-------------------|----------------|
| `Strict` |  Maximale |  Cassé |  Cassé | Applications critiques |
| `Lax` |  POST/PUT/DELETE |  Fonctionne |  Fonctionne | Notre choix |
| `None` |  Aucune |  Fonctionne |  Fonctionne | Iframes uniquement |

**Conclusion** : `SameSite=Lax` est le compromis parfait pour notre portfolio avec authentification magic link.

#### 7. Durée de vie du token CSRF

**Question importante** : combien de temps un token CSRF est-il valide ?

**Réponse** : le token CSRF est lié � la session Phoenix.

**Cycle de vie** :

```
1. User ouvre /login (nouvelle session)
   �
2. Phoenix gén�re session_id + csrf_token
   �
3. Les deux sont stockés dans le cookie (signé)
   �
4. User active pendant 2h (renouvellement session)
   �
5. Token CSRF reste valide
   �
6. Session expire (2h inactivité ou 24h max)
   �
7. Token CSRF invalide
   �
8. Prochaine requête POST � 403 Forbidden
```

**Test pratique** :

```
Scénario : User ouvre formulaire, part 3h, revient et soumet

1. User ouvre /login � 10h00
   �
2. Token CSRF généré et inclus dans le formulaire
   �
3. User part déjeuner (3h d'inactivité)
   �
4. Session expirée (timeout 2h)
   �
5. User revient � 13h00 et soumet le formulaire
   �
6. Phoenix vérifie token CSRF � session expirée
   �
7. Réponse : 403 Forbidden
   �
8. User doit rafraîchir la page et se reconnecter
```

**Impact UX** :

-  Sécurité renforcée (tokens expirés ne peuvent pas être réutilisés)
-  UX potentiellement dégradée pour utilisateurs inactifs

**Avec LiveView** : ce probl�me est largement atténué car la connexion WebSocket maintient la session active. Si le WebSocket se déconnecte (inactivité), LiveView affiche automatiquement un message de reconnexion.

#### 8. Pipeline API et CSRF

Le router contient un pipeline `:api` (ligne 59) :

```elixir
pipeline :api do
  plug :accepts, ["json"]
end
```

**Observation** : pas de `plug :protect_from_forgery` dans ce pipeline.

Pourquoi ?

Les APIs REST/GraphQL utilisent généralement des tokens Bearer (JWT) ou API keys dans les headers, pas de cookies. Sans cookies, pas de risque CSRF.

**Exemple API classique** :

```bash
# Authentification via Bearer token
curl -X POST https://api.thibaultsan.com/photos \
  -H "Authorization: Bearer eyJhbGc..." \
  -H "Content-Type: application/json" \
  -d '{"title":"Sunset"}'
```

Le token Bearer est envoyé explicitement dans le header `Authorization`. Un site malveillant ne peut pas voler ce token (isolé par Same-Origin Policy du navigateur).

**Actuellement** : pipeline `:api` non utilisé (aucune route).

**Future API** : si vous ajoutez une API REST pour mobile app par exemple :
-  Utilisez JWT/Bearer tokens (pas de cookies)
-  Pas besoin de protection CSRF
-  Ne pas utiliser de cookies pour l'auth API

**Exception** : API utilisée par le frontend web avec cookies � CSRF nécessaire. Mais ce cas est rare (mieux vaut utiliser LiveView).

#### 9. Tests et validation

**Observation** : aucun test explicite de la protection CSRF n'a été trouvé dans la suite de tests.

**Tests recommandés** :

##### Test 1 : POST sans token � 403

```elixir
# test/portfolio_web/integration/csrf_test.exs
defmodule PortfolioWeb.Integration.CSRFTest do
  use PortfolioWeb.ConnCase

  describe "CSRF protection" do
    test "POST without CSRF token is rejected", %{conn: conn} do
      conn = post(conn, ~p"/login", %{email: "test@example.com"})

      # Phoenix retourne soit 403 Forbidden soit redirect selon config
      assert conn.status in [403, 302]
      assert conn.halted
    end

    test "POST with valid CSRF token is accepted", %{conn: conn} do
      # Fetch pour obtenir un token CSRF
      conn = get(conn, ~p"/login")
      csrf_token = conn.private[:csrf_token]

      # POST avec token
      conn = post(conn, ~p"/login", %{
        _csrf_token: csrf_token,
        email: "test@example.com"
      })

      # Devrait passer (peut échouer pour autres raisons mais pas CSRF)
      refute conn.halted
    end
  end
end
```

##### Test 2 : LiveView avec token invalide

```elixir
test "LiveView rejects connection with invalid CSRF token", %{conn: conn} do
  # Connecter LiveView avec mauvais token
  assert {:error, %{reason: "invalid csrf token"}} =
    live(conn, ~p"/admin")
end
```

##### Test 3 : Vérifier protection sur toutes les routes sensibles

```elixir
test "all POST/PUT/DELETE routes require CSRF", %{conn: conn} do
  sensitive_routes = [
    {:post, ~p"/admin/albums"},
    {:delete, ~p"/admin/albums/123"},
    {:put, ~p"/admin/users/123"}
  ]

  for {method, path} <- sensitive_routes do
    conn = apply(Plug.Conn, method, [build_conn(), path, %{}])

    assert conn.status in [403, 302],
      "Route #{method} #{path} should be CSRF protected"
  end
end
```

**Test manuel (curl)** :

```bash
# 1. Se connecter et récupérer le cookie
curl -c cookies.txt https://thibaultsan.com/login

# 2. Essayer un POST sans token CSRF
curl -b cookies.txt -X POST https://thibaultsan.com/admin/albums \
  -d "title=Hacked Album"

# Résultat attendu : 403 Forbidden ou redirect
```

**Priorité** : haute pour validation sécurité.

## Alternatives considérées

### Double Submit Cookie

Approche :
- Stocker le token CSRF dans un cookie séparé
- Le JavaScript lit ce cookie et l'envoie dans un header custom
- Serveur compare les deux valeurs

Avantages :
- Stateless (pas de stockage session côté serveur)
- Compatible avec CDN/load balancers

Inconvénients :
- Plus complexe � implémenter
- Moins sécurisé que le token en session (subdomain attacks possibles)
- Nécessite JavaScript obligatoire

Décision : rejeté. Phoenix utilise déj� token en session (mieux sécurisé).

### Origin/Referer header uniquement

Approche :
- Vérifier que le header `Origin` ou `Referer` correspond au domaine
- Pas de token nécessaire

Avantages :
- Simple
- Pas de code JavaScript

Inconvénients :
- Headers peuvent être absents (privacy settings, ancien navigateur)
- Headers peuvent être spoofés dans certains cas
- Pas recommandé par OWASP comme protection unique

Décision : rejeté. Phoenix combine cette vérification avec le token CSRF (défense en profondeur).

### Désactiver CSRF pour certaines routes

Approche :
- Pipeline `:api` sans `protect_from_forgery`
- Authentification via JWT uniquement

Avantages :
- Performance lég�rement meilleure (pas de vérification)
- Simplifie l'intégration API mobile

Inconvénients :
- Risque d'oubli (route sensible sans protection)

Décision : accepté pour les APIs futures avec JWT/Bearer tokens. Actuellement non utilisé (pas d'API).

## Probl�mes identifiés et recommandations

### 1. Absence de tests CSRF (Priorité Haute)

Probl�me : aucun test ne vérifie explicitement la protection CSRF.

Risque : si `protect_from_forgery` est accidentellement supprimé d'une pipeline, personne ne le remarquera avant la prod.

Recommandation : ajouter une suite de tests `csrf_test.exs` couvrant :
- POST sans token � 403
- POST avec token valide � OK
- LiveView avec token invalide � erreur
- Vérification sur toutes les routes sensibles

Priorité : haute.

### 2. Meta tag CSRF inutilisé (Documentation)

Observation : le meta tag CSRF est présent dans tous les layouts mais uniquement utilisé par LiveView (pas de code JavaScript custom).

Recommandation :
- Documenter clairement dans les layouts que ce meta tag est pour LiveView
- Si JavaScript custom ajouté future

ment, documenter l'usage du token

Exemple de commentaire dans layout :

```heex
<!-- Token CSRF pour Phoenix LiveView et requêtes AJAX custom -->
<meta name="csrf-token" content={get_csrf_token()} />
```

Priorité : basse (documentation).

### 3. Pas de page d'erreur 403 custom (UX)

Observation : lorsqu'un token CSRF est invalide, Phoenix retourne une page 403 générique ou redirige vers `/`.

Recommandation : créer une page d'erreur custom expliquant le probl�me :

```elixir
# error_view.ex
def render("403.html", _assigns) do
  ~H"""
  <div class="error-page">
    <h1>Requête non autorisée</h1>
    <p>Votre session a expiré ou la requête est invalide.</p>
    <a href="/">Retour � l'accueil</a>
  </div>
  """
end
```

Priorité : moyenne (amélioration UX).

### 4. Configuration protect_from_forgery par défaut

Observation : `protect_from_forgery` utilise la config par défaut (`:exception` mode).

Options disponibles :
- `with: :exception` (défaut) : l�ve une erreur si CSRF invalide
- `with: :clear_session` : efface la session et continue

Recommandation : garder le mode `:exception` (plus sécurisé). Mode `:clear_session` peut masquer des attaques.

Priorité : aucune action nécessaire (config actuelle correcte).

### 5. GET avec side effects (Bonne pratique)

Observation : aucun GET avec side effects n'a été trouvé dans le code (bonne pratique).

Rappel : `SameSite=Lax` ne prot�ge pas les GET contre CSRF. Il est critique de ne jamais implémenter d'actions modifiantes en GET.

**Exemple � éviter** :

```elixir
#  MAUVAIS - Action sensible en GET
get "/admin/users/:id/delete", UserController, :delete

#  BON - Utiliser DELETE
delete "/admin/users/:id", UserController, :delete
```

Recommandation : maintenir cette bonne pratique. En code review, rejeter tout GET avec side effects.

Priorité : vigilance continue (bonne pratique � maintenir).

## Conséquences

### Positives

- Protection CSRF robuste via token + SameSite
- Compatible avec magic links (SameSite=Lax)
- LiveView g�re automatiquement les tokens
- Défense en profondeur (token + cookie attributes)
- Code minimal (Phoenix natif)
- Aucun formulaire classique � gérer manuellement
- Prêt pour API future (pipeline séparé)

### Négatives

- Tokens expirent avec la session (UX dégradée apr�s inactivité)
- Meta tag CSRF dans tous les layouts (overhead minimal)
- Pas de tests explicites (� ajouter)
- Page d'erreur 403 générique (� améliorer)

### Neutres

- SameSite=Lax suffisant pour le contexte (pas besoin de Strict)
- Protection applicable même aux pages publiques (overhead négligeable)
- Compatible avec architecture actuelle (100% LiveView)

## Améliorations futures

### Court terme (priorité haute)
1. Ajouter suite de tests CSRF compl�te
2. Vérifier usage du token CSRF en JavaScript (actuellement LiveView uniquement)
3. Documenter durée de vie des tokens (lié � session)

### Moyen terme (priorité moyenne)
1. Créer page d'erreur 403 custom avec message clair
2. Ajouter commentaires dans layouts expliquant le meta tag CSRF
3. Tester manuellement avec curl (POST sans token)

### Long terme (évolutions futures)
1. Pipeline API avec JWT (skip CSRF)
2. Monitoring des erreurs 403 CSRF (détection anomalies)
3. Message LiveView custom lors de token expiré

## Références et ressources

### Documentation officielle
- Phoenix CSRF Protection : https://hexdocs.pm/phoenix/csrf_protection.html
- Plug.CSRFProtection : https://hexdocs.pm/plug/Plug.CSRFProtection.html
- Phoenix LiveView Security : https://hexdocs.pm/phoenix_live_view/security-model.html

### Standards et guides
- OWASP CSRF Prevention : https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html
- MDN SameSite cookies : https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Set-Cookie/SameSite
- RFC 6749 (OAuth 2.0) : https://tools.ietf.org/html/rfc6749

### Articles approfondis
- Understanding CSRF : https://portswigger.net/web-security/csrf
- SameSite Cookie Explained : https://web.dev/articles/samesite-cookies-explained

### Fichiers concernés
- `lib/portfolio_web/router.ex` (toutes les pipelines)
- `lib/portfolio_web/endpoint.ex` (configuration cookie SameSite)
- `lib/portfolio_web/components/layouts/*.html.heex` (meta tag CSRF)
- `assets/js/app.js` (utilisation du token par LiveView)
- `lib/portfolio_web/components/core_components.ex` (logout avec method="delete")
- `lib/portfolio_web/live/admin/*/index.html.heex` (événements phx-click protégés)
