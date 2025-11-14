# ADR-052: Stratégie Headers de Sécurité HTTP

Statut: Accepté  
Date: 2025-11-11

## Contexte

Les headers HTTP de sécurité sont des directives envoyées par le serveur au navigateur pour contrôler le comportement sécuritaire de l'application web. Contrairement au CSP qui se concentre sur le contenu (scripts, styles), les headers de sécurité couvrent un spectre plus large : transport, cookies, iframe, MIME sniffing, etc.

### Problématique

**Voir aussi** : ADR-050 (Security Layered Defense) pour la vue d'ensemble complète, ADR-051 (Content Security Policy) pour CSP détaillé

Sans headers de sécurité appropriés, une application web est vulnérable à plusieurs vecteurs d'attaque :

Vecteurs d'attaque sans headers :
- Man-in-the-Middle (MITM) : downgrade HTTPS → HTTP
- Session hijacking : vol de cookie via JavaScript XSS
- Clickjacking : interface admin embarquée dans iframe malveillant
- MIME confusion : fichier .jpg exécuté comme JavaScript
- XSS : protection legacy navigateurs anciens
- Referrer leakage : URL sensibles exposées dans referer

Les headers de sécurité modernes permettent au serveur de donner des instructions explicites au navigateur sur ces comportements, créant une défense en profondeur avec les autres mécanismes (CSP, validation, etc.).

### Contexte Technique

Le portfolio utilise Phoenix qui fournit des plugs natifs pour certains headers :

Headers actuels (endpoint.ex) :
- Content-Security-Policy (ADR-051)
- X-Frame-Options
- X-Content-Type-Options
- X-XSS-Protection (deprecated)
- Strict-Transport-Security (HSTS)

Configuration session (endpoint.ex) :
- Cookie attributes : SameSite, Secure, HttpOnly

Headers manquants :
- Referrer-Policy
- Permissions-Policy (anciennement Feature-Policy)
- Cross-Origin-* policies (CORP, COEP, COOP)

## Options Considérées

### Option 1: Headers Minimaux (Défaut Phoenix)

Approche : Utiliser uniquement `put_secure_browser_headers` de Phoenix sans customisation.

Configuration :

```elixir
# router.ex
pipeline :browser do
  plug :put_secure_browser_headers  # Headers par défaut Phoenix
end
```

Headers ajoutés par Phoenix par défaut :
- X-Frame-Options: SAMEORIGIN
- X-Content-Type-Options: nosniff
- X-XSS-Protection: 1; mode=block

Avantages :
- Simplicité maximale (1 ligne)
- Maintenance Phoenix (mis à jour automatiquement)
- Protection basique assurée

Inconvénients :
- Pas de HSTS (critique pour HTTPS)
- Pas de CSP (critique pour XSS)
- Pas de Referrer-Policy (privacy)
- Pas de Permissions-Policy (features modernes)
- X-Frame-Options: SAMEORIGIN (moins strict que DENY)

Décision : Rejeté. Protection insuffisante pour interface admin.

### Option 2: Headers Custom Complets (Actuel)

Approche : Définir manuellement tous les headers de sécurité via plug custom.

Configuration actuelle :

```elixir
# endpoint.ex:66
plug :put_secure_headers

defp put_secure_headers(conn, _opts) do
  conn
  |> put_resp_header("content-security-policy", "...")
  |> put_resp_header("x-frame-options", "DENY")
  |> put_resp_header("x-content-type-options", "nosniff")
  |> put_resp_header("x-xss-protection", "1; mode=block")
  |> put_resp_header("strict-transport-security", 
       "max-age=31536000; includeSubDomains")
end
```

Avantages :
- Contrôle total sur chaque header
- Configuration fine (DENY vs SAMEORIGIN)
- HSTS activé avec includeSubDomains
- CSP personnalisé (ADR-051)

Inconvénients :
- Maintenance manuelle (mise à jour headers)
- Duplication config (CSP verbeux)
- Risque d'oubli lors ajout nouveau header

Décision : Accepté avec améliorations (voir configuration détaillée).

### Option 3: Bibliothèque Tierce (SecureHeaders)

Approche : Utiliser une bibliothèque Elixir pour gérer les headers automatiquement.

