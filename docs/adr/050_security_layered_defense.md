# ADR-050: Défense en Profondeur (Layered Security)

Statut: Accepté  
Date: 2025-11-11

## Contexte

La sécurité d'une application web ne peut pas reposer sur une seule mesure. Une approche de défense en profondeur (layered security) consiste à empiler plusieurs couches de sécurité indépendantes, de sorte que si une couche est compromise, les autres continuent de protéger le système.

### Problématique

Le portfolio Photography est une application web exposée publiquement avec les caractéristiques suivantes :

Contexte de menace :
- Interface publique accessible (photo.thibaultsan.com)
- Interface admin sensible (login, gestion albums/photos)
- Upload de fichiers (photos, potentiellement malveillants)
- Authentification passwordless (magic links)
- Base de données avec données utilisateurs

Vecteurs d'attaque potentiels :
- CSRF (Cross-Site Request Forgery)
- XSS (Cross-Site Scripting)
- SQL Injection
- Clickjacking (iframe malveillant)
- Session hijacking
- Brute force sur magic links
- Spam d'emails via magic links
- Upload de fichiers malveillants
- Man-in-the-Middle (MITM)
- DDoS (Denial of Service)

Sans stratégie de sécurité holistique :
- Risque de dépendre d'une seule protection (SPOF sécurité)
- Attaques sophistiquées peuvent contourner une couche unique
- Difficulté à auditer la posture de sécurité globale
- Absence de résilience en cas de 0-day sur une bibliothèque

## Décision

Le système adopte une architecture de défense en profondeur avec 7 couches de sécurité indépendantes, de l'infrastructure au code applicatif. Chaque couche apporte une protection spécifique, de sorte que la compromission d'une couche ne compromet pas l'ensemble du système.

### Architecture de Défense en Profondeur

```
┌─────────────────────────────────────────────────────────────┐
│                     Couche 7: Validation                    │
│              Input Validation, Output Encoding              │
│                  (Ecto Changesets, HEEx)                    │
└─────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────┐
│                   Couche 6: Authentification                │
│         Magic Links, RBAC, Session Management               │
│              (ADR-020, ADR-021, ADR-022)                    │
└─────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────┐
│                  Couche 5: Rate Limiting                    │
│         Protection Anti-Abus, Brute Force Prevention        │
│                      (ADR-023, Hammer)                      │
└─────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────┐
│                  Couche 4: Protection CSRF                  │
│         Token CSRF, SameSite Cookies, Origin Check          │
│                   (ADR-024, Phoenix CSRF)                   │
└─────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────┐
│                  Couche 3: Headers Sécurité                 │
│    CSP, X-Frame-Options, HSTS, X-Content-Type-Options       │
│              (ADR-051, ADR-052, Endpoint Plug)              │
└─────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────┐
│                   Couche 2: Transport SSL/TLS               │
│         HTTPS Only, Let's Encrypt, Cloudflare Full          │
│                   (ADR-043, Kamal + Traefik)                │
└─────────────────────────────────────────────────────────────┘
                              ↑
┌─────────────────────────────────────────────────────────────┐
│                  Couche 1: Infrastructure                   │
│      Firewall, fail2ban, Cloudflare DDoS Protection         │
│                  (Hetzner VPS + Cloudflare)                 │
└─────────────────────────────────────────────────────────────┘
```

### Couche 1: Infrastructure et Réseau

#### Firewall Serveur (Hetzner)

Protection au niveau réseau avant que les paquets n'atteignent l'application.

Configuration Hetzner Firewall :

```yaml
# Ports ouverts
- 22/tcp   (SSH, IP whitelist recommandée)
- 80/tcp   (HTTP, redirect HTTPS)
- 443/tcp  (HTTPS)

# Ports fermés
- 5432/tcp (PostgreSQL, localhost uniquement)
- 4369/tcp (Erlang EPMD, localhost uniquement)
- Tous autres ports
```

Protection :
- Ferme tous les ports sauf 22/80/443
- PostgreSQL inaccessible depuis Internet
- Empêche scan de ports et attaques sur services internes

Implémentation :
- Configuration via Hetzner Cloud Console
- Règles firewall par défaut (deny all, allow whitelist)
- IP whitelist pour SSH (IP admin uniquement)

Documentation : ADR-043 section Infrastructure

#### fail2ban (Recommandé, non implémenté)

Détecte les patterns d'attaque dans les logs et bannit les IPs malveillantes.

Configuration recommandée :

```ini
# /etc/fail2ban/jail.local
[phoenix-auth]
enabled = true
port = http,https
filter = phoenix-auth
logpath = /var/log/phoenix/*.log
maxretry = 20        # 20 rate limits dépassés
bantime = 3600       # Ban 1 heure
findtime = 600       # Fenêtre 10 minutes
```

