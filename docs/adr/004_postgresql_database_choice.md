# ADR-004: Choix de PostgreSQL comme Base de Données

Statut: Accepté
Date: 2025-06

## Contexte

Au démarrage du projet Portfolio, le choix de la base de données devait concilier plusieurs contraintes :

### Préférence Initiale : SQLite

**Attractivité de SQLite** :
- **Simplicité opérationnelle** : Fichier unique, pas de process séparé, configuration minimale
- **Légèreté** : Consommation RAM/CPU négligeable, idéal pour petit serveur Hetzner
- **Déploiement trivial** : Inclus dans release Elixir, pas de setup infrastructure
- **Coût zéro** : Pas de serveur DB dédié à gérer
- **Développement simplifié** : Pas de credentials, connexion locale instantanée

**Volumétrie attendue** :
- 20-30 albums par an
- 10-15 photos par album en moyenne (variable : 1 à 100)
- Métadonnées DB : < 10 Mo sur 10 ans
- Fichiers photos (3 WebP + 1 AVIF = 3.2 Mo/photo) : ~960 Mo/an (stockage séparé, hors DB)

SQLite largement suffisant pour ces volumes.

### Contrainte Décisive : Oban

**Besoin de traitement asynchrone** :
- Upload photos : Extraction métadonnées EXIF, génération variantes (3 WebP + 1 AVIF)
- Traitement images via Vix/libvips : 3-5 secondes par photo 12MP
- Impossibilité de bloquer requêtes HTTP pendant traitement

**Oban comme solution** :
- Background job processing robuste (retry, monitoring, scheduling)
- Alternative GenServer : Possible mais nécessite développement custom (retry logic, persistence jobs, monitoring)
- Décision : Utiliser Oban pour ne pas réinventer la roue