Bibliothèques disponibles :
- `secure_headers` (hex.pm) : Gem Ruby porté en Elixir
- `plug_security` : Plug pour headers sécurité

Configuration théorique :

```elixir
# mix.exs
{:secure_headers, "~> 1.0"}

# endpoint.ex
plug SecureHeaders,
  csp: "default-src 'self'",
  hsts: [max_age: 31_536_000, include_subdomains: true],
  x_frame_options: "DENY"
```

Avantages :
- Configuration déclarative
- Best practices par défaut
- Maintenance bibliothèque
- Potentiellement tests intégrés

Inconvénients :
- Dépendance supplémentaire
- Moins de contrôle granulaire
- Bibliothèques Elixir moins matures que Ruby/Rails
- Over-engineering pour cas simple

Décision : Rejeté. Configuration manuelle Phoenix suffit, pas de dépendance nécessaire.

### Option 4: Headers au Niveau Reverse Proxy (Traefik)

Approche : Configurer headers dans Traefik (reverse proxy Kamal) au lieu de Phoenix.

Configuration Kamal :

```yaml
# config/deploy.yml
proxy:
  middlewares:
    security-headers:
      headers:
        customResponseHeaders:
          X-Frame-Options: "DENY"
          Strict-Transport-Security: "max-age=31536000"
          # ...
```

Avantages :
- Headers appliqués avant Phoenix (performance)
- Configuration infrastructure (séparation concerns)
- Appliqué à toutes requêtes (même erreurs 500)

Inconvénients :
- Configuration distribuée (Traefik + Phoenix)
- CSP dynamique difficile (nonce future)
- Complexité opérationnelle
- Debug plus difficile (deux layers)

Décision : Rejeté. Configuration Phoenix plus simple et flexible pour CSP dynamique.

## Décision

L'option choisie est : Option 2 - Headers Custom Complets avec améliorations

Configuration centralisée dans Phoenix Endpoint avec headers modernes ajoutés.

### Justification

Cette approche offre :

1. Contrôle total : Configuration fine de chaque header selon besoins
2. Simplicité : Tout dans un seul fichier (endpoint.ex)
3. Flexibilité : CSP dynamique possible (nonce futur)
4. Maintenance : Code explicite, facile à auditer
5. Performance : Headers appliqués par Phoenix (pas de proxy overhead)

Les améliorations par rapport à la configuration actuelle :
- Ajout Referrer-Policy
- Ajout Permissions-Policy
- HSTS preload
- Suppression X-XSS-Protection (deprecated)
- Documentation inline pour chaque header

## Configuration Détaillée

### Headers de Sécurité Implémentés

#### 1. Strict-Transport-Security (HSTS)

Rôle : Force le navigateur à toujours utiliser HTTPS, même si l'utilisateur tape http://.

Configuration actuelle :

```elixir
# endpoint.ex:81
put_resp_header("strict-transport-security",
  "max-age=31536000; includeSubDomains"
)
```

Directives :
- `max-age=31536000` : 1 an (365 jours)
- `includeSubDomains` : applique à tous sous-domaines (photo., tech., amvcc.)

Protection :
- Empêche downgrade attack HTTPS → HTTP
- Protège contre MITM même si attaquant contrôle réseau
- Navigateur refuse connexion HTTP après première visite HTTPS

Exemple attaque prévenue :

```
1. User visite https://photo.thibaultsan.com (première fois)
2. Navigateur reçoit HSTS header, stocke directive 1 an
3. Attaquant MITM intercept et redirect vers http://photo.thibaultsan.com
4. Navigateur vérifie HSTS : domaine en liste HSTS
5. Navigateur refuse HTTP, force HTTPS
6. Attaque échoue
```

**Amélioration recommandée : HSTS Preload**

```elixir
put_resp_header("strict-transport-security",
  "max-age=31536000; includeSubDomains; preload"
)
```

Ajout directive `preload` puis soumettre à HSTS Preload List : https://hstspreload.org/

Bénéfice : Protection dès la toute première visite (navigateurs modernes ont liste preload intégrée).

Prérequis preload :
1. HTTPS obligatoire sur tous sous-domaines
2. max-age ≥ 31536000 (1 an)
3. includeSubDomains présent
4. Redirect HTTP → HTTPS

