# ADR-023: Rate Limiting et Protection Anti-Abus

Statut: Accepté
Date: 2025-07

## Contexte

Les applications web exposées publiquement sont vulnérables � divers types d'abus :
- Spam d'emails via magic links (coût SMTP, réputation domaine)
- Brute force sur les tokens de magic links
- Déni de service (DoS) par saturation des ressources
- Énumération d'utilisateurs valides
- Abuse de fonctionnalités coûteuses (upload, processing)

Le rate limiting est une technique de défense essentielle qui limite le nombre de requêtes qu'un client peut effectuer dans un intervalle de temps donné. Plusieurs approches existent :

- Rate limiting au niveau application (Elixir/Phoenix)
- Rate limiting au niveau reverse proxy (Nginx, Traefik)
- Rate limiting au niveau CDN/WAF (Cloudflare, AWS WAF)
- Protection syst�me via fail2ban (bannissement IP niveau firewall)

Pour ce portfolio, le choix s'est porté sur une approche hybride : rate limiting applicatif avec Hammer (biblioth�que Elixir) complété par des recommandations de protection infrastructure.

## Décision

Le syst�me utilise Hammer (biblioth�que Elixir) avec backend ETS (in-memory) pour implémenter un rate limiting granulaire par type d'action. Trois niveaux de protection sont définis : par email, par IP, et au niveau global de l'application.

### Architecture du rate limiting

#### 1. Module RateLimiter

Le module `Portfolio.RateLimiter` encapsule la logique de rate limiting :

```elixir
@rate_limits %{
  # 5 magic link requests per hour per email
  magic_link_request: {5, :timer.hours(1)},
  # 10 magic link verification attempts per 5 minutes per IP
  magic_link_verify: {10, :timer.minutes(5)},
  # Rate limit global pour l'application
  magic_link_global: {100, :timer.hours(1)}
}
```

API principale :
- `check_rate(action, identifier)` : vérifie si une action est autorisée
- `reset(action, identifier)` : reset manuel du compteur (admin, tests)
- `limit(action)` : retourne la configuration d'une limite

#### 2. Configuration des limites

##### Magic link request (par email)

**Limite** : 5 requêtes par heure par email

**Justification** :
- Empêche le spam d'un email spécifique
- Permet les cas d'usage légitimes (erreur de frappe, lien perdu)
- Basé sur l'expérience pratique d'utilisation

**Identifier** : adresse email en minuscules

**Exemple** :
```elixir
RateLimiter.check_rate(:magic_link_request, "user@example.com")
# {:allow, 4} ou {:deny, 3540000}
```

##### Magic link request (par IP) - AJOUT RECOMMANDÉ

**Limite** : 20 requêtes par heure par IP

**Justification** :
- Protection contre un attaquant qui spam avec plusieurs emails différents depuis la même IP
- Complément � la limite par email
- Permet � plusieurs utilisateurs légitimes derri�re le même NAT (entreprise, famille)

**Identifier** : adresse IP (via `X-Forwarded-For` ou `remote_ip`)

**Implémentation recommandée** :
```elixir
@rate_limits %{
  magic_link_request_by_email: {5, :timer.hours(1)},
  magic_link_request_by_ip: {20, :timer.hours(1)},
  # ...
}
```

Vérification dans `MagicLinkAuthService` :
```elixir
with {:ok, :allowed_email} <- check_email_rate_limit(email),
     {:ok, :allowed_ip} <- check_ip_rate_limit(ip) do
  # Proceed
else
  {:error, :rate_limit_exceeded} -> {:error, :rate_limit_exceeded}
end
```

##### Magic link verify (par IP)

**Limite** : 10 tentatives toutes les 5 minutes par IP

**Justification** :
- Protection contre brute force sur les tokens
- Fenêtre courte (5 min) car risque élevé (attaque active)
- Par IP car l'email n'est pas connu lors de la vérification

**Identifier** : adresse IP

**Application** : via `RateLimiterPlug` dans `AuthController` (ligne 12)

##### Magic link global (application)

**Limite** : 100 requêtes par heure pour toute l'application

**Justification** :
- Protection contre attaque distribuée (botnet)
- Détection d'anomalie (pic inhabituel)
- Soft limit : logge une alerte sans bloquer les users légitimes

