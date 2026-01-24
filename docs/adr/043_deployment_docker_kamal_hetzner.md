# ADR-043: Déploiement Docker, Kamal et Hetzner

Statut: Accepté  
Date: 2025-11-11

## Contexte

Le déploiement d'une application Phoenix en production nécessite plusieurs composants : conteneurisation, orchestration, infrastructure serveur, et gestion DNS/SSL. Le choix de la stack de déploiement impacte directement le coût, la complexité opérationnelle et la maintenabilité du projet.

### Problématique

Le portfolio Photography nécessite un déploiement production avec les contraintes suivantes :

Contraintes techniques :
- Application Phoenix/Elixir à conteneuriser
- PostgreSQL pour persistence
- Stockage fichiers photos (local, voir ADR-010)
- SSL/TLS obligatoire (HTTPS) - voir ADR-050, ADR-052
- DNS multi-domaines (thibaultsan.com, photo.thibaultsan.com, etc.)

**Voir aussi** :
- ADR-010 (Storage Strategy) pour le stockage des photos
- ADR-044 (CDN Strategy) pour Cloudflare et SSL
- ADR-050 (Security Layered Defense) pour la configuration SSL/TLS
- ADR-052 (Security Headers) pour HSTS et headers sécurité

Contraintes opérationnelles :
- Budget très limité (quasiment aucun moyen financier)
- Développeur solo (pas d'équipe DevOps)
- Simplicité : Déploiement en une commande
- Contrôle total sur infrastructure
- Zero-downtime deployments souhaité

Contraintes performance :
- 4 Go RAM disponibles (serveur + DB + app + images)
- CPU suffisant pour traitement images

Sans stratégie de déploiement claire :
- Risque de choisir solution trop coûteuse (Heroku $50+/mois)
- Ou trop complexe (Kubernetes = overkill pour mono-instance)
- Difficile de déployer rapidement et en sécurité

## Options considérées

### Option 1: Heroku / Render / Fly.io (PaaS Managed)

Description:

Utiliser une plateforme PaaS (Platform-as-a-Service) qui gère infrastructure, déploiement et scaling automatiquement.

Plateformes disponibles :
- Heroku : $25-50/mois (hobby/production)
- Render : $25-50/mois
- Fly.io : $10-30/mois (pricing variable)
- Gigalixir : $10-50/mois (spécialisé Elixir)

```bash
# Déploiement Heroku
git push heroku main
# Heroku gère build, deploy, SSL, scaling
```

Avantages :
- Déploiement ultra-simple (git push)
- SSL/DNS géré automatiquement
- Scaling facile (slider horizontal)
- PostgreSQL managée incluse
- Backup automatique
- Support professionnel
- Zero-downtime deployments natif

Inconvénients :
- Coût mensuel élevé ($25-50/mois minimum = $300-600/an)
- Perte de contrôle (infrastructure opaque)
- Vendor lock-in
- Limites ressources (RAM, CPU, stockage)
- Coûts additionnels pour stockage fichiers (S3)
- Over-engineering pour petit projet solo

Effort estimé : Très faible

Risques :
- Coût prohibitif pour budget limité [Probabilité: Très élevée, Impact: Critique]
- Dépendance vendor [Probabilité: Élevée, Impact: Moyen]

### Option 2: VPS Infomaniak / OVH + Deploy Manuel

Description:

Louer un VPS chez Infomaniak ou OVH et déployer manuellement via SSH, scripts shell et systemd.

VPS disponibles :
- Infomaniak VPS : €6-20/mois (Suisse)
- OVH VPS : €6-15/mois (France)
- Hetzner VPS : €4-10/mois (Allemagne)

```bash
# Déploiement manuel
ssh user@server
git pull
mix deps.get
MIX_ENV=prod mix release
systemctl restart portfolio
```

Avantages :
- Coût faible (€6-10/mois)
- Contrôle total
- Pas de vendor lock-in
- Ressources dédiées
- Hébergement européen (RGPD)

Inconvénients :
- Complexité opérationnelle élevée
- Pas d'orchestration (deploy manuel)
- Pas de zero-downtime deployments
- Configuration serveur manuelle (nginx, SSL, firewall)
- Backup manuel
- Monitoring manuel
- Scaling difficile

Effort estimé : Élevé (3-5 jours setup initial)

Risques :
- Erreurs de deploy manuelles [Probabilité: Élevée, Impact: Élevé]
- Downtime lors des déploiements [Probabilité: Très élevée, Impact: Moyen]
- Maintenance complexe [Probabilité: Élevée, Impact: Moyen]

### Option 3: Kubernetes (K8s) sur VPS

Description:

Déployer un cluster Kubernetes mono-nœud sur VPS pour orchestration avancée.

Solutions possibles :
- K3s (lightweight Kubernetes)
- MicroK8s
- Rancher

Avantages :
- Orchestration puissante
- Zero-downtime deployments
- Scaling horizontal facile
- Standard industrie
- Écosystème riche (Helm charts)

Inconvénients :
- Over-engineering massif pour mono-instance
- Complexité extrême (courbe d'apprentissage raide)
- Consommation ressources élevée (K8s = 500 Mo+ RAM)
- Configuration YAML complexe
- Overkill pour projet solo
- Temps setup/maintenance important

Effort estimé : Très élevé (1-2 semaines)

Risques :
- Over-engineering [Probabilité: Très élevée, Impact: Élevé]
- Complexité insurmontable pour solo [Probabilité: Élevée, Impact: Critique]
- Consommation mémoire excessive [Probabilité: Élevée, Impact: Élevé]

### Option 4: Docker + Kamal + Hetzner VPS

Description:

Utiliser Docker pour conteneurisation, Kamal pour orchestration déploiement, et Hetzner VPS comme infrastructure. Kamal est un outil créé par Basecamp pour déployer applications conteneurisées simplement.

Architecture :

```
Local Machine                 Internet                 Hetzner VPS
────────────────             ────────                 ────────────

Developer                  Cloudflare               Docker Host
    ↓                         ↓                          ↓
kamal deploy            DNS + SSL              ┌─────────────────┐
    ↓                      (Full)              │   Kamal Proxy   │
Build Docker                 ↓                 │  (Traefik/SSL)  │
    ↓                        ↓                 └────────┬────────┘
Push Registry          Route Traffic                   ↓
    ↓                        ↓                 ┌─────────────────┐
SSH Deploy            157.180.70.8            │ Portfolio App   │
                                              │  (Phoenix)      │
                                              └────────┬────────┘
                                                       ↓
                                              ┌─────────────────┐
                                              │  PostgreSQL     │
                                              │  (Accessory)    │
                                              └─────────────────┘
                                                       ↓
                                              ┌─────────────────┐
                                              │  Volumes        │
                                              │  - DB data      │
                                              │  - Photos       │
                                              └─────────────────┘
```

Implémentation :

```yaml
# config/deploy.yml
service: portfolio
image: thibaultsan/portfolio

servers:
  web:
    - 157.180.70.8

proxy:
  ssl: true
  hosts:
    - thibaultsan.com
    - photo.thibaultsan.com
    - tech.thibaultsan.com
    - amvcc.thibaultsan.com
  app_port: 4000
  healthcheck:
    interval: 3
    path: /
    timeout: 10

accessories:
  db:
    image: postgres:16-alpine
    host: 157.180.70.8
    port: 5432
    env:
      clear:
        POSTGRES_DB: portfolio_prod
      secret:
        - POSTGRES_USER
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data
    
volumes:
  - "photos:/app/priv/static/uploads"

env:
  clear:
    PHX_SERVER: true
    POOL_SIZE: "10"
    PHX_HOST: "thibaultsan.com"
  secret:
    - SECRET_KEY_BASE
    - DATABASE_URL

# Déploiement
$ kamal deploy
# → Build Docker image
# → Push to registry
# → SSH to server
# → Pull image
# → Start container avec zero-downtime
# → Healthcheck
# → Switch traffic
```

Avantages :
- Coût très faible : Hetzner VPS €4-10/mois (~$5-12/mois)
- Déploiement simple : Une commande `kamal deploy`
- Zero-downtime deployments : Healthcheck + traffic switch automatique
- SSL automatique : Let's Encrypt via Kamal proxy
- Multi-domaines : Support natif plusieurs hosts
- PostgreSQL managé : Accessory Kamal pour DB
- Volumes persistants : Photos et DB data
- Contrôle total : Accès root VPS
- Rollback facile : `kamal rollback`
- Logs centralisés : `kamal app logs`

Inconvénients :
- Kamal moins mature que Kubernetes
- Documentation Kamal limitée (outil récent 2023)
- Nécessite registry Docker (Docker Hub gratuit suffisant)
- Mono-serveur (pas de HA native)

Effort estimé : Faible (1-2 jours setup initial)

Risques :
- Kamal outil récent (moins mature) [Probabilité: Moyenne, Impact: Faible]
- Mono-serveur (SPOF) [Probabilité: Élevée, Impact: Moyen, Acceptable pour petit projet]

## Décision

L'option choisie est: Option 4 - Docker + Kamal + Hetzner VPS

### Justification de la décision

Cette solution offre le meilleur compromis entre coût, simplicité et contrôle pour un projet solo avec budget limité. Cette stack :

1. Coût minimal : €5-10/mois (~$60-120/an) vs $300-600/an PaaS
2. Déploiement simple : `kamal deploy` vs deploy manuel complexe
3. Zero-downtime : Healthcheck + traffic switch automatique
4. Contrôle total : Accès root, pas de vendor lock-in
5. SSL automatique : Let's Encrypt géré par Kamal
6. Pragmatique : Évite over-engineering (Kubernetes)

Le principal compromis accepté est le mono-serveur (SPOF), mais acceptable pour un portfolio personnel sans besoin de haute disponibilité critique.

## Conséquences

### Positives

- Coût très faible : €5-10/mois au lieu de $50+/mois
- Déploiement rapide : 5-10 minutes au lieu de plusieurs heures
- Zero-downtime : Pas d'interruption service lors des déploiements
- SSL automatique : HTTPS géré automatiquement
- Rollback simple : Une commande en cas de problème
- Logs centralisés : Accès facile via `kamal app logs`
- Contrôle total : Accès SSH, configuration libre

### Négatives

- Mono-serveur : SPOF (Single Point of Failure)
- Kamal moins mature : Documentation limitée, communauté plus petite
- Pas de scaling horizontal automatique : Nécessite configuration manuelle

### Neutres

- Hébergement Allemagne (Hetzner) : Conforme RGPD, latence acceptable France/Europe

## Configuration Détaillée

### Stack Complète

Composant | Technologie | Version | Rôle
---|---|---|---
Conteneurisation | Docker | Latest | Isolation application
Orchestration | Kamal | 1.x | Déploiement zero-downtime
Infrastructure | Hetzner VPS | CPX21 (4 Go RAM) | Serveur
Base de données | PostgreSQL | 16-alpine | Persistence
Reverse Proxy | Traefik (Kamal) | Latest | Routing + SSL
DNS | Cloudflare | - | DNS management
SSL | Let's Encrypt | - | Certificats HTTPS
Registry | Docker Hub | - | Stockage images

### Hetzner VPS Choisi

Plan : CPX21  
Spécifications :
- 4 Go RAM
- 2 vCPU AMD
- 80 Go SSD
- 20 To trafic/mois
- Prix : ~€8/mois (~$9/mois)

Justification :
- 4 Go RAM suffisants pour app + DB + images
- 80 Go SSD suffisants pour DB + photos (avec backup externe)
- Datacenter Allemagne (Nuremberg) : Latence < 30ms Europe

Alternatives considérées :
- Infomaniak (Suisse) : €10-15/mois, plus cher
- OVH (France) : €6-10/mois, fiabilité moindre
- DigitalOcean : $12-15/mois, plus cher qu'Hetzner

### Cloudflare Configuration

Mode DNS : DNS only (gris, pas de proxy)  
Raison : Application auto-hébergée gère SSL via Let's Encrypt

Configuration SSL/TLS :
- Encryption Mode : Full
- Justification : Chiffrement Cloudflare → Serveur via Let's Encrypt

Si activation proxy Cloudflare futur (orange) :
- Avantage : CDN gratuit, cache statique, DDoS protection
- Inconvénient : SSL géré par Cloudflare (certificat Cloudflare-Serveur)
- Configuration requise : Full (strict) avec certificat Origin

Note : Le proxy orange Cloudflare est prévu pour ADR-044 (CDN Strategy) si nécessaire.

### Dockerfile

```dockerfile
FROM ubuntu:noble

# Install dependencies
RUN apt-get update && apt-get install -y \
    bash \
    libstdc++6 \
    openssl \
    libncurses6 \
    locales \
    ca-certificates \
    libvips42 \        # Traitement images (ADR-011)
    libvips-tools \
    exiftool           # Métadonnées EXIF

# Copy Phoenix release
COPY --chown=nobody:root ./_build/prod/rel/portfolio/ ./

# Expose port
EXPOSE 4000

# Run as unprivileged user
USER nobody

# Start Phoenix
CMD ["/app/bin/portfolio", "start"]
```

Justifications :
- Base Ubuntu Noble (24.04 LTS) : Stabilité, support long terme
- Libvips : Traitement images performant (cf ADR-011)
- User nobody : Sécurité (pas root)
- Release Phoenix : Build optimisé production

### Kamal Configuration

```yaml
# config/deploy.yml
service: portfolio
image: thibaultsan/portfolio

servers:
  web:
    - 157.180.70.8

proxy:
  ssl: true                    # Let's Encrypt automatique
  hosts:
    - thibaultsan.com
    - photo.thibaultsan.com
    - tech.thibaultsan.com
    - amvcc.thibaultsan.com
  app_port: 4000
  healthcheck:
    interval: 3                # Check santé toutes les 3s
    path: /                    # Endpoint healthcheck
    timeout: 10                # Timeout 10s

accessories:
  db:
    image: postgres:16-alpine
    host: 157.180.70.8
    port: 5432
    env:
      clear:
        POSTGRES_DB: portfolio_prod
      secret:
        - POSTGRES_USER         # Dans .kamal/secrets
        - POSTGRES_PASSWORD
    directories:
      - data:/var/lib/postgresql/data  # Volume persistant
    healthcheck:
      cmd: pg_isready -U postgres
      interval: 10
      timeout: 5

volumes:
  - "photos:/app/priv/static/uploads"  # Stockage photos

env:
  clear:
    PHX_SERVER: true
    POOL_SIZE: "10"
    PHX_HOST: "thibaultsan.com"
  secret:
    - SECRET_KEY_BASE
    - DATABASE_URL

ssh:
  user: amvcc                  # User SSH non-root

aliases:
  iex: app exec --interactive --reuse "./bin/portfolio remote"
  ssh: app exec --interactive --reuse "bash"
  logs: app logs -f
```

### Secrets Management

Fichier : `.kamal/secrets` (jamais commité)

```bash
# .kamal/secrets
KAMAL_REGISTRY_USERNAME=thibaultsan
KAMAL_REGISTRY_PASSWORD=<docker_hub_token>

SECRET_KEY_BASE=<phoenix_secret>
DATABASE_URL=postgresql://user:pass@db:5432/portfolio_prod

POSTGRES_USER=portfolio
POSTGRES_PASSWORD=<db_password>
```

Génération secrets :

```bash
# SECRET_KEY_BASE
mix phx.gen.secret

# PostgreSQL password
openssl rand -base64 32
```

Sécurité :
- `.kamal/secrets` dans `.gitignore`
- Permissions 600 (lecture user uniquement)
- Rotation secrets tous les 6 mois recommandée

## Workflow Déploiement

### Déploiement Initial

```bash
# 1. Setup serveur Hetzner
kamal server bootstrap

# 2. Setup Docker sur serveur
kamal setup

# 3. Déploiement initial
kamal deploy
```

Étapes automatiques :
1. Build image Docker localement
2. Push vers Docker Hub
3. SSH vers serveur Hetzner
4. Pull image depuis registry
5. Start PostgreSQL (accessory)
6. Start application container
7. Healthcheck (attente application ready)
8. Switch traffic vers nouvelle version
9. Stop ancienne version

Durée : ~5-10 minutes

### Déploiements Suivants

```bash
# Deploy nouvelle version (zero-downtime)
kamal deploy

# Rollback si problème
kamal rollback

# Voir logs
kamal app logs -f

# Accès console IEx
kamal iex

# Accès SSH
kamal ssh
```

### Zero-Downtime Deployment

Séquence Kamal :

```
1. Ancienne version running (portfolio-web-v1)
2. Build nouvelle image (portfolio-web-v2)
3. Start nouvelle version en parallèle
4. Healthcheck nouvelle version (GET /)
5. Si healthcheck OK :
   - Switch Traefik vers nouvelle version
   - Stop ancienne version après drain
6. Si healthcheck FAIL :
   - Stop nouvelle version
   - Keep ancienne version
   - Rollback automatique
```

Downtime : 0 seconde (si healthcheck pass)

### Healthcheck Endpoint

```elixir
# lib/portfolio_web/router.ex
scope "/", PortfolioWeb do
  pipe_through :browser
  
  get "/", PageController, :home
  # Kamal healthcheck utilise GET / par défaut
end
```

Healthcheck vérifie :
- Application répond HTTP 200
- Phoenix démarré complètement
- DB connectée (pool Ecto)

Si healthcheck échoue après 10 secondes :
- Nouvelle version arrêtée
- Ancienne version conservée
- Deploy échoue avec erreur

## Plan d'action

### Phase 1: Setup Infrastructure (Priorité: CRITIQUE si pas déjà fait)

Tâches :
1. Créer compte Hetzner
2. Provisionner VPS CPX21 (4 Go RAM)
3. Configurer firewall Hetzner :
   - Port 22 (SSH)
   - Port 80 (HTTP → redirect HTTPS)
   - Port 443 (HTTPS)
   - Port 5432 (PostgreSQL, localhost only)
4. Créer user SSH non-root (`amvcc`)
5. Configurer clés SSH

Critères de succès :
- VPS accessible via SSH
- Firewall configuré
- User non-root créé

Estimation : 1 heure

### Phase 2: Configuration Kamal (Priorité: CRITIQUE si pas déjà fait)

Tâches :
1. Créer `config/deploy.yml`
2. Configurer `.kamal/secrets`
3. Setup Docker Hub registry
4. Configurer accessory PostgreSQL
5. Configurer volumes persistants

Critères de succès :
- `config/deploy.yml` valide
- Secrets configurés (pas commités)
- Registry accessible

Estimation : 2 heures

### Phase 3: Premier Déploiement (Priorité: CRITIQUE si pas déjà fait)

Tâches :
1. `kamal setup` (install Docker sur serveur)
2. `kamal deploy` (premier déploiement)
3. Vérifier application accessible
4. Configurer DNS Cloudflare
5. Vérifier SSL Let's Encrypt

Critères de succès :
- Application accessible HTTPS
- Tous domaines résolus
- SSL valide

Estimation : 3 heures

### Phase 4: Monitoring Déploiements (Priorité: MOYENNE)

Tâches :
1. Documenter procédure déploiement
2. Créer checklist pre-deploy
3. Configurer alerting si deploy échoue (Newsletter)
4. Documenter procédure rollback

Critères de succès :
- Documentation complète
- Checklist accessible

Estimation : 1 jour

### Phase 5: Backup Strategy (Priorité: HAUTE)

Note : À documenter dans ADR dédié (en cours)

Tâches :
1. Backup DB PostgreSQL automatique
2. Backup photos uploadées
3. Test restauration backup
4. Schedule backup quotidien

Déclencheur : Voir ADR backup (à créer)

## Alternatives Futures

### Si Besoin Haute Disponibilité

Si le projet nécessite 99.9% uptime :

Option : Multi-serveurs avec load balancer
- 2+ VPS Hetzner derrière Hetzner Load Balancer (€5/mois)
- PostgreSQL externe managée (Supabase, Neon)
- Stockage photos S3-compatible (Cloudflare R2)

Déclencheur : SLA client contractuel OU trafic critique business

### Si Besoin Scaling Horizontal

Si le projet dépasse capacité mono-serveur :

Option : Scale horizontal Kamal
- Ajouter serveurs dans `config/deploy.yml`
- Kamal gère déploiement multi-serveurs
- Load balancing via Hetzner ou Cloudflare

Déclencheur : CPU/RAM > 80% constant OU trafic > 100k req/jour

## Références

- [Kamal Documentation](https://kamal-deploy.org/)
- [Kamal GitHub](https://github.com/basecamp/kamal)
- [Hetzner Cloud](https://www.hetzner.com/cloud)
- [Cloudflare DNS](https://www.cloudflare.com/dns/)
- [Let's Encrypt](https://letsencrypt.org/)
- Code source :
  - `config/deploy.yml` : Configuration Kamal
  - `Dockerfile` : Image Docker
  - `.kamal/secrets` : Secrets (non commité)

## Notes

### Pourquoi Hetzner vs Alternatives ?

Hetzner vs Concurrents :

Critère | Hetzner | DigitalOcean | OVH | Infomaniak
---|---|---|---|---
Prix 4 Go RAM | €8/mois | $12/mois | €6/mois | €12/mois
Localisation | Allemagne | USA/EU | France | Suisse
Fiabilité | Excellente | Très bonne | Moyenne | Bonne
Support | Email | Ticket | Ticket | Excellent
Écosystème | Bon | Excellent | Moyen | Petit

Verdict : Hetzner meilleur rapport qualité/prix/fiabilité.

### Kamal vs Capistrano

Kamal (Ruby on Rails) vs Capistrano (ancien outil Basecamp) :

Différence principale :
- Capistrano : Deploy code sur serveur, build sur serveur
- Kamal : Build local, deploy Docker container

Avantages Kamal :
- Conteneurisation (isolation, reproducibilité)
- Zero-downtime natif
- Moins de dépendances serveur

### Docker Hub vs Registry Privé

Docker Hub gratuit suffit car :
- Images publiques acceptables (pas de secrets dans image)
- Limite : 200 pulls/6h (largement suffisant)
- Alternative : GitHub Container Registry (gratuit aussi)

Registry privé (Harbor, etc.) uniquement si :
- Besoin de garder images privées
- Volume pulls très élevé

### Mono-serveur : Acceptable ?

SPOF (Single Point of Failure) acceptable pour :
- Portfolio personnel (pas de SLA contractuel)
- Trafic faible/moyen
- Budget limité

Non acceptable pour :
- Applications critiques business
- E-commerce avec transactions
- Services avec SLA 99.9%+

Mitigation SPOF :
- Backup réguliers (restauration rapide)
- Monitoring uptime (détection rapide)
- Documentation procédure restauration

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