Filter :

```ini
# /etc/fail2ban/filter.d/phoenix-auth.conf
[Definition]
failregex = Rate limit exceeded.*identifier: <HOST>
ignoreregex =
```

Protection :
- Bannissement automatique IP après 20 rate limits en 10 min
- Niveau firewall (iptables) : requête n'atteint jamais Phoenix
- Réduit charge serveur lors d'attaques

Statut : Non implémenté, priorité haute

Documentation : ADR-023 section Protection Infrastructure

#### Cloudflare DDoS Protection

Protection au niveau CDN contre les attaques DDoS volumétriques.

Configuration actuelle :
- Cloudflare en mode DNS only (gris, pas de proxy)
- Protection DDoS basique activée

Configuration future (si proxy activé, orange) :
- DDoS protection avancée (plan Free)
- Bot Fight Mode (détection bots)
- Rate limiting Cloudflare (plan Pro+)
- WAF (Web Application Firewall, plan Pro+)

Protection :
- Absorbe les attaques DDoS avant le serveur
- Challenge automatique pour IPs suspectes
- Limite requêtes par IP au niveau edge

Statut : DNS only actuellement, proxy optionnel futur

Documentation : ADR-044 section CDN Strategy

### Couche 2: Transport et Chiffrement

**Voir aussi** : ADR-043 (Deployment) pour la configuration Kamal/Traefik SSL, ADR-052 (Security Headers) pour HSTS

#### HTTPS Obligatoire

Tout le trafic transite en HTTPS, HTTP redirige automatiquement.

Configuration Kamal/Traefik :

```yaml
# config/deploy.yml
proxy:
  ssl: true                     # Let's Encrypt automatique
  hosts:
    - thibaultsan.com
    - photo.thibaultsan.com
    - tech.thibaultsan.com
    - amvcc.thibaultsan.com
```

Protection :
- Chiffrement TLS 1.2+ (man-in-the-middle impossible)
- Certificats Let's Encrypt (renouvelés automatiquement)
- Redirect HTTP → HTTPS (aucun trafic non chiffré)

Implémentation :
- Kamal + Traefik gèrent SSL automatiquement
- Certificats stockés dans volumes Docker
- Renouvellement automatique tous les 90 jours

#### HSTS (HTTP Strict Transport Security)

Force les navigateurs à toujours utiliser HTTPS, même si l'utilisateur tape http://.

Configuration Endpoint :

```elixir
# lib/portfolio_web/endpoint.ex:78
defp put_secure_headers(conn, _opts) do
  conn
  |> put_resp_header(
    "strict-transport-security",
    "max-age=31536000; includeSubDomains"
  )
  # ...
end
```

Paramètres :
- `max-age=31536000` : 1 an (365 jours)
- `includeSubDomains` : applique à tous les sous-domaines

Protection :
- Empêche downgrade attack HTTPS → HTTP
- Navigateur refuse connexion HTTP même si attaquant MITM
- Protection dès la première visite (après premier chargement HTTPS)

Amélioration recommandée : Preload HSTS

```elixir
"strict-transport-security",
"max-age=31536000; includeSubDomains; preload"
```

Puis soumettre à la HSTS Preload List : https://hstspreload.org/

Bénéfice : Protection dès la toute première visite (navigateurs modernes)

#### Cloudflare Full Encryption

Chiffrement de bout en bout entre utilisateur et serveur via Cloudflare.

Configuration Cloudflare :
- SSL/TLS Encryption Mode : Full (strict recommandé)
- Cloudflare ↔ Utilisateur : Certificat Cloudflare
- Cloudflare ↔ Serveur : Certificat Let's Encrypt

Protection :
- Double chiffrement (navigateur → Cloudflare → serveur)
- Validation certificat serveur (Full strict)
- Pas de trafic clair entre Cloudflare et serveur

Documentation : ADR-043 section Cloudflare Configuration

### Couche 3: Headers de Sécurité HTTP

**Voir aussi** : ADR-051 (Content Security Policy) pour CSP détaillé, ADR-052 (Security Headers Strategy) pour tous les headers

Ensemble de headers HTTP qui instruisent le navigateur sur les restrictions de sécurité.

#### Content Security Policy (CSP)

Contrôle les sources autorisées pour scripts, styles, images, etc.

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

Directives :
- `default-src 'self'` : par défaut, uniquement même origine
- `script-src 'unsafe-inline' 'unsafe-eval'` : Alpine.js + Tailwind requis
- `img-src https:` : permet images depuis CDN future
- `frame-ancestors 'none'` : aucun iframe autorisé (anti-clickjacking)