Statut actuel : Tous prérequis remplis, soumission recommandée.

Limitations HSTS :
- Protection uniquement après première visite HTTPS (résolu par preload)
- Pas de révocation rapide (cache navigateur 1 an)
- Bloque HTTP même pour dev local (utiliser localhost différent)

#### 2. X-Frame-Options

Rôle : Contrôle si la page peut être embarquée dans un iframe.

Configuration actuelle :

```elixir
# endpoint.ex:76
put_resp_header("x-frame-options", "DENY")
```

Options :
- `DENY` : aucun iframe autorisé (notre choix)
- `SAMEORIGIN` : iframe même domaine uniquement
- `ALLOW-FROM uri` : iframe domaine spécifique (deprecated)

Protection :
- Empêche clickjacking (bouton invisible dans iframe)
- Complète CSP `frame-ancestors 'none'` (défense en profondeur)

Exemple attaque prévenue :

```html
<!-- evil.com tente clickjacking -->
<iframe src="https://photo.thibaultsan.com/admin"></iframe>
<div style="position:absolute; top:100px; opacity:0.01">
  <button>Supprimer tous albums</button>
</div>

<!-- User clique pensant cliquer sur bouton visible, 
     mais clique en réalité sur bouton admin invisible dans iframe -->

<!-- Avec X-Frame-Options: DENY, navigateur refuse de charger iframe -->
```

Note : Header legacy, remplacé par CSP `frame-ancestors` moderne. Garder pour compatibilité navigateurs anciens (IE11, Safari < 10).

Recommandation : Conserver configuration actuelle (défense en profondeur).

#### 3. X-Content-Type-Options

Rôle : Empêche le navigateur de deviner le MIME type (MIME sniffing).

Configuration actuelle :

```elixir
# endpoint.ex:77
put_resp_header("x-content-type-options", "nosniff")
```

