# ADR-046 : Environnement Docker Preproduction

Statut: Accepté
Date: 2025-11-15

## Contexte

Le projet Portfolio utilise Kamal pour le déploiement en production sur un VPS Hetzner. Actuellement, il n'existe que deux environnements :

1. **Development** : Machine locale avec `mix phx.server`
2. **Production** : VPS Hetzner avec Docker + Kamal

### Problèmes identifiés

**Gap entre Development et Production :**

1. **Différences d'environnement**
   - Dev : Pas de Docker (Elixir natif)
   - Prod : Docker + Kamal + PostgreSQL conteneurisé
   - Résultat : "Ça marche en dev mais pas en prod"

2. **Tests incomplets**
   - Migrations non testées en environnement Docker
   - Variables d'environnement différentes (dev vs prod)
   - Configuration runtime.exs non vérifiée avant déploiement

3. **Déploiements risqués**
   - Pas de validation avant push en production
   - Découverte de bugs uniquement en prod
   - Rollback coûteux si erreur

4. **Difficultés de debugging**
   - Impossible de reproduire bugs production localement
   - Logs Docker différents des logs dev
   - Configuration réseau différente (proxy, ports)

### Besoins

1. **Environnement isomorphe** : Preprod identique à prod (Docker, config, volumes)
2. **Validation pré-déploiement** : Tester migrations, config, builds avant prod
3. **Tests d'intégration** : Valider stack complète (app + DB + volumes Docker)
4. **Debugging facilité** : Reproduire conditions production localement
5. **Formation équipe** : Environnement safe pour apprendre Kamal/Docker

### Contraintes