Protection :
- Empêche XSS par injection script externe
- Bloque inline scripts malveillants (sauf whitelist)
- Empêche exfiltration de données vers domaine externe

Limitations :
- `unsafe-inline` affaiblit la protection XSS
- Nécessaire pour Alpine.js (framework JavaScript)

Amélioration future : nonce-based CSP (ADR-051)

Documentation : ADR-051 Content Security Policy

#### X-Frame-Options

Empêche l'application d'être embarquée dans un iframe (protection clickjacking).

Configuration :

```elixir
# endpoint.ex:76
put_resp_header("x-frame-options", "DENY")
```

Options :
- `DENY` : aucun iframe autorisé (notre choix)
- `SAMEORIGIN` : iframe même domaine uniquement
- `ALLOW-FROM uri` : iframe domaine spécifique (deprecated)

Protection :
- Empêche clickjacking (bouton invisible sur iframe transparent)
- Complète `frame-ancestors 'none'` du CSP (défense en profondeur)

Exemple attaque prévenue :

```html
<!-- Site malveillant evil.com -->
<iframe src="https://photo.thibaultsan.com/admin" style="opacity: 0.01"></iframe>
<button style="position: absolute; top: 100px">Cliquez ici pour gagner!</button>

<!-- User clique pensant gagner un prix, mais clique en réalité sur bouton admin invisible -->
```

Avec `X-Frame-Options: DENY`, le navigateur refuse de charger l'iframe.

#### X-Content-Type-Options

Force le navigateur à respecter le Content-Type déclaré (pas de MIME sniffing).

Configuration :

```elixir
# endpoint.ex:77
put_resp_header("x-content-type-options", "nosniff")
```

Protection :
- Empêche le navigateur d'exécuter un fichier .jpg comme JavaScript
- Évite attaques par upload de fichier polyglotte (image + script)

Exemple attaque prévenue :

```
1. Attaquant upload "image.jpg" contenant du JavaScript caché
2. Serveur retourne Content-Type: image/jpeg
3. Sans nosniff : IE/Edge détecte JavaScript et exécute
4. Avec nosniff : navigateur refuse, traite comme image
```

#### X-XSS-Protection (Deprecated)

Protection XSS legacy pour anciens navigateurs.

Configuration :

```elixir
# endpoint.ex:78
put_resp_header("x-xss-protection", "1; mode=block")
```

Statut : Deprecated, remplacé par CSP moderne

Recommandation : Garder pour compatibilité navigateurs anciens (IE, Safari < 13)

Documentation : ADR-052 Security Headers Strategy

### Couche 4: Protection CSRF

**Voir aussi** : ADR-024 (CSRF Protection) pour les détails complets de la protection CSRF

Protection contre les requêtes forgées cross-site.

#### Token CSRF Phoenix

Token secret unique par session, validé sur chaque requête modifiante.

Implémentation :

```elixir
# router.ex - toutes les pipelines browser
pipeline :browser do
  plug :protect_from_forgery  # Token CSRF automatique
  # ...
end
```

Mécanisme :
1. GET /login : Phoenix génère token CSRF → session
2. Formulaire contient `<input name="_csrf_token" value="...">`
3. POST /login : Phoenix vérifie token == session
4. Si match : requête autorisée
5. Si mismatch : 403 Forbidden

Protection :
- Requêtes POST/PUT/DELETE depuis site externe rejetées
- Même si cookie de session volé (CSRF != session hijacking)

#### SameSite=Lax Cookie

Attribut cookie qui limite l'envoi du cookie cross-site.

Configuration :

```elixir
# endpoint.ex:16
@session_options [
  same_site: "Lax",  # Cookie pas envoyé pour POST cross-site
  # ...
]
```

Comportement :
- Cookie envoyé pour navigation GET cross-site (magic links OK)
- Cookie PAS envoyé pour POST/PUT/DELETE cross-site (CSRF bloqué)

Protection :
- Défense en profondeur avec token CSRF
- Protection native navigateur (pas de code serveur)

#### Origin/Referer Check (Phoenix natif)

Phoenix vérifie automatiquement les headers Origin/Referer.

Implémentation : Intégré dans `Plug.CSRFProtection`

Protection :
- Rejette requêtes si Origin != domaine attendu
- Complète token CSRF (triple protection)

Documentation : ADR-024 CSRF Protection

### Couche 5: Rate Limiting et Anti-Abus

**Voir aussi** : ADR-023 (Rate Limiting) pour la stratégie complète de rate limiting

Limitation du nombre de requêtes pour empêcher brute force et spam.

#### Rate Limiting Applicatif (Hammer)

Limite par action et par identifier (email ou IP).

Configuration :