**Incompatibilité SQLite** :
- Oban optimisé pour PostgreSQL (PgBoss pattern, advisory locks, LISTEN/NOTIFY)
- Support SQLite expérimental via [Oban.Lite](https://github.com/sorentwo/oban_lite) mais features limitées
- Advisory locks PostgreSQL critiques pour coordination workers distribués
- LISTEN/NOTIFY PostgreSQL pour notifications temps réel (jobs enqueued, completed)

**Conclusion** : Oban → PostgreSQL obligatoire.

### Besoins Fonctionnels

**Fonctionnalités PostgreSQL utilisées** :

1. **UUID primary keys** : IDs distribués, pas de collision, pas de séquences auto-incrémentées
2. **ENUM types** : Validation typage fort pour roles (`admin`, `user`), types albums
3. **JSONB** : Stockage métadonnées variables (EXIF, variants) sans schema rigide
4. **CHECK constraints** : Validation enum-like pour statuts
5. **Indexes composites** : Optimisation requêtes fréquentes (published + date, type + published)
6. **Transactions ACID** : Garanties intégrité pour opérations multi-étapes (upload + insert DB)

**Fonctionnalités futures envisagées** :
- **Full-text search** (tsvector) : Recherche albums/photos par mots-clés
- **GeoQueries** (PostGIS) : Filtrage photos par localisation géographique
- **Read replicas** : Scaling lecture si trafic augmente significativement

### Contraintes Opérationnelles

**Infrastructure** :
- Serveur Hetzner VPS partagé (1 instance pour app + DB)
- Budget minimal : Éviter services managés coûteux (AWS RDS, Hetzner Cloud SQL)
- Configuration par défaut PostgreSQL acceptable (pas de tuning avancé nécessaire)

**Compétences** :
- Habitude PostgreSQL > SQLite
- Pas d'apprentissage majeur nécessaire
- Ecto excellente intégration PostgreSQL

## Options Considérées

### Option 1: PostgreSQL

**Description:**
Base de données relationnelle open-source, robuste, avec features avancées (JSONB, ENUM, Full-text search, PostGIS).

**Configuration:**
- Version : PostgreSQL 16 (dernière stable)
- Hébergement : Même serveur Hetzner que l'application (réduction coût)
- Configuration : Paramètres par défaut (shared_buffers, work_mem, etc.)
- Backups : Daily backups via pg_dump, conservation 7j + 4 weekly + 3 monthly

**Avantages:**
- **Oban natif** : Support complet, advisory locks, LISTEN/NOTIFY, performances optimales
- **Features riches** : ENUM, JSONB, Full-text search, PostGIS, Arrays, Window functions
- **Scaling** : Read replicas, clustering (PgBouncer), partitioning
- **Transactions ACID** : Garanties intégrité forte
- **UUIDs natifs** : Type uuid avec génération via gen_random_uuid()
- **Indexes avancés** : B-tree, GIN (JSONB), GiST (PostGIS), BRIN
- **Écosystème Elixir** : Ecto optimisé PostgreSQL, Postgrex driver mature
- **Maturité** : Stable depuis 1996, communauté large, documentation exhaustive
- **Open-source** : Pas de vendor lock-in, licence permissive

**Inconvénients:**
- **Complexité opérationnelle** : Process séparé, configuration, backups, monitoring
- **Consommation ressources** : ~50-100 MB RAM minimum vs ~10 MB SQLite
- **Setup initial** : Installation, création DB, credentials, migrations
- **Overkill volumétrie** : Features avancées sous-exploitées pour < 10 Mo données
- **Coût cognitif** : Gestion serveur DB additionnel (même si co-localisé)

**Effort estimé:** Moyen (setup initial, backups à configurer)

**Risques:**
- Consommation RAM sur petit VPS [Probabilité: Faible, Impact: Moyen]
  - Mitigation : PostgreSQL 16 optimisé, config par défaut acceptable pour faible charge
- Complexité backups [Probabilité: Moyenne, Impact: Élevé]
  - Mitigation : Scripts automatisés pg_dump + rclone vers Hetzner Storage Box

---

### Option 2: SQLite

**Description:**
Base de données relationnelle embarquée, stockée dans un fichier unique, sans serveur séparé.

**Avantages:**
- **Simplicité maximale** : Fichier unique, pas de process, pas de config
- **Légèreté** : < 10 MB RAM, CPU négligeable
- **Déploiement trivial** : Inclus dans release Elixir
- **Développement rapide** : Pas de setup DB, connexion instantanée
- **Backups simples** : Copie fichier .db
- **Suffisant volumétrie** : < 10 Mo données sur 10 ans largement gérable

**Inconvénients:**
- **Oban incompatible** : Support expérimental limité, pas de LISTEN/NOTIFY ni advisory locks
- **Concurrence write limitée** : Un seul writer à la fois, problématique pour Oban workers parallèles
- **Pas de ENUM natif** : Simulation via CHECK constraints
- **JSONB inexistant** : JSON stocké en text, pas d'indexation ni requêtes optimisées
- **Scaling impossible** : Pas de read replicas, pas de clustering
- **Features limitées** : Pas de Full-text search avancé, pas de PostGIS

**Effort estimé:** Très faible (Ecto supporte SQLite3 nativement)

**Décision:** Rejeté en raison de l'incompatibilité Oban (contrainte bloquante).

---

### Option 3: MySQL / MariaDB

**Description:**
Alternative relationnelle à PostgreSQL, populaire dans écosystème web (LAMP).

**Avantages:**
- Maturité équivalente PostgreSQL
- Popularité (hébergeurs, tutos, communauté)
- Performance lecture optimisée (certains cas d'usage)

**Inconvénients:**
- **JSONB inférieur** : JSON stocké en binaire mais requêtes moins performantes que PostgreSQL
- **ENUM moins flexible** : Changement valeurs ENUM nécessite ALTER TABLE (vs simple ajout PostgreSQL)
- **Transactions moins robustes** : Historiquement MyISAM sans transactions (InnoDB résout, mais perception)
- **Écosystème Elixir** : Myxql moins mature que Postgrex
- **Oban** : Support PostgreSQL prioritaire, MySQL secondaire
- **Pas d'avantage décisif** : Aucune raison de préférer MySQL pour ce use case

**Effort estimé:** Moyen (équivalent PostgreSQL)

**Décision:** Rejeté car aucun avantage sur PostgreSQL, JSONB inférieur, Ecto/Oban moins optimisés.

---

### Option 4: NoSQL (MongoDB, CouchDB)

**Description:**
Base de données orientée documents, schema flexible.

**Avantages:**
- Schema flexible (JSONB-like natif)
- Scaling horizontal facilité

**Inconvénients:**
- **Données relationnelles** : Albums ↔ Photos relation claire, SQL adapté
- **Transactions** : Historiquement faibles (amélioré depuis MongoDB 4+, mais complexité accrue)
- **Oban incompatible** : Nécessite PostgreSQL ou MySQL
- **Écosystème Elixir** : Ecto conçu pour SQL, MongoDB adapter tiers (Mongodb.Ecto) moins mature
- **Over-engineering** : Pas de besoin scaling horizontal pour volumétrie attendue
- **Perte features** : Contraintes FK, ENUM types, indexes composites SQL

**Effort estimé:** Élevé (changement paradigme, adapter écosystème Elixir)

**Décision:** Rejeté car données relationnelles évidentes, Oban incompatible, écosystème Elixir sous-optimal.

---

### Option 5: Ash Framework (ORM Alternative)

**Description:**
Framework Elixir offrant couche d'abstraction au-dessus d'Ecto avec CRUD auto-générés, GraphQL, authorization policies.

**Avantages:**
- CRUD auto-générés : Productivité accrue
- Policies déclaratives : Authorization élégante
- GraphQL automatique : API sans effort
- Validations riches : Changesets étendus

**Inconvénients:**
- **Over-engineering** : Framework lourd pour portfolio solo
- **Courbe apprentissage** : Concepts Ash (resources, actions, policies) à maîtriser
- **Abstraction excessive** : Perte contrôle fin sur requêtes SQL
- **DDD complexifié** : Ash impose patterns propres, friction avec DDD tactique
- **Utilité limitée** : Projet sans API GraphQL, sans besoin CRUD massif

**Effort estimé:** Très élevé (apprentissage framework, migration code existant)

**Décision:** Rejeté car over-engineering pour use case, incompatible objectif apprentissage DDD pur.

---

## Décision

L'option choisie est: **Option 1 - PostgreSQL**

### Justification

La décision est basée sur les critères suivants :

**1. Contrainte Oban (Bloquant)**

Oban nécessite PostgreSQL pour fonctionnement optimal :
- **Advisory locks** : Coordination workers distribués sans polling DB
- **LISTEN/NOTIFY** : Notifications temps réel (job enqueued → worker wake up)
- **Performance** : Optimisations PgBoss pattern (queue tables, indexes)

SQLite incompatible → Choix forcé vers PostgreSQL.

Alternative GenServer custom rejetée :
- **Effort développement** : Retry logic, persistence jobs, monitoring = réinventer Oban
- **Risque bugs** : Background job processing complexe, cas edge nombreux
- **Maintenance** : Code custom à maintenir vs dépendance Oban mature

Décision : Utiliser Oban → Accepter PostgreSQL comme conséquence.

**2. Features PostgreSQL Utiles (Important)**

Bien que volumétrie faible, PostgreSQL apporte features exploitées :

**ENUM Types** :
```sql
CREATE TYPE user_role AS ENUM ('admin', 'user');
```
- Type safety au niveau DB (vs CHECK constraints)
- Performance (enum = smallint en interne)
- Auto-documentation schema
- Ecto génère types Elixir automatiquement

**JSONB** :
```elixir
# Stockage métadonnées variables
add :exif_data, :map, default: %{}  # JSONB PostgreSQL
add :variants, :map, default: %{}   # JSONB PostgreSQL
```
- Schema flexible pour EXIF (chaque appareil photo = métadonnées différentes)
- Requêtes possibles : `WHERE exif_data @> '{"camera": "Canon"}'`
- GIN indexes pour performance requêtes JSONB (futur)

**UUID Native** :
```elixir
config :portfolio, generators: [binary_id: true]
```
- IDs distribués (pas de collision multi-serveurs futurs)
- UUIDv4 actuellement, migration UUIDv7 facile (tri chronologique)

**Indexes Composites** :
```sql
CREATE INDEX albums_published_date ON albums (published, date_prise_vue);
CREATE INDEX albums_type_published ON albums (type, published);
```
- Optimisation requêtes fréquentes (timeline publiée, filtres par type)
- Mesures performance à venir (optimisation préventive basée sur requêtes anticipées)

**3. Scaling Futur (Souhaitable)**

PostgreSQL offre chemins de scaling si projet grossit :
- **Read replicas** : Scaling lecture (probable si trafic augmente)
- **Clustering** : PgBouncer pooling, multi-instances (possible si croissance forte)
- **Migration managé** : Hetzner Cloud SQL, AWS RDS (peu probable, coût élevé)

SQLite bloquerait ces évolutions.

**4. Écosystème Elixir (Important)**

- Ecto optimisé PostgreSQL (query planner, migrations, types)
- Postgrex driver mature et performant
- Oban conçu pour PostgreSQL
- Habitude développeur (PostgreSQL > SQLite)

**5. Maturité et Communauté (Souhaitable)**

- PostgreSQL stable depuis 1996, communauté large
- Documentation exhaustive, résolution problèmes facilitée
- Open-source, pas de vendor lock-in

### Trade-offs Acceptés

**Complexité Opérationnelle** :
- Process PostgreSQL séparé à gérer (vs fichier SQLite)
- Configuration, credentials, backups, monitoring
- Acceptable : Compétences PostgreSQL existantes, setup one-time

**Consommation Ressources** :
- PostgreSQL : ~50-100 MB RAM vs ~10 MB SQLite
- Sur petit VPS Hetzner : Impact faible (PostgreSQL 16 optimisé, config par défaut acceptable)
- Monitoring à mettre en place pour vérifier consommation

**Over-Engineering Volumétrie** :
- PostgreSQL surdimensionné pour < 10 Mo données sur 10 ans
- SQLite largement suffisant niveau volumétrie
- Justification : Oban + features futures (Full-text search, PostGIS) + scaling

**Dépendance PostgreSQL** :
- Migration vers autre DB coûteuse (Ecto migrations, types spécifiques)
- Acceptable : PostgreSQL pérenne, pas de raison de changer
- Abstraction Repositories DDD facilite migration théorique

### Implémentation

**Configuration PostgreSQL** :

```elixir
# config/config.exs
config :portfolio, ecto_repos: [Portfolio.Repo]
config :portfolio, generators: [timestamp_type: :utc_datetime, binary_id: true]

# config/runtime.exs (production)
config :portfolio, Portfolio.Repo,
  url: database_url,
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
  socket_options: [:inet6]
```

**Features Utilisées** :

**1. UUID Primary Keys (UUIDv4)** :
```elixir
# Migration
create table(:albums, primary_key: false) do
  add :id, :binary_id, primary_key: true
  # ...
end

# Schema
@primary_key {:id, :binary_id, autogenerate: true}
```

**Migration UUIDv7 recommandée** (refactoring futur) :
- UUIDv7 = UUID avec timestamp intégré (tri chronologique)
- Performance indexes B-tree améliorée (inserts séquentiels vs random)
- Pas de fragmentation index
- Migration transparente (même type `binary_id`)

**2. ENUM Types** :
```sql
-- user_role
CREATE TYPE user_role AS ENUM ('admin', 'user');

-- album_type (via Ecto)
field :type, Ecto.Enum, values: [:couples, :wedding, :motherhood, ...]
```

**3. JSONB (via :map)** :
```elixir
# Schema
field :exif_data, :map, default: %{}
field :variants, :map, default: %{}

# Migration
add :exif_data, :map, default: %{}
```

**GIN Index futur** (si requêtes JSONB) :
```sql
CREATE INDEX photos_exif_gin ON photos USING GIN (exif_data);
-- Permet: WHERE exif_data @> '{"camera": "Canon EOS R5"}'
```

**4. CHECK Constraints** :
```sql
CREATE CONSTRAINT processing_status_valid
  CHECK (processing_status IN ('pending', 'processing', 'completed', 'failed'));
```

**Incohérence identifiée** : CHECK constraint pour `processing_status` vs ENUM pour `user_role`.

**Refactoring recommandé** :
```sql
-- Migration à créer
CREATE TYPE photo_processing_status AS ENUM ('pending', 'processing', 'completed', 'failed');

ALTER TABLE photos
  ALTER COLUMN processing_status TYPE photo_processing_status
  USING processing_status::photo_processing_status;
```

**5. Indexes Composites** :
```sql
-- Timeline publiée triée par date
CREATE INDEX albums_published_date ON albums (published, date_prise_vue);

-- Filtres type + published
CREATE INDEX albums_type_published ON albums (type, published);

-- Photos par album
CREATE INDEX photos_album_id ON photos (album_id);

-- Sessions utilisateur par activité
CREATE INDEX user_sessions_user_activity ON user_sessions (user_id, last_activity_at);
```

**Stratégie Backups** :

**Configuration actuelle** : En cours d'étude

**Recommandation** : Stratégie 3-2-1
- **3 copies** : Production + Local backup + Remote backup
- **2 médias** : Hetzner volume (local) + Hetzner Storage Box (remote)
- **1 offsite** : Storage Box dans autre datacenter

**Implémentation** :
```bash
# Daily backup (cron 3h du matin)
0 3 * * * /usr/local/bin/backup_postgres.sh

# backup_postgres.sh
#!/bin/bash
DATE=$(date +\%Y\%m\%d)
pg_dump -Fc portfolio_prod > /backups/portfolio_$DATE.dump

# Rotation : 7 daily + 4 weekly + 3 monthly
# Remote sync via rclone vers Hetzner Storage Box
rclone sync /backups hetzner:portfolio-backups
```

**Coût** : Hetzner Storage Box 100GB = 3.26€/mois (largement suffisant)

**Test restore mensuel** : Backup inutile si restore échoue, vérification procédure obligatoire.

**Zero-Downtime Deployments** :

**Objectif** : < 30s downtime (acceptable pour app non-critique)

**Stratégie** :
1. **Migrations backward-compatible** :
```elixir
# BAD: Breaking change
def change do
  alter table(:albums) do
    add :new_field, :string, null: false  # Crash si old code tourne
  end
end

# GOOD: Non-breaking
def change do
  alter table(:albums) do
    add :new_field, :string  # Nullable d'abord
  end
end

# Migration suivante (après deploy)
def change do
  alter table(:albums) do
    modify :new_field, :string, null: false  # Safe
  end
end
```

2. **Kamal rolling deployment** :
- Nouvelle version déployée sans arrêter ancienne
- Healthcheck `/health` validé avant routing trafic
- Swap instantané quand prête, rollback auto si échec

3. **Migrations pré-deploy** :
```bash
# Kamal hook pre-deploy
kamal deploy --skip-push  # Run migrations avant swap
```

**Monitoring** :

**Métriques à collecter** :
- Query latency (P50, P95, P99)
- Slow queries (> 100ms)
- Connection pool usage
- DB size growth
- Index hit ratio

**Outils** :
- Phoenix LiveDashboard : Ecto queries métriques
- Telemetry : Custom events pour queries critiques
- pg_stat_statements : Slow queries PostgreSQL

**Tests performance** : À réaliser (actuellement pas en production).

## Conséquences

### Positives

- **Oban pleinement fonctionnel** : Background jobs robustes, retry, monitoring, scheduling
- **Features riches exploitées** : ENUM, JSONB, UUID, indexes composites
- **Scaling path clair** : Read replicas, clustering possibles si croissance
- **Écosystème Elixir optimal** : Ecto + Postgrex + Oban intégration parfaite
- **Maturité et stabilité** : PostgreSQL éprouvé, communauté large, documentation
- **Transactions ACID** : Garanties intégrité forte pour opérations complexes
- **Évolutions futures** : Full-text search, PostGIS, Advanced indexes (GIN, GiST)

### Négatives

- **Complexité opérationnelle accrue** : Setup, backups, monitoring vs simplicité SQLite
  - Gestion : Scripts automatisés backups, monitoring Phoenix LiveDashboard
- **Consommation ressources** : ~50-100 MB RAM vs ~10 MB SQLite
  - Surveillance : Monitoring RAM VPS, PostgreSQL 16 optimisé acceptable
- **Over-engineering volumétrie** : < 10 Mo données, PostgreSQL surdimensionné
  - Justification : Oban contrainte bloquante, features futures, scaling
- **Coût cognitif** : Gestion serveur DB additionnel (même si co-localisé)
  - Acceptable : Compétences PostgreSQL existantes, overhead limité

### Neutres

- **Backups complexes** : pg_dump + rclone vs copie fichier SQLite
  - Automatisation : Scripts cron, procédure documentée, test restore mensuel
- **Dépendance PostgreSQL** : Migration vers autre DB coûteuse
  - Acceptable : PostgreSQL pérenne, abstraction Repositories DDD facilite théoriquement
- **Configuration par défaut** : Pas de tuning avancé nécessaire
  - Réévaluation : Si performance dégradée, tuning `shared_buffers`, `work_mem`

## Plan d'Action

1. **Phase 1: Setup PostgreSQL** ✅
   - Installation PostgreSQL 16 sur VPS Hetzner
   - Configuration Ecto + Postgrex
   - Migrations initiales (albums, photos, users, sessions)

2. **Phase 2: Features PostgreSQL** ✅
   - UUIDs (binary_id)
   - ENUM types (user_role)
   - JSONB (exif_data, variants)
   - CHECK constraints (processing_status)
   - Indexes composites (optimisation requêtes)

3. **Phase 3: Oban Integration** ✅
   - Migration Oban jobs table
   - Configuration workers (image_processing queue)
   - Background jobs (image variants generation)

4. **Phase 4: Backups** (En cours)
   - Script backup automatisé (pg_dump + rotation)
   - Remote backup Hetzner Storage Box
   - Test restore mensuel
   - Documentation procédure recovery

5. **Phase 5: Monitoring** (Futur)
   - Phoenix LiveDashboard métriques Ecto
   - Telemetry custom events queries critiques
   - Slow query logging (pg_stat_statements)
   - Alerting si dégradation performance

6. **Phase 6: Refactoring** (Futur, si nécessaire)
   - Migration UUIDv7 (tri chronologique, performance indexes)
   - Conversion processing_status vers ENUM (cohérence avec user_role)
   - GIN indexes JSONB (si requêtes métadonnées EXIF fréquentes)
   - Tuning PostgreSQL (si performance dégradée)

7. **Phase 7: Scaling** (Futur, si croissance trafic)
   - Read replicas (scaling lecture)
   - PgBouncer pooling (gestion connexions)
   - PostgreSQL managé (Hetzner Cloud SQL, AWS RDS si nécessaire)

**Critères de succès:**
- ✅ Oban fonctionnel avec PostgreSQL
- ✅ Migrations zero-downtime (< 30s)
- ✅ Backups automatisés quotidiens (7j + 4w + 3m rétention)
- ✅ Monitoring métriques DB (latency, slow queries)
- ✅ < 10 Mo DB sur 2 ans (validation volumétrie)
- 🔄 Test restore backup mensuel
- 🔄 Zero-downtime deployments validés

**Rollback plan:**

Si PostgreSQL pose problème (peu probable) :
1. Identifier pain point : Performance ? Complexité ? Coût RAM ?
2. Solutions graduelles :
   - Performance → Tuning config (shared_buffers, work_mem, effective_cache_size)
   - Complexité backups → Simplifier procédure, automatisation accrue
   - RAM → Réduire pool_size, tuning PostgreSQL
3. Dernier recours : Migration vers MySQL (équivalent complexité, Oban compatible)
   - Effort : 1-2 semaines (migrations, tests)
   - Pas de retour SQLite possible (Oban incompatible)

## Références

- [PostgreSQL Official Documentation](https://www.postgresql.org/docs/)
- [Ecto PostgreSQL Adapter](https://hexdocs.pm/ecto_sql/Ecto.Adapters.Postgres.html)
- [Oban PostgreSQL Requirements](https://hexdocs.pm/oban/Oban.html)
- [Phoenix Ecto Guide](https://hexdocs.pm/phoenix/ecto.html)
- [PostgreSQL Performance Tuning](https://wiki.postgresql.org/wiki/Performance_Optimization)

Documentation projet connexe :
- `docs/adr/013_async_image_processing_oban.md` (Justification Oban nécessitant PostgreSQL)
- `docs/adr/041_oban_background_jobs.md` (Configuration Oban détaillée)
- `docs/operations/backup_restore_procedures.md` (Guide backups PostgreSQL)

## Notes

### Incohérences Identifiées

**CHECK Constraint vs ENUM** :
- `user_role` : ENUM ✅ (type safety, performance)
- `processing_status` : CHECK constraint ❌ (faible typage)

**Refactoring recommandé** :
```sql
CREATE TYPE photo_processing_status AS ENUM ('pending', 'processing', 'completed', 'failed');

ALTER TABLE photos
  ALTER COLUMN processing_status TYPE photo_processing_status
  USING processing_status::photo_processing_status;
```

Justification : Cohérence architecturale, type safety DB, performance.

### Optimisations Futures

**UUIDv7** :
Migration vers UUIDv7 (UUID avec timestamp) :
- Tri chronologique natif
- Performance indexes B-tree (inserts séquentiels)
- Pas de fragmentation index
- Migration transparente (dépendance `uniq` gem)

**GIN Indexes JSONB** :
Si requêtes fréquentes sur métadonnées EXIF :
```sql
CREATE INDEX photos_exif_gin ON photos USING GIN (exif_data);
-- Permet: WHERE exif_data @> '{"camera": "Canon EOS R5"}'
```

**Full-Text Search** :
Si recherche albums/photos par mots-clés :
```sql
ALTER TABLE albums ADD COLUMN searchable tsvector;
CREATE INDEX albums_search ON albums USING GIN (searchable);
```

**PostGIS** :
Si filtrage géographique (photos par localisation) :
```sql
CREATE EXTENSION postgis;
ALTER TABLE photos ADD COLUMN location geography(POINT, 4326);
CREATE INDEX photos_location ON photos USING GIST (location);
```

### Volumétrie Actuelle et Projections

**Données actuelles** : Pas encore en production

**Projections** (basées sur 3 WebP + 1 AVIF = 3.2 Mo/photo) :
```
Formats par photo :
  - Original : 1.5 Mo (JPEG/PNG non compressé)
  - 3 WebP légères : 200 KB + 300 KB + 400 KB = 900 KB
  - 1 AVIF qualité : 800 KB
  - Total : 3.2 Mo/photo

Année 1 : 25 albums × 12 photos = 300 photos
          300 × 3.2 Mo = 960 Mo (fichiers)
          25 albums × 1 Ko + 300 photos × 2 Ko = 625 Ko (DB)

Année 5 : 1,500 photos × 3.2 Mo = 4.8 Go (fichiers), ~3 Mo (DB)
Année 10 : 3,000 photos × 3.2 Mo = 9.6 Go (fichiers), ~6 Mo (DB)
```

**Conclusion** : PostgreSQL largement surdimensionné pour volumétrie DB, mais Oban justifie choix.

### Lessons Learned

**Préférence initiale SQLite** :
- SQLite préféré pour simplicité, légèreté, coût zéro
- Volumétrie attendue (< 10 Mo DB) compatible SQLite

**Contrainte Oban** :
- Oban nécessite PostgreSQL pour performances optimales
- Choix forcé : Accepter complexité PostgreSQL pour robustesse Oban

**Trade-off** :
- Over-engineering volumétrie accepté
- Complexité opérationnelle acceptable (compétences existantes)
- Features futures (Full-text search, PostGIS, Read replicas) justifient

**Satisfaction** :
- Pas de regret sur choix PostgreSQL
- Oban valeur ajoutée importante (retry logic, monitoring, scheduling)
- Features PostgreSQL (ENUM, JSONB, indexes) exploitées positivement

**Améliorations** :
- Backups à finaliser (priorité haute)
- Monitoring à mettre en place
- Refactoring ENUM pour processing_status (cohérence)
- Migration UUIDv7 (performance indexes)

---

**Participants à la décision:**
- Thibault San - Développeur Solo

**Révisé par:**
- Thibault San - 2025-11-10