- Pas de serveur preprod dédié (budget limité)
- Environnement preprod local (machine développeur)
- Compatible avec stack existante (Docker, Kamal, PostgreSQL)
- Simple à lancer (une commande)
- Isolation totale du dev (pas d'interférence)

---

## Options Considérées

### Option 1 : Pas d'environnement preprod

Continuer avec Dev local + Production directe.

**Avantages :**
- Aucun effort supplémentaire
- Pas de maintenance

**Inconvénients :**
- ❌ Gap dev/prod persiste
- ❌ Bugs découverts en production
- ❌ Déploiements risqués
- ❌ Impossible de tester migrations Docker
- ❌ Pas de validation pré-déploiement

**Rejeté** : Risque inacceptable pour production.

### Option 2 : VPS Preprod dédié (Hetzner)

Louer un second VPS pour la preprod.

**Coût :**
- VPS CX11 (2 vCPU, 4GB RAM) : 4,51€/mois
- Total annuel : ~55€

**Avantages :**
- Environnement public accessible (démos clients)
- Vraie simulation production

**Inconvénients :**
- ❌ Coût récurrent (+100% budget infra)
- ❌ Maintenance double (VPS preprod + prod)
- ❌ Gestion DNS supplémentaire
- ❌ Configuration Kamal dupliquée
- ❌ Over-engineering pour portfolio personnel

**Rejeté** : Budget disproportionné pour le besoin.

### Option 3 : Docker Compose local en preprod ⭐

Créer un environnement preprod local avec Docker Compose, isomorphe à production.

**Architecture :**

```
┌────────────────────────────────────────────────────────┐
│ Machine Développeur                                    │
│                                                         │
│  Development (Elixir natif)                            │
│  ├── mix phx.server                                    │
│  ├── PostgreSQL local (dev)                            │
│  └── Port 4000                                         │
│                                                         │
│  Preproduction (Docker Compose)                        │
│  ├── app_preprod (Docker)                              │
│  │   ├── Image: portfolio:latest                       │
│  │   ├── Port 4001                                     │
│  │   └── Volumes: storage_preprod                      │
│  ├── db_preprod (Docker)                               │
│  │   ├── Image: postgres:16                            │
│  │   ├── Port 5433                                     │
│  │   └── Volume: postgres_preprod                      │
│  └── docker-compose.preprod.yml                        │
│                                                         │
└────────────────────────────────────────────────────────┘
                        │
                        │ Configuration identique
                        ▼
┌────────────────────────────────────────────────────────┐
│ VPS Hetzner (Production)                               │
│                                                         │
│  ├── app_production (Docker + Kamal)                   │
│  ├── db_production (PostgreSQL Docker)                 │
│  └── Volumes: storage_production                       │
└────────────────────────────────────────────────────────┘
```

**Principes :**

1. **Isolation totale** : Preprod ne touche pas Dev
   - Ports différents (4000 dev, 4001 preprod)
   - Base de données séparée (5432 dev, 5433 preprod)
   - Volumes Docker dédiés

2. **Configuration identique à prod**
   - Même Dockerfile
   - Même variables d'environnement (structure)
   - Même versions PostgreSQL, Elixir, etc.

3. **Simple à lancer**
   ```bash
   docker-compose -f docker-compose.preprod.yml up
   ```

4. **Jetable et reproductible**
   ```bash
   # Reset complet
   docker-compose -f docker-compose.preprod.yml down -v
   docker-compose -f docker-compose.preprod.yml up --build
   ```

**Avantages :**
- ✅ Gratuit (local)
- ✅ Environnement isomorphe à production
- ✅ Validation migrations avant prod
- ✅ Tests stack complète (app + DB + volumes)
- ✅ Debugging conditions prod localement
- ✅ Isolation totale dev/preprod
- ✅ Reproductible (reset complet en 2 minutes)
- ✅ Pas de maintenance serveur

**Inconvénients :**
- Docker Compose à maintenir (mais simple)
- Pas d'accès public (local uniquement)
- Consomme ressources machine dev (mais temporaire)

**Effort estimé :** Faible (2-3 heures setup)

---

## Décision

L'option choisie est : **Option 3 - Docker Compose local en preprod**

### Justification

**Critères de décision :**

1. **Coût** : Gratuit vs 55€/an pour VPS preprod
2. **Isomorphie** : Configuration identique à production (Docker, PostgreSQL, volumes)
3. **Simplicité** : Une commande pour lancer/arrêter
4. **Isolation** : Preprod séparé de dev (ports, DB, volumes)
5. **Validation** : Tester migrations, config, builds avant prod
6. **Pragmatisme** : Solution adaptée au besoin (portfolio personnel)

**Cas d'usage principaux :**

1. **Avant déploiement** : Valider migrations + build + config
2. **Debugging prod** : Reproduire bug en environnement Docker local
3. **Tests d'intégration** : Valider stack complète
4. **Formation** : Apprendre Docker/Kamal sans risquer prod

---

## Implémentation

### Structure des fichiers

```
portfolio/
├── Dockerfile                          # Build production (existant)
├── docker-compose.preprod.yml         # Nouveau fichier preprod
├── .env.preprod                       # Variables environnement preprod
├── config/
│   ├── runtime.exs                    # Config runtime (existant)
│   └── deploy.yml                     # Kamal production (existant)
└── scripts/
    ├── preprod_start.sh               # Helper démarrage preprod
    ├── preprod_stop.sh                # Helper arrêt preprod
    └── preprod_reset.sh               # Helper reset complet
```

### docker-compose.preprod.yml

```yaml
version: "3.9"

services:
  db:
    image: postgres:16-alpine
    container_name: portfolio_db_preprod
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: portfolio_preprod
    ports:
      - "5433:5432"  # Port externe différent de dev (5432)
    volumes:
      - postgres_preprod:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    networks:
      - preprod_network

  app:
    build:
      context: .
      dockerfile: Dockerfile
      args:
        MIX_ENV: prod
    container_name: portfolio_app_preprod
    depends_on:
      db:
        condition: service_healthy
    environment:
      # Database
      DATABASE_URL: "ecto://postgres:postgres@db:5432/portfolio_preprod"
      
      # App
      SECRET_KEY_BASE: "preprod_secret_key_base_change_me_in_production"
      PHX_HOST: "localhost"
      PORT: 4000
      
      # Configuration
      POOL_SIZE: 10
      
      # Feature flags
      ENABLE_RATE_LIMITING: "true"
      SESSION_EXPIRATION_SECONDS: 7200
      
    ports:
      - "4001:4000"  # Port externe différent de dev (4000)
    volumes:
      - storage_preprod:/app/storage
    networks:
      - preprod_network
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:4000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s

volumes:
  postgres_preprod:
    driver: local
  storage_preprod:
    driver: local

networks:
  preprod_network:
    driver: bridge
```

### .env.preprod

```bash
# Database
DATABASE_URL=ecto://postgres:postgres@localhost:5433/portfolio_preprod

# App
SECRET_KEY_BASE=preprod_secret_key_base_change_me_in_production_this_is_only_for_local_testing
PHX_HOST=localhost
PORT=4001

# Pool
POOL_SIZE=10

# Feature flags (identiques à prod pour validation)
ENABLE_RATE_LIMITING=true
SESSION_EXPIRATION_SECONDS=7200

# Oban (désactivé en preprod local, optionnel)
# OBAN_ENABLED=false
```

### scripts/preprod_start.sh

```bash
#!/bin/bash

set -euo pipefail

echo "🚀 Démarrage de l'environnement preprod..."

# Vérifier que Docker est actif
if ! docker info > /dev/null 2>&1; then
    echo "❌ Docker n'est pas démarré. Lancez Docker Desktop et réessayez."
    exit 1
fi

# Build et démarrage
echo "📦 Build de l'image Docker..."
docker-compose -f docker-compose.preprod.yml build

echo "🔧 Démarrage des services..."
docker-compose -f docker-compose.preprod.yml up -d

echo "⏳ Attente du démarrage de la base de données..."
sleep 5

echo "🗃️  Création de la base de données..."
docker-compose -f docker-compose.preprod.yml exec app bin/portfolio eval "Portfolio.Release.migrate()"

echo "✅ Preprod démarré avec succès!"
echo ""
echo "📍 Application: http://localhost:4001"
echo "📍 Base de données: localhost:5433"
echo ""
echo "📋 Commandes utiles:"
echo "  - Logs: docker-compose -f docker-compose.preprod.yml logs -f app"
echo "  - Shell: docker-compose -f docker-compose.preprod.yml exec app sh"
echo "  - Stop: ./scripts/preprod_stop.sh"
echo "  - Reset: ./scripts/preprod_reset.sh"
```

### scripts/preprod_stop.sh

```bash
#!/bin/bash

set -euo pipefail

echo "🛑 Arrêt de l'environnement preprod..."

docker-compose -f docker-compose.preprod.yml down

echo "✅ Preprod arrêté"
```

### scripts/preprod_reset.sh

```bash
#!/bin/bash

set -euo pipefail

echo "🗑️  Reset complet de l'environnement preprod..."
echo "⚠️  ATTENTION: Cela va supprimer TOUTES les données preprod (DB + volumes)"
read -p "Continuer? (yes/no): " confirm

if [ "$confirm" != "yes" ]; then
    echo "Reset annulé"
    exit 0
fi

# Arrêt et suppression complète (volumes inclus)
docker-compose -f docker-compose.preprod.yml down -v

echo "🔄 Redémarrage de preprod..."
./scripts/preprod_start.sh

echo "✅ Reset terminé"
```

### Dockerfile (si besoin d'ajustement)

Le `Dockerfile` existant doit fonctionner tel quel. Vérifier qu'il contient bien :

```dockerfile
# Healthcheck endpoint (si pas déjà présent)
HEALTHCHECK --interval=30s --timeout=10s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:${PORT:-4000}/health || exit 1
```

### Endpoint healthcheck (à ajouter si manquant)

```elixir
# lib/portfolio_web/router.ex
scope "/", PortfolioWeb do
  pipe_through :browser
  
  # Healthcheck endpoint (pas d'authentification)
  get "/health", HealthController, :index
end

# lib/portfolio_web/controllers/health_controller.ex
defmodule PortfolioWeb.HealthController do
  use PortfolioWeb, :controller

  def index(conn, _params) do
    # Vérifier que la DB est accessible
    case Ecto.Adapters.SQL.query(Portfolio.Repo, "SELECT 1", []) do
      {:ok, _} ->
        json(conn, %{status: "ok", timestamp: DateTime.utc_now()})
      
      {:error, _} ->
        conn
        |> put_status(:service_unavailable)
        |> json(%{status: "error", message: "Database unavailable"})
    end
  end
end
```

---

## Utilisation

### Workflow de validation pré-déploiement

**Avant chaque déploiement production :**

```bash
# 1. Démarrer preprod
./scripts/preprod_start.sh

# 2. Vérifier que l'app démarre correctement
curl http://localhost:4001/health

# 3. Tester les migrations
docker-compose -f docker-compose.preprod.yml exec app bin/portfolio eval "Portfolio.Release.migrate()"

# 4. Tester l'application manuellement
open http://localhost:4001

# 5. Vérifier les logs (pas d'erreurs)
docker-compose -f docker-compose.preprod.yml logs -f app

# 6. Si tout est OK, déployer en prod
kamal deploy

# 7. Arrêter preprod
./scripts/preprod_stop.sh
```

### Workflow de debugging production

**Reproduire un bug prod localement :**

```bash
# 1. Reset preprod pour partir de zéro
./scripts/preprod_reset.sh

# 2. Charger un backup production (optionnel)
# Permet de reproduire l'état exact de la prod
docker-compose -f docker-compose.preprod.yml exec db psql -U postgres -d portfolio_preprod < /path/to/prod_backup.sql

# 3. Reproduire le bug
# Accéder à l'app via http://localhost:4001

# 4. Investiguer avec logs
docker-compose -f docker-compose.preprod.yml logs -f app

# 5. Accès shell si nécessaire
docker-compose -f docker-compose.preprod.yml exec app sh
```

### Workflow de test de migration

**Tester une nouvelle migration :**

```bash
# 1. Créer la migration en dev
mix ecto.gen.migration add_new_feature

# 2. Démarrer preprod
./scripts/preprod_start.sh

# 3. Appliquer la migration
docker-compose -f docker-compose.preprod.yml exec app bin/portfolio eval "Portfolio.Release.migrate()"

# 4. Vérifier que la migration s'applique sans erreur
docker-compose -f docker-compose.preprod.yml logs app

# 5. Tester l'application avec la nouvelle migration
open http://localhost:4001

# 6. Si OK, commit et déployer en prod
git add .
git commit -m "feat: add new feature with migration"
git push
kamal deploy
```

---

## Différences Dev / Preprod / Prod

| Aspect | Development | Preproduction | Production |
|--------|------------|---------------|------------|
| **Environnement** | Elixir natif | Docker Compose | Docker + Kamal |
| **Port** | 4000 | 4001 | 80/443 |
| **Base de données** | PostgreSQL local (5432) | PostgreSQL Docker (5433) | PostgreSQL Docker |
| **Volumes** | Local filesystem | Docker volumes | Docker volumes |
| **Configuration** | config/dev.exs | config/runtime.exs + .env.preprod | config/runtime.exs + ENV |
| **Hot reload** | Oui (mix phx.server) | Non (Docker) | Non (Docker) |
| **Build** | Mix (dev) | Docker (prod build) | Docker (prod build) |
| **Isolation** | Aucune | Complète (Docker) | Complète (Docker) |
| **Reset** | - | `./scripts/preprod_reset.sh` | Backup/Restore |

---

## Tests Automatisés (CI/CD)

**Optionnel (futur) :** Intégrer preprod dans CI/CD GitHub Actions.

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Start preprod environment
        run: ./scripts/preprod_start.sh
      
      - name: Wait for app to be ready
        run: |
          for i in {1..30}; do
            curl -f http://localhost:4001/health && break || sleep 2
          done
      
      - name: Run integration tests
        run: docker-compose -f docker-compose.preprod.yml exec app mix test
      
      - name: Stop preprod
        run: ./scripts/preprod_stop.sh
```

---

## Limitations et Contraintes

### Limitations connues

1. **Pas d'accès public** : Preprod local uniquement (pas de démos clients)
2. **Ressources machine** : Consomme CPU/RAM (mais temporaire)
3. **Pas de vraie simulation réseau** : Latence, proxy, CDN simulés

### Quand NE PAS utiliser preprod local

- **Démos clients** : Utiliser staging sur VPS dédié si besoin
- **Tests de charge** : Performance différente de prod (machine locale)
- **Tests multi-utilisateurs** : Difficile de simuler concurrence

### Solutions alternatives pour ces cas

**Si besoin d'un environnement public :**
- Deploy preprod sur VPS Hetzner temporaire (4,51€/mois)
- Utiliser ngrok pour exposer preprod local (gratuit tier)
- Deploy sur Fly.io free tier (limité mais gratuit)

---

## Conséquences

### Positives

- ✅ Validation pré-déploiement (migrations, config, builds)
- ✅ Environnement isomorphe à production (Docker, PostgreSQL, volumes)
- ✅ Debugging facilité (reproduction bugs prod localement)
- ✅ Tests d'intégration stack complète
- ✅ Isolation totale dev/preprod (ports, DB, volumes différents)
- ✅ Reproductible (reset complet en 2 minutes)
- ✅ Gratuit (local, pas de serveur externe)
- ✅ Formation équipe (safe pour apprendre Docker/Kamal)
- ✅ Réduction drastique des bugs en production

### Négatives

- Docker Compose à maintenir (mais fichier simple)
- Consommation ressources machine dev (mais temporaire)
- Pas d'accès public (mais suffisant pour validation)

### Neutres

- Workflow supplémentaire pré-déploiement (mais rapide : 2-3 min)
- Courbe d'apprentissage Docker Compose (mais simple)

---

## Évolutions Futures

### Court terme

1. ✅ docker-compose.preprod.yml créé et testé
2. ✅ Scripts helpers (start/stop/reset)
3. ✅ Documentation workflow validation

### Moyen terme

1. **CI/CD intégration** : Tests automatisés preprod dans GitHub Actions
2. **Seed data** : Script pour peupler preprod avec données de test
3. **Profiling** : Outils de profiling performance en preprod

### Long terme

1. **Staging VPS** : Si besoin de démos clients publiques
2. **Multi-environment** : Preprod + Staging + Production
3. **Blue/Green deployment** : Déploiement sans downtime

---

## Checklist de Mise en Place

- [ ] docker-compose.preprod.yml créé
- [ ] .env.preprod configuré
- [ ] Scripts helpers créés (start/stop/reset)
- [ ] Healthcheck endpoint implémenté (/health)
- [ ] Test démarrage preprod réussi
- [ ] Test migration en preprod réussi
- [ ] Test accès app http://localhost:4001 réussi
- [ ] Test reset preprod réussi
- [ ] Documentation workflow validée
- [ ] Équipe formée à l'utilisation preprod

---

## Références

- ADR-043 : Deployment Docker Kamal Hetzner (production)
- ADR-004 : PostgreSQL Database Choice (base de données)
- ADR-041 : Oban Background Jobs (workers asynchrones)

**Fichiers concernés :**
- `docker-compose.preprod.yml` (configuration Docker Compose)
- `.env.preprod` (variables environnement preprod)
- `scripts/preprod_start.sh` (helper démarrage)
- `scripts/preprod_stop.sh` (helper arrêt)
- `scripts/preprod_reset.sh` (helper reset)
- `lib/portfolio_web/controllers/health_controller.ex` (healthcheck)
- `lib/portfolio_web/router.ex` (route healthcheck)

**Documentation opérationnelle :**
- `docs/operations/preprod_usage.md` (à créer - guide utilisation détaillé)
- `docs/operations/debugging_production.md` (à créer - guide debugging avec preprod)
