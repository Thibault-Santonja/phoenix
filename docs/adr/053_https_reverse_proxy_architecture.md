# ADR-053: Architecture HTTPS et Reverse Proxy

Statut: Accepte  
Date: 2025-11-28

## Contexte

L'application Portfolio utilise une architecture de deploiement avec terminaison SSL au niveau du reverse proxy plutot qu'au niveau de l'application Phoenix. Cette decision architecturale impacte la configuration de securite et necessite une documentation claire.

### Problematique

Sobelow signale "HTTPS Not Enabled" dans `prod.exs` car Phoenix n'est pas configure pour servir HTTPS directement. Cependant, l'application est bien servie en HTTPS en production grace a l'architecture suivante.

## Architecture de Deploiement

### Schema Global

```
Internet                    Hetzner VPS (157.180.70.8)
────────                    ──────────────────────────

  Client                          Docker Host
    │                                  │
    │ HTTPS (443)                      │
    ▼                                  ▼
┌─────────────────┐           ┌─────────────────┐
│   Cloudflare    │           │   Kamal Proxy   │
│   (DNS + CDN)   │           │   (Traefik)     │
│                 │           │                 │
│ SSL: Full Mode  │──HTTPS───▶│ Let's Encrypt   │
│ Cert: Cloudflare│    443    │ Auto SSL        │
└─────────────────┘           └────────┬────────┘
                                       │
                                       │ HTTP (4000)
                                       ▼
                              ┌─────────────────┐
                              │ Portfolio App   │
                              │ (Phoenix/Bandit)│
                              │                 │
                              │ Port: 4000      │
                              │ Protocol: HTTP  │
                              └────────┬────────┘
                                       │
                                       ▼
                              ┌─────────────────┐
                              │  PostgreSQL     │
                              │  (Accessory)    │
                              └─────────────────┘
```

### Flux de Requete

1. **Client → Cloudflare** : HTTPS (TLS 1.3, certificat Cloudflare)
2. **Cloudflare → Traefik** : HTTPS (TLS 1.2+, certificat Let's Encrypt)
3. **Traefik → Phoenix** : HTTP (reseau Docker interne, port 4000)

### Configuration Actuelle

#### Kamal Proxy (config/deploy.yml)

```yaml
proxy:
  ssl: true
  hosts:
    - thibaultsan.com
    - amvcc.thibaultsan.com
    - photo.thibaultsan.com
    - tech.thibaultsan.com
  app_port: 4000
  healthcheck:
    interval: 30
    path: /health
    timeout: 3
```

#### Cloudflare SSL/TLS

- **Mode** : Full (strict recommande si certificat origine valide)
- **Certificat Edge** : Cloudflare Universal SSL
- **Certificat Origine** : Let's Encrypt (via Traefik)

#### Phoenix Endpoint (runtime.exs)

```elixir
config :portfolio, PortfolioWeb.Endpoint,
  url: [host: host, port: 443, scheme: "https"],
  http: [
    ip: {0, 0, 0, 0, 0, 0, 0, 0},
    port: port  # 4000
  ]
```

## Decision

L'option choisie est : **Terminaison SSL au niveau du reverse proxy (Traefik/Cloudflare)**

### Justification

1. **Simplicite operationnelle** : Traefik gere automatiquement les certificats Let's Encrypt (renouvellement, ACME challenge)

2. **Performance** : Terminaison SSL une seule fois (pas de double chiffrement inutile)

3. **Securite reseau interne** : Le traffic HTTP entre Traefik et Phoenix reste dans le reseau Docker isole

4. **Standard industriel** : Architecture commune pour les deployments containerises

5. **Cout zero** : Let's Encrypt gratuit, pas de certificat commercial necessaire

## Configuration Securite Compensatoire

Puisque Phoenix ne gere pas HTTPS directement, les mesures suivantes compensent :

### 1. HSTS Header (endpoint.ex)

```elixir
|> put_resp_header(
  "strict-transport-security",
  "max-age=31536000; includeSubDomains"
)
```

Force les navigateurs a utiliser HTTPS pour toutes les requetes futures.

### 2. Secure Cookies (endpoint.ex)

```elixir
@session_options [
  secure: Application.compile_env!(:portfolio, :env) == :prod,
  same_site: "Lax",
  http_only: true
]
```

Cookies transmis uniquement via HTTPS en production.

### 3. URL Generation (runtime.exs)

```elixir
url: [host: host, port: 443, scheme: "https"]
```

Phoenix genere des URLs HTTPS meme si le serveur ecoute en HTTP.

### 4. Check Origin (runtime.exs)

```elixir
check_origin: [
  "https://#{host}",
  "https://amvcc.#{host}",
  "https://photo.#{host}",
  "https://tech.#{host}"
]
```

LiveView accepte uniquement les WebSocket depuis origines HTTPS.

### 5. CSP avec upgrade-insecure-requests

```elixir
"upgrade-insecure-requests;"
```

Force le navigateur a upgrader les requetes HTTP en HTTPS.

## Verification SSL

### Tests Manuels

```bash
# Verifier certificat Let's Encrypt
openssl s_client -connect thibaultsan.com:443 -servername thibaultsan.com

# Verifier HSTS
curl -I https://thibaultsan.com | grep -i strict

# Verifier redirection HTTP → HTTPS
curl -I http://thibaultsan.com
# Attendu: 301 → https://thibaultsan.com
```

### Outils de Validation

| Outil | URL | Score Attendu |
|-------|-----|---------------|
| SSL Labs | ssllabs.com/ssltest | A ou A+ |
| Mozilla Observatory | observatory.mozilla.org | B+ ou A |
| Security Headers | securityheaders.com | A |

## Sobelow : Explication du Warning

Sobelow signale :

```
Config.HTTPS: HTTPS Not Enabled - High Confidence
File: config/prod.exs
```

Ce warning est un **faux positif dans notre architecture** car :

1. Sobelow cherche `https: [...]` dans la config Phoenix
2. Notre HTTPS est gere par Traefik, pas Phoenix
3. L'application est effectivement servie en HTTPS

### Resolution

Ajouter un commentaire explicatif dans `prod.exs` :

```elixir
# Note: HTTPS is handled by Traefik reverse proxy (Kamal deployment).
# Phoenix serves HTTP on port 4000, Traefik terminates SSL on 443.
# See ADR-053 for architecture details.
```

Ou configurer `.sobelow-conf` pour ignorer :

```json
{
  "ignore": [
    {"Config.HTTPS": {"file": "config/prod.exs"}}
  ]
}
```

## Consequences

### Positives

- Gestion SSL automatisee (Let's Encrypt + Traefik)
- Pas de configuration certificat dans Phoenix
- Renouvellement automatique des certificats
- Performance optimale (une seule terminaison)
- Compatible avec Cloudflare CDN

### Negatives

- Warning Sobelow a documenter/ignorer
- Necessite comprehension de l'architecture multi-couches
- Debug SSL plus complexe (plusieurs composants)

### Neutres

- Standard pour deployments Docker/Kubernetes
- Meme approche que la majorite des PaaS (Heroku, Render, etc.)

## Références

- [Kamal Proxy SSL](https://kamal-deploy.org/docs/configuration/proxy/)
- [Traefik Let's Encrypt](https://doc.traefik.io/traefik/https/acme/)
- [Cloudflare SSL Modes](https://developers.cloudflare.com/ssl/origin-configuration/ssl-modes/)
- ADR-043: Deploiement Docker, Kamal et Hetzner
- ADR-052: Security Headers Strategy

---

Date de creation: 2025-11-28  
Derniere revision: 2025-11-28