Valeur unique : `nosniff` (pas d'alternative)

Protection :
- Force navigateur à respecter Content-Type déclaré
- Empêche exécution fichier .jpg comme JavaScript
- Bloque attaques polyglotte (fichier à double usage)

Exemple attaque prévenue :

```
1. Attaquant upload "innocent.jpg" (en réalité contient JavaScript)
2. Serveur retourne Content-Type: image/jpeg
3. Attaquant charge via <script src="/uploads/innocent.jpg"></script>

Sans nosniff :
4. IE/Edge détecte JavaScript dans fichier
5. Exécute malgré Content-Type image
6. XSS réussi

Avec nosniff :
4. Navigateur lit Content-Type: image/jpeg
5. Refuse d'exécuter comme script (type mismatch)
6. Attaque échouée
```

Observation : Critique pour applications avec upload fichiers (notre cas).

Recommandation : Conserver (protection essentielle).

#### 4. X-XSS-Protection (DEPRECATED)

Rôle : Active filtre XSS legacy dans navigateurs anciens (IE, Safari).

Configuration actuelle :

```elixir
# endpoint.ex:78
put_resp_header("x-xss-protection", "1; mode=block")
```

Options :
- `0` : désactive filtre
- `1` : active filtre (sanitize)
- `1; mode=block` : active et bloque page entière si XSS détecté

Statut : DEPRECATED depuis 2019

Raisons deprecation :
- Filtre XSS legacy introduit vulnérabilités (bypass connus)
- Chrome supprimé (2019), Firefox jamais supporté
- Edge supprimé (2020, passage Chromium)
- Safari garde support (mais déconseillé)

Recommandation : Supprimer ce header

Justification :
- CSP moderne remplace filtre XSS legacy
- Navigateurs modernes ignorent ce header
- Potentiellement contre-productif (false positives)

Remplacement :

```elixir
# Supprimer cette ligne
# put_resp_header("x-xss-protection", "1; mode=block")

# Déjà protégé par CSP (ADR-051)
```

Exception : Si support IE11 obligatoire, conserver. Sinon supprimer.

#### 5. Content-Security-Policy

Rôle : Contrôle sources autorisées pour scripts, styles, images, etc.

Configuration : Voir ADR-051 Content Security Policy (documentation complète)

Résumé directives :

```elixir
# endpoint.ex:68
put_resp_header("content-security-policy",
  "default-src 'self'; " <>
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
  "style-src 'self' 'unsafe-inline'; " <>
  "img-src 'self' data: https:; " <>
  "font-src 'self' data:; " <>
  "connect-src 'self' ws: wss:; " <>
  "frame-ancestors 'none';"
)
```

Améliorations prévues (ADR-051) :
- Suppression `unsafe-eval` si investigation confirme non nécessaire
- Ajout `object-src 'none'`
- Ajout `base-uri 'self'`
- Ajout `form-action 'self'`
- Migration nonce-based moyen/long terme

### Headers de Sécurité Recommandés (Non Implémentés)

#### 6. Referrer-Policy (PRIORITÉ HAUTE)

Rôle : Contrôle les informations envoyées dans le header Referer lors de navigation.

Problématique :

Sans Referrer-Policy, le navigateur envoie l'URL complète dans le header Referer :

```
User sur : https://photo.thibaultsan.com/admin/albums/123/edit?secret=abc123
Clique lien vers : https://example.com/

Requête vers example.com contient :
Referer: https://photo.thibaultsan.com/admin/albums/123/edit?secret=abc123

→ Fuite informations sensibles (album ID, query params, paths admin)
```

Configuration recommandée :

```elixir
put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
```

Politiques disponibles :

Politique | Cross-Origin | Same-Origin | Cas d'usage
---|---|---|---
`no-referrer` | Rien | Rien | Privacy maximale
`no-referrer-when-downgrade` | URL complète HTTPS→HTTPS, Rien HTTPS→HTTP | URL complète | Défaut navigateur
`origin` | Origine uniquement | Origine uniquement | API publique
`origin-when-cross-origin` | Origine uniquement | URL complète | Balance privacy/analytics
`same-origin` | Rien | URL complète | Site isolé
`strict-origin` | Origine si HTTPS→HTTPS, Rien si downgrade | Origine | Privacy + HTTPS
`strict-origin-when-cross-origin` | Origine si HTTPS→HTTPS, URL complète same-origin | URL complète | RECOMMANDÉ
`unsafe-url` | URL complète toujours | URL complète | Déconseillé

Choix recommandé : `strict-origin-when-cross-origin`

Comportement :
- Same-origin : URL complète (analytics internes OK)
- Cross-origin HTTPS : origine uniquement (https://photo.thibaultsan.com)
- Cross-origin downgrade HTTPS→HTTP : rien (sécurité)

Exemple :

```
Scénario 1 : Navigation interne
User : https://photo.thibaultsan.com/admin/albums
Clique : https://photo.thibaultsan.com/admin/photos
Referer: https://photo.thibaultsan.com/admin/albums
→ OK (same-origin, URL complète utile pour analytics)

Scénario 2 : Lien externe HTTPS
User : https://photo.thibaultsan.com/admin/albums/123/edit
Clique : https://example.com/article
Referer: https://photo.thibaultsan.com/
→ OK (origine uniquement, pas de leak path/params)

Scénario 3 : Lien externe HTTP (downgrade)
User : https://photo.thibaultsan.com/admin
Clique : http://unsecure.com/
Referer: (vide)
→ OK (pas de leak vers site non sécurisé)
```

Implémentation :

```elixir
# endpoint.ex:82 (ajouter)
put_resp_header("referrer-policy", "strict-origin-when-cross-origin")
```

Priorité : HAUTE (protection privacy + sécurité)

#### 7. Permissions-Policy (PRIORITÉ MOYENNE)

Rôle : Contrôle les features navigateur autorisées (camera, micro, geolocation, etc.).

Anciennement : Feature-Policy (renommé en 2020)

Problématique :

Sans Permissions-Policy, toutes features navigateur sont autorisées par défaut. Un script XSS pourrait :
- Accéder caméra/micro (espionnage)
- Lire géolocalisation (tracking)
- Utiliser payment API (fraude)
- Activer fullscreen (phishing UI)

Configuration recommandée :

```elixir
put_resp_header("permissions-policy",
  "camera=(), microphone=(), geolocation=(), payment=()"
)
```

Syntaxe :
- `feature=()` : feature bloquée pour tous (même same-origin)
- `feature=(self)` : feature autorisée same-origin uniquement
- `feature=(self "https://example.com")` : whitelist domaines
- `feature=*` : feature autorisée pour tous (déconseillé)

Features critiques à désactiver :

```elixir
put_resp_header("permissions-policy",
  "camera=(), " <>           # Pas de caméra
  "microphone=(), " <>       # Pas de micro
  "geolocation=(), " <>      # Pas de géolocalisation
  "payment=(), " <>          # Pas de Payment API
  "usb=(), " <>              # Pas d'accès USB
  "magnetometer=(), " <>     # Pas de magnetometer
  "gyroscope=(), " <>        # Pas de gyroscope
  "accelerometer=()"         # Pas d'accelerometer
)
```

Features à autoriser (si nécessaire) :

Notre cas : aucune feature nécessaire actuellement.

Future : Si upload photo via caméra mobile :

```elixir
"camera=(self)"  # Autoriser caméra same-origin uniquement
```

Exemple attaque prévenue :

```javascript
// Script XSS tente d'accéder caméra
navigator.mediaDevices.getUserMedia({ video: true })
  .then(stream => {
    // Envoyer stream vers serveur attaquant
    sendToEvil(stream);
  });

// Avec Permissions-Policy: camera=()
// → DOMException: Permission denied
```

Implémentation :

```elixir
# endpoint.ex:83 (ajouter)
put_resp_header("permissions-policy",
  "camera=(), microphone=(), geolocation=(), payment=()"
)
```

Priorité : MOYENNE (defense in depth, pas de feature utilisée actuellement)

#### 8. Cross-Origin-* Policies (PRIORITÉ BASSE)

Rôle : Contrôle le partage de ressources cross-origin (CORP, COEP, COOP).

Headers :
- Cross-Origin-Resource-Policy (CORP)
- Cross-Origin-Embedder-Policy (COEP)
- Cross-Origin-Opener-Policy (COOP)

Contexte : Protection contre attaques Spectre/Meltdown via SharedArrayBuffer et timing attacks.

CORP : Cross-Origin-Resource-Policy

Contrôle qui peut charger la ressource (image, script, etc.).

```elixir
put_resp_header("cross-origin-resource-policy", "same-origin")
```

Options :
- `same-origin` : ressources chargées uniquement par même origine
- `same-site` : ressources chargées par même site (sous-domaines OK)
- `cross-origin` : ressources chargées par tous (publique)

Cas d'usage : Empêcher hotlinking images (bandwidth theft).

COEP : Cross-Origin-Embedder-Policy

Exige que toutes ressources cross-origin soient explicitement partagées (CORS).

```elixir
put_resp_header("cross-origin-embedder-policy", "require-corp")
```

Impact : Casse chargement images externes (Facebook, etc.) sans CORS.

COOP : Cross-Origin-Opener-Policy

Isole contexte browsing des popups/iframes cross-origin.

```elixir
put_resp_header("cross-origin-opener-policy", "same-origin")
```

Protection : Empêche window.opener attacks.

Recommandation pour notre cas :

Pas d'implémentation court terme car :
- Pas d'utilisation SharedArrayBuffer
- Images externes (Facebook) nécessitent cross-origin
- Complexité vs bénéfice faible

Future : Si utilisation Web Workers avancés ou isolation stricte requise.

Priorité : BASSE (protection edge case, complexité élevée)

### Configuration Session Cookie (Existante)

#### Cookie Attributes Sécurisés

Configuration session actuelle :

```elixir
# endpoint.ex:11
@session_options [
  store: :cookie,
  key: "_portfolio_key",
  signing_salt: "sisdz80o",
  same_site: "Lax",      # Protection CSRF
  secure: true,          # HTTPS uniquement (prod)
  http_only: true,       # Pas accessible JavaScript
  compress: true,
  max_age: 24 * 60 * 60  # 24h expiration
]
```

Analyse attributs :

SameSite: "Lax" (ADR-024)
- Protection CSRF native navigateur
- Cookie pas envoyé pour POST cross-site
- Cookie envoyé pour GET navigation (magic links OK)

Secure: true
- Cookie envoyé uniquement sur HTTPS
- Protection MITM (cookie non exposé sur HTTP)
- Note : Phoenix set automatiquement en production

HttpOnly: true
- Cookie pas accessible via JavaScript (document.cookie)
- Protection XSS (script ne peut pas voler session)
- Critique pour sécurité session

max_age: 24h
- Session expire après 24h
- Limite window attaque si session compromise
- Balance sécurité/UX

Observation : Configuration cookie excellente, aucun changement nécessaire.

## Configuration Finale Recommandée

### Implémentation Complète

```elixir
# lib/portfolio_web/endpoint.ex

# Avant les routes
plug :put_secure_headers

# ...

defp put_secure_headers(conn, _opts) do
  # WebSocket protocol selon environnement
  ws_proto = if Mix.env() == :prod, do: "wss:", else: "ws: wss:"
  
  conn
  # CSP : Protection XSS et injection (ADR-051)
  |> put_resp_header(
    "content-security-policy",
    "default-src 'self'; " <>
      "script-src 'self' 'unsafe-inline'; " <>  # unsafe-eval supprimé après investigation
      "style-src 'self' 'unsafe-inline'; " <>
      "img-src 'self' data: https:; " <>
      "font-src 'self' data:; " <>
      "connect-src 'self' #{ws_proto}; " <>
      "frame-ancestors 'none'; " <>
      "object-src 'none'; " <>                   # Nouveau
      "base-uri 'self'; " <>                     # Nouveau
      "form-action 'self'; " <>                  # Nouveau
      "upgrade-insecure-requests;"               # Nouveau
  )
  # HSTS : Force HTTPS, protection MITM
  |> put_resp_header(
    "strict-transport-security",
    "max-age=31536000; includeSubDomains; preload"  # preload ajouté
  )
  # X-Frame-Options : Protection clickjacking (legacy, complète CSP)
  |> put_resp_header("x-frame-options", "DENY")
  # X-Content-Type-Options : Empêche MIME sniffing
  |> put_resp_header("x-content-type-options", "nosniff")
  # Referrer-Policy : Protection privacy, limite leak URL sensibles
  |> put_resp_header("referrer-policy", "strict-origin-when-cross-origin")  # Nouveau
  # Permissions-Policy : Désactive features navigateur non utilisées
  |> put_resp_header(
    "permissions-policy",
    "camera=(), microphone=(), geolocation=(), payment=()"  # Nouveau
  )
  # Note : X-XSS-Protection supprimé (deprecated, contre-productif)
end
```

### Changements par Rapport à Configuration Actuelle

Ajouts :
1. CSP : `object-src 'none'`, `base-uri 'self'`, `form-action 'self'`, `upgrade-insecure-requests`
2. HSTS : `preload` directive
3. Referrer-Policy : `strict-origin-when-cross-origin`
4. Permissions-Policy : `camera=(), microphone=(), geolocation=(), payment=()`
5. CSP : `ws:` conditionnel (production wss: uniquement)

Suppressions :
1. X-XSS-Protection : header deprecated
2. CSP : `unsafe-eval` (après investigation confirme non nécessaire)

### Validation Configuration

#### Tests Automatisés

```elixir
# test/portfolio_web/security/headers_test.exs
defmodule PortfolioWeb.Security.HeadersTest do
  use PortfolioWeb.ConnCase
  
  describe "Security Headers" do
    test "HSTS header with preload", %{conn: conn} do
      conn = get(conn, "/")
      
      assert [hsts] = get_resp_header(conn, "strict-transport-security")
      assert hsts =~ "max-age=31536000"
      assert hsts =~ "includeSubDomains"
      assert hsts =~ "preload"
    end
    
    test "X-Frame-Options is DENY", %{conn: conn} do
      conn = get(conn, "/")
      
      assert ["DENY"] = get_resp_header(conn, "x-frame-options")
    end
    
    test "X-Content-Type-Options is nosniff", %{conn: conn} do
      conn = get(conn, "/")
      
      assert ["nosniff"] = get_resp_header(conn, "x-content-type-options")
    end
    
    test "Referrer-Policy is strict-origin-when-cross-origin", %{conn: conn} do
      conn = get(conn, "/")
      
      assert ["strict-origin-when-cross-origin"] = 
        get_resp_header(conn, "referrer-policy")
    end
    
    test "Permissions-Policy blocks camera and microphone", %{conn: conn} do
      conn = get(conn, "/")
      
      assert [policy] = get_resp_header(conn, "permissions-policy")
      assert policy =~ "camera=()"
      assert policy =~ "microphone=()"
    end
    
    test "X-XSS-Protection is NOT present (deprecated)", %{conn: conn} do
      conn = get(conn, "/")
      
      assert [] = get_resp_header(conn, "x-xss-protection")
    end
    
    test "CSP includes frame-ancestors none", %{conn: conn} do
      conn = get(conn, "/")
      
      assert [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "frame-ancestors 'none'"
    end
  end
  
  describe "Cookie Security" do
    test "session cookie has Secure attribute in prod" do
      # Test en production uniquement
      if Mix.env() == :prod do
        conn = get(build_conn(), "/")
        cookie = get_session_cookie(conn)
        
        assert cookie =~ "Secure"
      end
    end
    
    test "session cookie has HttpOnly attribute", %{conn: conn} do
      conn = get(conn, "/")
      cookie = get_session_cookie(conn)
      
      assert cookie =~ "HttpOnly"
    end
    
    test "session cookie has SameSite=Lax", %{conn: conn} do
      conn = get(conn, "/")
      cookie = get_session_cookie(conn)
      
      assert cookie =~ "SameSite=Lax"
    end
  end
  
  defp get_session_cookie(conn) do
    conn
    |> get_resp_header("set-cookie")
    |> Enum.find(&String.contains?(&1, "_portfolio_key"))
  end
end
```

#### Tests Manuels

##### Test 1: HSTS avec curl

```bash
curl -I https://photo.thibaultsan.com/

# Vérifier présence :
# Strict-Transport-Security: max-age=31536000; includeSubDomains; preload
```

##### Test 2: Tous headers avec securityheaders.com

URL : https://securityheaders.com/

1. Entrer URL : https://photo.thibaultsan.com
2. Analyser rapport
3. Score attendu : A ou A+

Headers vérifiés :
- Strict-Transport-Security : ✅
- Content-Security-Policy : ✅
- X-Frame-Options : ✅
- X-Content-Type-Options : ✅
- Referrer-Policy : ✅
- Permissions-Policy : ✅

##### Test 3: HSTS Preload List

URL : https://hstspreload.org/

1. Entrer domaine : thibaultsan.com
2. Vérifier éligibilité preload
3. Soumettre si tous critères verts
4. Attendre inclusion (quelques semaines)

Critères :
- HTTPS sur tous sous-domaines : ✅
- Redirect HTTP → HTTPS : ✅
- HSTS header valide : ✅
- max-age ≥ 31536000 : ✅
- includeSubDomains : ✅

## Matrice Headers vs Attaques

| Vecteur Attaque | Headers Protégeant | Niveau Protection |
|-----------------|-------------------|-------------------|
| XSS | CSP + (X-XSS-Protection deprecated) | Élevé |
| MITM | HSTS + Secure Cookie | Très Élevé |
| Session Hijack | HttpOnly Cookie + HSTS + SameSite | Élevé |
| Clickjacking | X-Frame-Options + CSP frame-ancestors | Très Élevé |
| MIME Confusion | X-Content-Type-Options | Élevé |
| Referrer Leak | Referrer-Policy | Moyen |
| Feature Abuse | Permissions-Policy | Moyen |
| Base Tag Inject | CSP base-uri | Moyen |
| Form Hijack | CSP form-action | Moyen |

Lecture :
- Très Élevé : Protection robuste, difficile à contourner
- Élevé : Protection forte, contournement rare
- Moyen : Defense in depth, réduit surface attaque

## Plan d'Action

### Court Terme (Priorité: HAUTE)

1. Ajouter Referrer-Policy
   - Header : `strict-origin-when-cross-origin`
   - Tests automatisés
   - Validation securityheaders.com
   - Estimation : 0.25 jour

2. **Supprimer X-XSS-Protection**
   - Retirer header deprecated
   - Tests vérifier absence
   - Estimation : 0.1 jour

3. Ajouter HSTS preload
   - Directive `preload` dans HSTS
   - Soumettre à hstspreload.org
   - Estimation : 0.25 jour

4. Suite tests headers complète
   - Tests automatisés headers_test.exs
   - Tests manuels securityheaders.com
   - Documentation résultats
   - Estimation : 0.5 jour

### Moyen Terme (Priorité: MOYENNE)

1. Ajouter Permissions-Policy
   - Header : `camera=(), microphone=(), geolocation=(), payment=()`
   - Tests automatisés
   - Validation compatibilité navigateurs
   - Estimation : 0.5 jour

2. **Améliorer CSP (ADR-051)**
   - Ajout `object-src`, `base-uri`, `form-action`
   - Suppression `unsafe-eval` après investigation
   - ws: conditionnel prod/dev
   - Estimation : 1 jour

3. Validation outils externes
   - securityheaders.com : score A+
   - Mozilla Observatory : score A+
   - SSL Labs : score A+
   - Documentation badges
   - Estimation : 0.5 jour

### Long Terme (Priorité: BASSE)

1. **Cross-Origin-* Policies**
   - Évaluer besoin CORP/COEP/COOP
   - POC avec headers activés
   - Tests compatibilité images Facebook
   - Estimation : 2 jours

2. Clear-Site-Data
   - Header pour logout (clear cookies/cache)
   - Implementation endpoint /logout
   - Tests multi-navigateurs
   - Estimation : 1 jour

3. Reporting CSP/HSTS
   - Endpoints /csp-report, /hsts-report
   - Dashboard violations
   - Alerting anomalies
   - Estimation : 2 jours

## Conséquences

### Positives

- Protection robuste contre MITM (HSTS preload)
- Protection clickjacking complète (X-Frame-Options + CSP)
- Privacy améliorée (Referrer-Policy)
- Defense in depth contre XSS (CSP + nosniff + HttpOnly)
- Limitation features navigateur (Permissions-Policy)
- Configuration centralisée (endpoint.ex)
- Tests automatisés garantissent présence headers
- Compatible navigateurs modernes

### Négatives

- Suppression X-XSS-Protection casse IE11 (acceptable si pas support requis)
- HSTS preload irréversible (difficile à retirer de liste)
- Permissions-Policy peut casser features futures (camera upload)
- Maintenance manuelle headers (pas de lib)

### Neutres

- Configuration statique (pas de CSP dynamique nonce actuellement)
- Headers appliqués à toutes réponses (overhead minimal)
- Compatibilité navigateurs anciens limitée (acceptable)

## Références

### Standards et Spécifications

- HSTS RFC 6797 : https://tools.ietf.org/html/rfc6797
- CSP Level 3 : https://www.w3.org/TR/CSP3/
- Referrer-Policy : https://www.w3.org/TR/referrer-policy/
- Permissions-Policy : https://w3c.github.io/webappsec-permissions-policy/

### Documentation MDN

- HSTS : https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Strict-Transport-Security
- X-Frame-Options : https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Frame-Options
- X-Content-Type-Options : https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/X-Content-Type-Options
- Referrer-Policy : https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Referrer-Policy
- Permissions-Policy : https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Permissions-Policy

### Outils de Validation

- Security Headers : https://securityheaders.com/
- HSTS Preload : https://hstspreload.org/
- Mozilla Observatory : https://observatory.mozilla.org/
- SSL Labs : https://www.ssllabs.com/ssltest/

### Best Practices

- OWASP Secure Headers Project : https://owasp.org/www-project-secure-headers/
- web.dev Security Headers : https://web.dev/security-headers/
- Google Safe Browsing : https://developers.google.com/safe-browsing

### Fichiers Code Concernés

- `lib/portfolio_web/endpoint.ex:66-82` : Configuration headers sécurité
- `lib/portfolio_web/endpoint.ex:11-18` : Configuration session cookie
- `test/portfolio_web/security/headers_test.exs` : Tests automatisés (à créer)

### ADRs Connexes

- ADR-050 : Security Layered Defense (vue d'ensemble)
- ADR-051 : Content Security Policy (CSP détaillé)
- ADR-024 : CSRF Protection (SameSite cookie)
- ADR-022 : Session Management (cookie attributes)

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