**Identifier** : constante "global"

**Implémentation recommandée** :
```elixir
defp check_global_rate_limit do
  case RateLimiter.check_rate(:magic_link_global, "global") do
    {:allow, _remaining} ->
      :ok
    {:deny, _retry_after} ->
      Logger.error("[SECURITY] Global rate limit exceeded - possible attack")
      # NE PAS bloquer, juste alerter
      :ok
  end
end
```

Configuration dans `config/config.exs` :
```elixir
config :portfolio, :rate_limiting,
  global_magic_link_limit: 100,
  global_magic_link_period_hours: 1
```

##### Login attempt (SUPPRIMÉ)

**Observation** : limite `login_attempt` définie mais jamais utilisée.

**Raison** : redondante avec `magic_link_request` (pas de formulaire password classique).

**Action** : supprimer de `@rate_limits` (dette technique).

#### 3. Choix de Hammer comme biblioth�que

##### Évaluation des alternatives

**Hammer** (choix retenu) :
-  Solution mature et éprouvée dans l'écosyst�me Elixir
-  API simple et idiomatique
-  Plusieurs backends (ETS, Redis, Mnesia)
-  Performance excellente avec ETS in-memory
-  Pas de dépendance externe en mode ETS
-  État perdu au redémarrage avec ETS
-  Pas de sharing entre instances (probl�me multi-instances)