```elixir
# lib/portfolio/rate_limiter.ex
@rate_limits %{
  magic_link_request: {5, :timer.hours(1)},        # 5/h par email
  magic_link_verify: {10, :timer.minutes(5)},      # 10/5min par IP
}
```

Protections :
- Magic link request : 5 requêtes/h par email (anti-spam)
- Magic link verify : 10 tentatives/5min par IP (anti-brute force)
- Limite globale recommandée : 100 requêtes/h application (détection anomalie)

Mécanisme :
1. User demande magic link
2. `RateLimiter.check_rate(:magic_link_request, email)`
3. Si < 5/h : autorisé, email envoyé
4. Si ≥ 5/h : refusé, message "Trop de tentatives"

#### Rate Limiting IP (Recommandé)

Limite par IP en complément de la limite par email.

Configuration recommandée :

```elixir
magic_link_request_by_ip: {20, :timer.hours(1)}  # 20/h par IP
```

Protection :
- Empêche attaquant de spam 100 emails différents depuis même IP
- Complète limite par email (défense en profondeur)

Statut : Non implémenté, priorité haute

#### fail2ban (Infrastructure)

Bannissement IP au niveau firewall après détection pattern attaque.

Configuration :
- 20 rate limits dépassés en 10 min → ban 1h
- Ban niveau iptables (requête n'atteint pas Phoenix)

Statut : Non implémenté, priorité haute

Documentation : ADR-023 Rate Limiting

### Couche 6: Authentification et Autorisation

**Voir aussi** : ADR-020 (Magic Links), ADR-021 (RBAC), ADR-022 (Session Management) pour les détails complets

Contrôle d'accès et gestion des identités.

#### Magic Links Passwordless (ADR-020)

Authentification sans mot de passe via lien email temporaire.

Sécurité :
- Token aléatoire 32 bytes (256 bits entropie)
- Expiration 15 minutes
- Usage unique (invalidé après utilisation)
- Rate limiting 5 requêtes/h par email

Avantages sécurité vs passwords :
- Pas de password réutilisé (credential stuffing impossible)
- Pas de password faible (123456, password)
- Pas de phishing password (token expire en 15min)
- Pas de rainbow table (token aléatoire)

Protection :
- Token impossible à deviner (2^256 combinaisons)
- Rate limiting empêche brute force
- Email compromise = accès temporaire (15min max)

#### RBAC - Role-Based Access Control (ADR-021)

Contrôle d'accès basé sur les rôles utilisateur.

Rôles :
- `:admin` : accès complet interface admin
- `:user` : accès restreint (futur)

Implémentation :

```elixir
# plugs/require_auth.ex:126
def require_admin_role(conn, _opts) do
  if user.role in [:admin] do
    conn
  else
    redirect(to: "/")
  end
end
```

Protection :
- Séparation privilèges (principle of least privilege)
- Escalation verticale impossible (user → admin)
- Contrôle au niveau pipeline + LiveView

#### Session Management (ADR-022)

Gestion sécurisée des sessions utilisateur.

Configuration :

```elixir
# endpoint.ex
@session_options [
  store: :cookie,
  signing_salt: "sisdz80o",     # Secret signature
  same_site: "Lax",
  secure: true,                  # HTTPS uniquement
  http_only: true,               # Pas accessible JavaScript
  max_age: 24 * 60 * 60,        # 24h expiration
]
```

Sécurité :
- Cookie signé (tamper-proof)
- HttpOnly (protection XSS - JS ne peut pas lire)
- Secure (HTTPS uniquement - MITM impossible)
- SameSite=Lax (protection CSRF)
- Expiration 24h (limite window attaque)

Session en base de données :
- Tracking activité (last_active_at)
- Révocation possible (logout invalide session)
- Détection sessions multiples

Protection :
- Session hijacking difficile (cookie signé + HTTPS)
- XSS ne peut pas voler session (HttpOnly)
- Session expirée après 24h inactivité

#### Cache Session (Cachex)

Cache en mémoire pour réduire requêtes DB sur sessions actives.

Configuration :

```elixir
# plugs/require_auth.ex:99
Cachex.fetch(:portfolio_cache, {:session, token}, fn ->
  Auth.get_session_by_token(token)
  {:commit, session, ttl: :timer.hours(1)}
end)
```

Sécurité :
- TTL 1h (invalidation automatique)
- Cache invalidé au logout
- Session DB reste source de vérité

Protection :
- Performance améliorée (moins de charge DB)
- Pas de compromis sécurité (TTL court)

Documentation : ADR-020, ADR-021, ADR-022

### Couche 7: Validation et Encoding

Validation des entrées et encoding des sorties pour prévenir injection.

#### Input Validation (Ecto Changesets)

Validation stricte de toutes les entrées utilisateur.

Exemple Album :

```elixir
# photography/album.ex:138
def changeset(album, attrs) do
  album
  |> cast(attrs, [:title, :type, :description, ...])
  |> validate_required([:title, :type, :date_prise_vue])
  |> validate_length(:title, min: 3, max: 200)
  |> validate_length(:description, max: 5000)
  |> validate_date_not_future(:date_prise_vue)
  |> unique_constraint(:slug)
end
```

Protections :
- Longueur limitée (prévient buffer overflow, DoS)
- Format validé (email regex RFC 5322)
- Unicité garantie (slug, email)
- Dates cohérentes (pas de dates futures)

Exemple User :

```elixir
# auth/user.ex:93
defp validate_email(changeset) do
  changeset
  |> validate_format(:email, @email_regex)  # RFC 5322
  |> validate_length(:email, max: 160)
  |> update_change(:email, &String.downcase/1)  # Normalisation
  |> unique_constraint(:email)
end
```

Protection :
- Email valide uniquement (prévient injection via email)
- Longueur max 160 (DoS par email très long)
- Normalisation (email@Example.com == email@example.com)

#### SQL Injection Protection (Ecto Parameterized Queries)

Ecto utilise toujours des requêtes paramétrées (jamais de string interpolation).

Exemple sécurisé :

```elixir
# repositories/album_repository.ex
def get_album_by_slug(slug) do
  from(a in Album, where: a.slug == ^slug)  # ← Paramètre ^slug
  |> Repo.one()
end
```

SQL généré :

```sql
SELECT * FROM albums WHERE slug = $1;
-- Paramètre: $1 = "wedding-2024"
```

Protection :
- Impossible d'injecter SQL via slug
- Ecto échappe automatiquement les paramètres
- Aucune interpolation string dans requêtes

Exemple attaque prévenue :

```elixir
# ❌ DANGEREUX (jamais faire ça)
slug = "'; DROP TABLE albums; --"
query = "SELECT * FROM albums WHERE slug = '#{slug}'"

# ✅ SÛR (Ecto fait toujours ça)
from(a in Album, where: a.slug == ^slug)
```

#### Output Encoding (HEEx Templates)

HEEx encode automatiquement toutes les variables pour prévenir XSS.

Template sécurisé :

```heex
<!-- album_live/index.html.heex -->
<h1><%= @album.title %></h1>
<!-- Si title = "<script>alert('XSS')</script>" -->
<!-- Rendu: &lt;script&gt;alert('XSS')&lt;/script&gt; -->
```

Protection :
- Auto-escape HTML par défaut
- Impossible d'injecter balises <script>
- Protection XSS automatique

Bypass si nécessaire (dangereux) :

```heex
<div><%= raw(@trusted_html) %></div>  # ⚠️ Dangereux, éviter
```

Recommandation : Ne jamais utiliser `raw/1` sur input utilisateur.

#### File Upload Validation

Validation stricte des fichiers uploadés.

Configuration LiveView :

```elixir
# album_live/edit.ex:36
allow_upload(:photos,
  accept: ~w(.jpg .jpeg .png .webp),  # Extensions autorisées
  max_entries: 20,                    # Max 20 fichiers
  max_file_size: 10_000_000,         # 10 Mo max
  auto_upload: true
)
```

Validation supplémentaire :

```elixir
# local_storage.ex:72
defp validate_image_file(path) do
  case Vix.Vips.Image.new_from_file(path) do
    {:ok, _image} -> :ok              # Vraie image
    {:error, _} -> {:error, :invalid_image}  # Fichier corrompu/malveillant
  end
end
```

Protections :
- Extension validée (pas de .exe, .php)
- Taille limitée (DoS par upload 10 Go impossible)
- Magic bytes vérifiés (Vix valide que c'est vraiment une image)
- Renommage fichier (slug unique, pas de path traversal)

Exemple attaque prévenue :

```
1. Attaquant upload "photo.jpg" (en réalité PHP shell)
2. Extension validée : .jpg OK
3. Vix tente de lire comme image
4. Vix détecte que ce n'est pas une image valide
5. Upload rejeté : {:error, :invalid_image}
```

#### EXIF Sanitization

Suppression des métadonnées EXIF potentiellement sensibles.

Implémentation :

```elixir
# image_processor.ex:195
defp strip_metadata(vips_image) do
  Vix.Vips.Operation.copy(vips_image, 
    interpretation: :VIPS_INTERPRETATION_sRGB
  )
end
```

Protection :
- Supprime GPS coordinates (vie privée)
- Supprime camera model, serial number
- Supprime date/heure originale
- Conserve uniquement données techniques nécessaires

Métadonnées supprimées :
- GPS Latitude/Longitude (localisation exacte)
- Camera Make/Model (empreinte matériel)
- Copyright/Author (PII)
- Date Time Original (timeline personnes)

Documentation : ADR-011 Image Processing

## Matrice de Défense Multi-Couches

Tableau montrant comment chaque vecteur d'attaque est bloqué par plusieurs couches :

| Vecteur Attaque | Couche 1 | Couche 2 | Couche 3 | Couche 4 | Couche 5 | Couche 6 | Couche 7 |
|-----------------|----------|----------|----------|----------|----------|----------|----------|
| CSRF | - | - | CSP | Token + SameSite | - | - | - |
| XSS | - | - | CSP | - | - | HttpOnly | HEEx Escape |
| SQL Injection | - | - | - | - | - | - | Ecto Params |
| Clickjacking | - | - | X-Frame-Options | - | - | - | - |
| Session Hijack | - | HTTPS | HSTS | SameSite | - | HttpOnly + Secure | - |
| Brute Force | fail2ban | - | - | - | Rate Limit | Session Expiry | - |
| DDoS | Firewall + CF | - | - | - | Rate Limit | - | - |
| MITM | - | HTTPS + HSTS | - | - | - | Secure Cookie | - |
| Upload Malware | - | - | CSP | - | File Size | - | Vix Validation |
| Email Spam | fail2ban | - | - | - | Rate Limit | Magic Link TTL | Email Validation |
| Path Traversal | - | - | - | - | - | - | Slug Generation |
| EXIF Exploit | - | - | - | - | - | - | Metadata Strip |

Lecture du tableau :
- Chaque ligne = un vecteur d'attaque
- Chaque colonne = une couche de défense
- Si une couche est compromise, les autres continuent de protéger

Exemple : CSRF
- Couche 3 : CSP empêche script externe
- Couche 4 : Token CSRF + SameSite cookie
- Même si CSP contournée (`unsafe-inline`), token CSRF protège

Exemple : XSS
- Couche 3 : CSP limite sources scripts
- Couche 6 : HttpOnly empêche vol session via JS
- Couche 7 : HEEx encode automatiquement

Principe : Aucune couche unique ne doit être SPOF (Single Point of Failure).

## Outils de Vérification Sécurité

### Outils Utilisés (CI/CD)

#### Sobelow (Static Analysis)

Analyse statique du code Elixir pour détecter vulnérabilités.

Configuration :

```elixir
# mix.exs:206
aliases: [
  precommit: [
    "sobelow --config",  # Check sécurité avant commit
    # ...
  ]
]
```

Détections :
- SQL Injection potentielle (Ecto fragments non paramétrés)
- XSS (usage de `raw/1`, `html_escape: false`)
- CSRF désactivé (pipeline sans `protect_from_forgery`)
- Secrets hardcodés (API keys en clair)
- Configuration insecure (SSL disabled, etc.)

Résultat actuel : 0 vulnérabilité détectée ✅

#### Credo (Code Quality)

Analyse qualité code, inclut certains checks sécurité.

Configuration :

```elixir
# mix.exs:205
"credo --strict",
```

Checks sécurité :
- Usage de `String.to_atom/1` sur input user (DoS mémoire)
- Pattern matching non exhaustif (crash app)
- Warning variables non utilisées (dead code)

#### deps.audit (Dependencies)

Vérifie les dépendances pour vulnérabilités connues (CVE).

Configuration :

```elixir
# mix.exs:207
"deps.audit",
```

Détections :
- CVE dans dépendances hex.pm
- Paquets retirés (retired packages)
- Versions obsolètes avec vulnérabilités

Exécution : À chaque `mix precommit` et en CI

### Outils Recommandés (Non implémentés)

#### OWASP ZAP (Dynamic Analysis)

Scanner de vulnérabilités web dynamique.

Usage :

```bash
# Scan automatique
docker run -t owasp/zap2docker-stable zap-baseline.py \
  -t https://photo.thibaultsan.com

# Détecte :
# - Headers sécurité manquants
# - Cookies insecure
# - Redirects open
# - XSS, SQLi, CSRF
```

Priorité : Moyenne (scan mensuel recommandé)

#### Mozilla Observatory

Scan en ligne des headers HTTP et configuration SSL.

Usage : https://observatory.mozilla.org/

Tests :
- Headers sécurité (CSP, HSTS, X-Frame-Options)
- Configuration SSL/TLS
- Cookies attributes (Secure, HttpOnly, SameSite)
- Redirects HTTP → HTTPS

Score attendu : A ou A+ avec config actuelle

Priorité : Basse (check manuel ponctuel)

#### SSL Labs (SSL Test)

Analyse détaillée de la configuration SSL/TLS.

Usage : https://www.ssllabs.com/ssltest/

Tests :
- Version TLS (1.2+ requis)
- Cipher suites (faibles désactivés)
- Certificat validité
- HSTS présent

Score attendu : A ou A+

Priorité : Basse (check initial puis annuel)

## Monitoring et Détection

### Logs Sécurité

Événements loggés pour audit sécurité :

```elixir
# Rate limit dépassé
Logger.warning("Rate limit exceeded",
  action: :magic_link_request,
  identifier: "user@example.com",
  ip: "203.0.113.42"
)

# CSRF token invalide
Logger.error("CSRF token mismatch",
  path: "/admin/albums",
  ip: "203.0.113.42"
)

# Login réussi
Logger.info("User logged in",
  user_id: user.id,
  email: user.email,
  ip: "203.0.113.42"
)

# Upload fichier rejeté
Logger.warning("Invalid image upload rejected",
  filename: "malware.jpg",
  user_id: user.id
)
```

Format : JSON structuré en production (ADR-042)

### Métriques Telemetry (Recommandé)

Métriques sécurité à tracker :

```elixir
# Dans Telemetry.ex
defp metrics do
  [
    # Rate limiting
    counter("portfolio.rate_limiter.denied.count"),
    last_value("portfolio.rate_limiter.denied.ip"),
    
    # CSRF
    counter("portfolio.csrf.invalid_token.count"),
    
    # Auth
    counter("portfolio.auth.login_failed.count"),
    counter("portfolio.auth.session_expired.count"),
    
    # Upload
    counter("portfolio.upload.rejected.count"),
  ]
end
```

Exploitation :
- LiveDashboard : visualisation temps réel
- Alerting : email si > N rate limits en 10 min

Statut : Non implémenté, priorité moyenne

### Alerting (Futur)

Alertes automatiques sur événements sécurité suspects.

Déclencheurs recommandés :

```
1. > 50 rate limits dépassés en 10 min
   → Email admin + log critique

2. > 10 tokens CSRF invalides en 1h
   → Possible attaque CSRF, investigation

3. > 5 uploads fichiers rejetés par même user
   → Possible upload malware, ban user

4. Session admin créée depuis IP nouvelle
   → Email confirmation (2FA future)
```

Implémentation possible :
- Newsletter (email basique)
- Slack webhook
- PagerDuty (si critique)

Statut : Non implémenté, priorité basse

## Limites et Faiblesses Connues

### 1. CSP avec unsafe-inline (Impact: Moyen)

Problème : `script-src 'unsafe-inline'` affaiblit protection XSS

Raison : Alpine.js + Tailwind Play CDN requièrent inline scripts

Risque :
- XSS par injection inline script possible
- Moins sévère que XSS par script externe (bloqué par CSP)

Mitigation :
- HEEx encode toutes les sorties (double protection)
- Migration future vers nonce-based CSP (ADR-051)

Acceptable : Oui pour phase actuelle (Alpine.js prioritaire pour UX)

### 2. Rate Limiting avec backend ETS (Impact: Faible)

Problème : État rate limiting perdu au redémarrage app

Raison : Hammer backend ETS (in-memory)

Risque :
- Redémarrage app → tous compteurs reset
- Attaquant peut attendre redémarrage pour contourner

Fréquence : Redémarrages rares (déploiements ~1x/semaine)

Mitigation :
- fail2ban au niveau infrastructure (persistant)
- Migration Hammer + Redis si scaling horizontal futur

Acceptable : Oui pour single instance actuel

### 3. Pas de 2FA (Impact: Moyen)

Problème : Authentification single-factor (email uniquement)

Raison : Complexité vs bénéfice pour portfolio personnel

Risque :
- Compromise email → accès admin complet
- Pas de layer supplémentaire après email

Mitigation actuelle :
- Magic link expiration 15 min
- Rate limiting sur génération links
- Email provider sécurisé (Gmail, ProtonMail)

Future : 2FA recommandé si données sensibles augmentent

Acceptable : Oui pour portfolio personnel (pas de données critiques)

### 4. Pas de WAF (Web Application Firewall) (Impact: Faible)

Problème : Pas de WAF devant l'application

Raison : Cloudflare WAF payant (plan Pro $20/mois)

Risque :
- Attaques sophistiquées (0-day) pas détectées
- Pas de rules custom (block patterns)

Mitigation :
- Défense en profondeur compense (7 couches)
- Cloudflare Free DDoS protection active

Future : WAF si budget permet ou si attaques détectées

Acceptable : Oui pour trafic actuel faible

### 5. Secrets en variables environnement (Impact: Faible)

Problème : Secrets stockés en variables env (non chiffrés)

Raison : Simplicité déploiement Kamal

Risque :
- Accès root serveur → lecture secrets
- Process dump peut exposer env vars

Mitigation :
- Accès SSH restreint (clé publique uniquement)
- User non-root pour app (principe least privilege)

Future : Vault (HashiCorp) ou secrets manager si équipe grandit

Acceptable : Oui pour développeur solo avec accès root

## Plan d'Action Sécurité

### Court Terme (Priorité: HAUTE)

1. Implémenter fail2ban
   - Installation serveur Hetzner
   - Configuration filter Phoenix logs
   - Test bannissement après 20 rate limits
   - Documentation procédure débannissement
   - Estimation : 0.5 jour

2. Ajouter tests sécurité
   - Tests CSRF (POST sans token → 403)
   - Tests rate limiting (dépassement limite)
   - Tests upload fichier malveillant
   - Tests SQL injection (tentatives paramètres)
   - Estimation : 1 jour

3. Scanner Mozilla Observatory
   - Scan initial score baseline
   - Corrections headers si nécessaire
   - Documentation résultat
   - Estimation : 0.5 jour

4. Ajouter rate limit par IP
   - Limite 20 magic links/h par IP
   - Complément limite par email
   - Tests intégration
   - Estimation : 0.5 jour

### Moyen Terme (Priorité: MOYENNE)

1. **Métriques Telemetry sécurité**
   - Compteurs rate limit denied
   - Compteurs CSRF invalid
   - Compteurs upload rejected
   - LiveDashboard visualisation
   - Estimation : 1 jour

2. **HSTS Preload**
   - Ajouter directive `preload`
   - Soumettre à hstspreload.org
   - Validation inclusion liste
   - Estimation : 0.25 jour

3. **Migration CSP nonce-based**
   - Remplacer `unsafe-inline` par nonce
   - Compatibilité Alpine.js
   - Tests tous navigateurs
   - Estimation : 2 jours
   - Documentation : ADR-051

4. Scan OWASP ZAP
   - Scan baseline automatique
   - CI/CD intégration
   - Corrections vulnérabilités détectées
   - Estimation : 1 jour

### Long Terme (Priorité: BASSE)

1. 2FA (Two-Factor Authentication)
   - TOTP (Google Authenticator)
   - Backup codes
   - Interface admin gestion 2FA
   - Estimation : 3-5 jours

2. Alerting automatique
   - Webhook Newsletter/Slack
   - Seuils configurables
   - Dashboard événements sécurité
   - Estimation : 2 jours

3. WAF si budget
   - Cloudflare Pro ($20/mois)
   - Rules custom anti-bot
   - Rate limiting Cloudflare
   - Estimation : 1 jour config

4. Secrets management
   - Migration vers Vault ou AWS Secrets Manager
   - Rotation automatique secrets
   - Audit trail accès secrets
   - Estimation : 3-5 jours

## Références

### Standards et Best Practices

- OWASP Top 10 2021 : https://owasp.org/Top10/
- OWASP Defense in Depth : https://owasp.org/www-community/Defense_in_Depth
- CWE Top 25 : https://cwe.mitre.org/top25/
- NIST Cybersecurity Framework : https://www.nist.gov/cyberframework

### Documentation Phoenix/Elixir

- Phoenix Security : https://hexdocs.pm/phoenix/security.html
- Plug Security : https://hexdocs.pm/plug/Plug.SSL.html
- Ecto Security : https://hexdocs.pm/ecto/Ecto.Query.html#module-security

### Outils

- Sobelow : https://github.com/nccgroup/sobelow
- Mozilla Observatory : https://observatory.mozilla.org/
- SSL Labs : https://www.ssllabs.com/
- OWASP ZAP : https://www.zaproxy.org/

### ADRs Connexes

- ADR-020 : Magic Link Passwordless Auth
- ADR-021 : RBAC Role-Based Access Control
- ADR-022 : Session Management
- ADR-023 : Rate Limiting
- ADR-024 : CSRF Protection
- ADR-025 : Email Validation
- ADR-043 : Deployment Docker Kamal Hetzner
- ADR-044 : CDN Strategy Cloudflare
- ADR-051 : Content Security Policy (à créer)
- ADR-052 : Security Headers Strategy (à créer)

### Fichiers Code Concernés

- `lib/portfolio_web/endpoint.ex` : Headers sécurité, session config
- `lib/portfolio_web/router.ex` : Pipelines CSRF, auth
- `lib/portfolio/rate_limiter.ex` : Rate limiting
- `lib/portfolio_web/plugs/require_auth.ex` : Authentification
- `lib/portfolio/auth/user.ex` : Validation email
- `lib/portfolio/photography/album.ex` : Validation input
- `lib/portfolio/photography/storage/local_storage.ex` : Upload validation
- `lib/portfolio/image_processor.ex` : EXIF sanitization
- `mix.exs` : Outils sécurité (Sobelow, deps.audit)

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