**PlugAttack** :
-  Plus flexible (custom strategies, throttling, blacklist)
-  Mieux intégré avec Plug
-  Moins mature (moins d'adoption)
-  Documentation moins compl�te
-  API moins ergonomique

**ExRated** :
-  Simple et léger
-  Moins de fonctionnalités
-  Moins maintenu (derni�re release ancienne)

**Custom Redis** :
-  State partagé entre instances
-  Persistance au redémarrage
-  Dépendance externe (Redis)
-  Complexité opérationnelle
-  Over-engineering pour usage actuel

**Décision** : Hammer avec backend ETS est le meilleur choix pour le contexte actuel (single instance, simplicité). Migration vers Hammer + Redis backend possible � l'avenir si scaling horizontal nécessaire.

##### Configuration Hammer

Dans `application.ex` (ligne 18) :
```elixir
{Hammer.Backend.ETS, [
  expiry_ms: 60_000 * 60 * 1,        # 1 heure (corrigé depuis 2h)
  cleanup_interval_ms: 60_000 * 10   # Cleanup toutes les 10 minutes
]}
```

Configuration :
- `expiry_ms` : durée de rétention des buckets (1h, aligné avec rate limits max)
- `cleanup_interval_ms` : fréquence du nettoyage des buckets expirés (10 min)

Note importante : correction de `expiry_ms` de 2h � 1h car les rate limits maximum sont de 1h. Pas besoin de garder les buckets plus longtemps.

#### 4. Application du rate limiting

Le rate limiting est appliqué � deux niveaux :

##### Niveau Service (MagicLinkAuthService)

Protection au niveau business logic :

```elixir
def request_magic_link(email) do
  case Portfolio.RateLimiter.check_rate(:magic_link_request, email) do
    {:deny, _retry_after} ->
      {:error, :rate_limit_exceeded}
    {:allow, _remaining} ->
      do_request_magic_link(email)
  end
end
```

Avantages :
- Protection indépendante du controller (testable)
- Erreur typée retournée au caller
- Cohérence métier (r�gle appliquée partout)

##### Niveau Controller (RateLimiterPlug)

Protection au niveau HTTP via plug :

```elixir
# Dans AuthController
plug PortfolioWeb.Plugs.RateLimiterPlug,
     [action: :magic_link_verify, identifier: :ip]
     when action in [:verify_magic_link]
```

Le plug `RateLimiterPlug` :
- Extrait l'identifier (IP, param, custom)
- Vérifie le rate limit
- Retourne 429 avec header `Retry-After` si dépassé
- Redirige vers `/login` avec message flash

Avantages :
- Protection au niveau HTTP (avant logique métier)
- Header `Retry-After` standard
- Message utilisateur localisé

Observation : pas de redondance entre les deux niveaux car actions différentes :
- Service : prot�ge `magic_link_request` (création du lien)
- Controller : prot�ge `magic_link_verify` (vérification du token)

#### 5. Identification des requêtes

Le syst�me utilise deux types d'identifiers :

##### Par email (magic_link_request)

```elixir
identifier = String.downcase(email)
```

Avantages :
- Limite par utilisateur individuel
- Empêche le spam d'un compte spécifique

Inconvénient :
- Un attaquant peut utiliser plusieurs emails

Solution : combiner avec rate limit par IP (recommandé).

##### Par IP (magic_link_verify)

```elixir
defp get_ip_address(conn) do
  case get_req_header(conn, "x-forwarded-for") do
    [ip | _] ->
      ip
      |> String.split(",")
      |> List.first()
      |> String.trim()
    [] ->
      conn.remote_ip
      |> :inet.ntoa()
      |> to_string()
  end
end
```

Logique d'extraction :
1. Priorité au header `X-Forwarded-For` (reverse proxy Traefik via Kamal)
2. Fallback sur `remote_ip` si header absent

Contexte infrastructure :
- Application déployée via Kamal avec reverse proxy Traefik
- Traefik set automatiquement le header `X-Forwarded-For`
- Extraction du premier IP de la liste (client original)

Avantages :
- Protection contre attaques depuis une IP spécifique
- Compatible avec proxy/load balancer

Inconvénients :
- Plusieurs users derri�re un NAT partagent la même IP (entreprise, famille)
- Un attaquant peut utiliser un botnet (IPs différentes)

Solution partielle : rate limit global application.

#### 6. Gestion des erreurs et UX

##### Message d'erreur dans LoginLive

Lorsque le rate limit est dépassé (service level) :

```elixir
{:error, :rate_limit_exceeded} ->
  {:noreply,
   socket
   |> put_flash(
     :error,
     "Trop de tentatives. Veuillez patienter avant de réessayer."
   )}
```

Message générique sans détail de temps (pour ne pas aider l'attaquant).

##### Header Retry-After (controller level)

Le plug `RateLimiterPlug` set le header standard :

```elixir
conn
|> put_resp_header("retry-after", to_string(retry_after_seconds))
|> put_flash(:error, "Trop de tentatives. Veuillez patienter #{format_retry_time(retry_after_ms)}...")
|> redirect(to: "/login")
```

Le helper `format_retry_time/1` formate en français :
- "X seconde(s)"
- "X minute(s)"
- "X heure(s)"

##### Améliorations UX recommandées

1. Countdown JavaScript :
```javascript
// Lire le header Retry-After
const retryAfter = parseInt(response.headers.get('Retry-After'));

// Afficher un compteur dégressif
let remaining = retryAfter;
const interval = setInterval(() => {
  remaining--;
  updateUI(`Réessayez dans ${remaining}s`);
  if (remaining <= 0) clearInterval(interval);
}, 1000);
```

Bénéfice : feedback temps réel pour l'utilisateur.

2. **Disable du bouton submit** pendant le rate limit :
```elixir
# Dans LoginLive
assign(socket, :rate_limited_until, DateTime.add(DateTime.utc_now(), retry_after_seconds, :second))

# Template
<button disabled={rate_limited?(@rate_limited_until)}>
  <%= if rate_limited?(@rate_limited_until) do %>
    Réessayez dans <%= countdown(@rate_limited_until) %>
  <% else %>
    Envoyer le lien
  <% end %>
</button>
```

Bénéfice : empêche les clics inutiles, meilleure UX.

#### 7. Logs et monitoring

##### Logs actuels

Niveau DEBUG (succ�s) :
```elixir
Logger.debug("Rate limit check passed",
  action: action,
  identifier: identifier,
  remaining: remaining
)
```

Niveau WARNING (rate limit dépassé) :
```elixir
Logger.warning("Rate limit exceeded",
  action: action,
  identifier: identifier,
  retry_after_ms: retry_after
)
```

##### Logs recommandés supplémentaires

Pour mieux détecter les attaques :

```elixir
Logger.warning("Rate limit exceeded",
  action: action,
  identifier: identifier,
  retry_after_ms: retry_after,
  user_agent: get_req_header(conn, "user-agent") |> List.first(),
  referer: get_req_header(conn, "referer") |> List.first(),
  timestamp: DateTime.utc_now()
)
```

Permet d'analyser les patterns (user-agent bot, referer suspect, etc.).

##### Métriques Telemetry recommandées

```elixir
# Dans RateLimiter.check_rate/2
case Hammer.check_rate(bucket_key, period, limit) do
  {:allow, count} ->
    :telemetry.execute(
      [:portfolio, :rate_limiter, :allowed],
      %{count: 1},
      %{action: action, remaining: limit - count}
    )
    # ...

  {:deny, _limit} ->
    :telemetry.execute(
      [:portfolio, :rate_limiter, :denied],
      %{count: 1},
      %{action: action, identifier: identifier}
    )
    # ...
end
```

Exploitation via LiveDashboard ou export Prometheus :
- Nombre de requêtes bloquées par action
- Top IPs bloquées
- Patterns temporels (heures de pic d'attaques)

##### Alerting (futur)

Configuration recommandée pour détecter les attaques :

```elixir
# Si > 50 rate limits dépassés en 10 minutes � alert
if count_rate_limits_last_10_min() > 50 do
  send_alert_email(admin_email, "Possible attack detected")
  send_slack_notification("#security", "Rate limit spike detected")
end
```

Actuellement non implémenté (priorité basse).

#### 8. Protection des utilisateurs légitimes

##### Blocage des emails inconnus en production

**Problématique** : en production, seuls les utilisateurs enregistrés doivent pouvoir se connecter. Actuellement, tout email peut demander un magic link (limité � 5/h).

**Solution recommandée** :

```elixir
# Dans UserService.get_or_create_user/1
defp create_user_if_allowed(email) do
  if Mix.env() in [:dev, :test] do
    # Dev/test : créer automatiquement
    %User{}
    |> User.registration_changeset(%{email: email})
    |> Repo.insert()
  else
    # Production : refuser les emails inconnus
    {:error, :user_not_found}
  end
end
```

Déj� implémenté correctement 

**Amélioration** : retourner une erreur générique pour ne pas révéler si un email est enregistré (énumération) :

```elixir
# Dans LoginLive, même message pour :user_not_found et :rate_limit_exceeded
{:error, :user_not_found} ->
  {:noreply, put_flash(socket, :error, "Un lien vous a été envoyé si votre email est enregistré.")}
```

Protection contre énumération d'utilisateurs valides.

##### Reset manuel pour admin

**Cas d'usage** : utilisateur légitime bloqué par erreur (ex: teste plusieurs fois son email).

**Fonction déj� existante** :
```elixir
RateLimiter.reset(:magic_link_request, "user@example.com")
```

**Interface admin recommandée** :

Dans `/admin/users`, ajouter un bouton "Reset rate limits" :

```elixir
def handle_event("reset_rate_limits", %{"user-id" => user_id}, socket) do
  user = Enum.find(socket.assigns.users, &(&1.id == user_id))

  RateLimiter.reset(:magic_link_request, user.email)
  RateLimiter.reset(:magic_link_verify, user.email)

  {:noreply, put_flash(socket, :info, "Rate limits réinitialisés pour #{user.email}")}
end
```

Priorité moyenne (nice-to-have).

##### Whitelist d'IPs (futur)

**Cas d'usage** : bureau de l'admin, IPs de confiance.

**Implémentation possible** :

```elixir
# config/config.exs
config :portfolio, :rate_limiting,
  whitelisted_ips: ["192.168.1.100", "203.0.113.42"]

# Dans RateLimiterPlug
defp whitelisted?(ip) do
  Application.get_env(:portfolio, :rate_limiting, [])
  |> Keyword.get(:whitelisted_ips, [])
  |> Enum.member?(ip)
end

def call(conn, opts) do
  ip = get_ip_address(conn)

  if whitelisted?(ip) do
    conn
  else
    # Check rate limit normalement
  end
end
```

Priorité basse (futur).

#### 9. Limitations et risques

##### Perte d'état au redémarrage (ETS)

**Risque** : les compteurs Hammer sont en mémoire (ETS). Au redémarrage de l'application, tous les rate limits sont réinitialisés.

**Impact** :
- Redémarrage fréquent : protection inefficace
- Redémarrage rare : impact négligeable

**Contexte actuel** : déploiements peu fréquents, acceptable.

**Migration future** : si redémarrages fréquents ou scaling horizontal � Hammer + Redis backend :

```elixir
# Dans application.ex
children = [
  # ...
  {Hammer.Backend.Redis, [
    redis_url: System.get_env("REDIS_URL"),
    pool_size: 10,
    expiry_ms: 60_000 * 60
  ]}
]

# Dans config/config.exs
config :hammer,
  backend: {Hammer.Backend.Redis, []}
```

##### Pas de sharing entre instances (multi-instances)

**Risque** : avec backend ETS, chaque instance Phoenix a son propre état. Les rate limits ne sont pas partagés.

**Exemple** :
- Instance A : user fait 5 requêtes (bloqué)
- Instance B : même user fait 5 requêtes (bloqué)
- Total : 10 requêtes au lieu de 5

**Impact** : avec load balancer, efficacité réduite de moitié (ou plus).

**Contexte actuel** : déploiement single instance via Kamal, pas de probl�me.

**Migration future** : si scaling horizontal � Hammer + Redis (état partagé).

Documentation de cette limitation critique pour décisions futures.

##### Contournement via botnet (IPs distribuées)

**Risque** : attaquant utilise un botnet (milliers d'IPs différentes) pour spam magic links.

**Protection actuelle** :
- Limite par email : 5/h (empêche spam d'un compte)
- Limite par IP : 20/h recommandée (réduit l'impact)

**Protection recommandée** :
- Limite globale : 100/h application (détection anomalie)
- Limite ne bloque pas mais alerte (soft limit)

**Protection infrastructure** (complément) :
- Cloudflare rate limiting (payant)
- fail2ban (bannissement IP niveau firewall)

##### Énumération d'utilisateurs

**Risque** : message d'erreur différent pour "email inconnu" vs "rate limit dépassé" permet d'énumérer les emails valides.

**Protection** : message générique identique :

```elixir
# BON
"Un lien vous a été envoyé si votre email est enregistré."

# MAUVAIS
"Email inconnu" vs "Trop de tentatives"
```

Recommandation � implémenter.

#### 10. Protection infrastructure complémentaire

Le rate limiting applicatif (Hammer) doit être complété par des protections infrastructure.

##### fail2ban (recommandé)

**Description** : fail2ban scanne les logs et bannit les IPs malveillantes via iptables.

**Installation** :
```bash
sudo apt install fail2ban
```

**Configuration** : créer `/etc/fail2ban/filter.d/phoenix-auth.conf` :
```
[Definition]
failregex = Rate limit exceeded.*identifier: <HOST>
ignoreregex =
```

Puis `/etc/fail2ban/jail.local` :
```
[phoenix-auth]
enabled = true
port = http,https
filter = phoenix-auth
logpath = /var/log/phoenix/*.log
maxretry = 20
bantime = 3600  # 1 heure
findtime = 600  # 10 minutes
```

**Bénéfice** : protection niveau firewall AVANT que la requête n'atteigne Phoenix. Réduit la charge serveur.

Priorité haute (� implémenter rapidement).

##### Cloudflare rate limiting

**Observation** : Cloudflare free tier ne propose pas de rate limiting avancé (fonctionnalité payante).

**Alternative gratuite Cloudflare** :
- Bot Fight Mode (détection bots basiques)
- Challenge pages (CAPTCHA pour IPs suspectes)
- DDoS protection automatique

**Évaluation** : tester Cloudflare free tier pour bénéficier de la protection DDoS gratuite même sans rate limiting avancé.

Priorité moyenne (recherche et évaluation).

##### Traefik rate limiting (Kamal)

**Observation** : Traefik (reverse proxy Kamal) supporte le rate limiting natif.

**Configuration possible** dans labels Docker :

```yaml
# deploy.yml
labels:
  traefik.http.middlewares.ratelimit.ratelimit.average: 100
  traefik.http.middlewares.ratelimit.ratelimit.burst: 50
```

**Bénéfice** : protection niveau proxy, avant Phoenix.

Priorité basse (complexifie la config Kamal, Hammer suffit pour l'instant).

## Alternatives considérées

### Rate limiting au niveau Nginx/Traefik uniquement

Approche :
- Configurer Traefik/Nginx pour limiter les requêtes
- Pas de code Elixir nécessaire

Avantages :
- Protection au niveau infrastructure
- Performance maximale (pas de traitement applicatif)
- Standard et éprouvé

Inconvénients :
- Moins granulaire (difficulté � différencier actions)
- Pas de visibilité applicative (logs séparés)
- Configuration complexe pour multi-actions
- Pas de logique métier (différencier email connu vs inconnu)

Décision : rejeté. Le rate limiting applicatif permet une granularité et une logique métier que Traefik seul ne peut pas offrir. Traefik peut compléter mais pas remplacer.

### Rate limiting JWT-based

Approche :
- Token JWT contenant un compteur de requêtes
- Vérifié et incrémenté � chaque requête

Avantages :
- Stateless (pas de stockage serveur)
- Scalabilité parfaite

Inconvénients :
- Impossible de révoquer avant expiration token
- Token manipulable côté client (même signé)
- Complexité de renouvellement

Décision : rejeté. Inadapté pour le contexte (magic links passwordless).

### Custom Redis rate limiting

Approche :
- Implémentation manuelle avec Redis INCR + EXPIRE
- Pas de biblioth�que tierce

Avantages :
- Contrôle total de la logique
- Optimisation maximale

Inconvénients :
- Réinventer la roue (Hammer existe et fonctionne)
- Maintenance et bugs potentiels
- Pas de bénéfice pour le cas d'usage

Décision : rejeté selon principe pragmatique. Hammer + Redis backend possible � l'avenir si nécessaire.

## Conséquences

### Positives

- Protection efficace contre spam et brute force
- Biblioth�que Hammer mature et éprouvée
- Configuration granulaire par type d'action
- Logs et monitoring pour détection d'attaques
- UX préservée (messages clairs, header Retry-After)
- Flexibilité (backend ETS maintenant, Redis si scaling futur)
- Protection multi-niveaux (email + IP + global)
- Compatible infrastructure existante (Traefik, Kamal)

### Négatives

- État perdu au redémarrage avec ETS (acceptable pour déploiements rares)
- Pas de sharing entre instances avec ETS (probl�me futur si scaling)
- Contournement possible via botnet (mitigé par limite globale)
- Complexité ajoutée vs pas de rate limiting

### Neutres

- Limites basées sur expérience (pas de modélisation scientifique)
- Trade-off sécurité/UX acceptable pour portfolio personnel
- Hammer ETS adapté au contexte actuel (single instance)
- Migration Redis possible si besoins évoluent

## Améliorations futures

### Court terme (priorité haute)
1. Ajouter rate limit par IP pour `magic_link_request` (20/h)
2. Ajouter rate limit global application (100/h soft limit)
3. Corriger `expiry_ms` Hammer (2h � 1h)
4. Supprimer `login_attempt` inutilisé
5. Configurer fail2ban sur serveur
6. Bloquer emails inconnus avec message générique (anti-énumération)

### Moyen terme (priorité moyenne)
1. Ajouter métriques Telemetry (requêtes bloquées, top IPs)
2. Afficher countdown JavaScript avec header Retry-After
3. Interface admin pour reset rate limits utilisateur
4. Logs enrichis (user-agent, referer, patterns)
5. Évaluer Cloudflare free tier (DDoS protection)

### Long terme (évolutions futures)
1. Migrer vers Hammer + Redis si scaling horizontal
2. Syst�me d'alerting automatique (email, Slack)
3. Interface admin whitelist IPs de confiance
4. Dashboard analytics des attaques
5. Rate limiting Traefik complémentaire

## Références

- Hammer documentation : https://hexdocs.pm/hammer/
- OWASP Rate Limiting : https://owasp.org/www-community/controls/Blocking_Brute_Force_Attacks
- HTTP Retry-After header : https://developer.mozilla.org/en-US/docs/Web/HTTP/Headers/Retry-After
- fail2ban documentation : https://www.fail2ban.org/
- Traefik rate limiting : https://doc.traefik.io/traefik/middlewares/http/ratelimit/
- Fichiers concernés :
  - `lib/portfolio/rate_limiter.ex`
  - `lib/portfolio_web/plugs/rate_limiter_plug.ex`
  - `lib/portfolio/services/auth/magic_link_auth_service.ex`
  - `lib/portfolio_web/controllers/auth_controller.ex`
  - `lib/portfolio_web/live/auth_live/login.ex`
  - `lib/portfolio/application.ex` (Hammer backend config)
