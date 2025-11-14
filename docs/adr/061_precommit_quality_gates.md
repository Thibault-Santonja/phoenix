# ADR-061: Precommit Quality Gates et CI/CD

Statut: Accepté  
Date: 2025-11-11

## Contexte

La qualité du code doit être vérifiée automatiquement avant chaque commit et lors de l'intégration continue. Sans gates de qualité automatisés, des bugs, vulnérabilités et violations de style peuvent être introduits en production.

### Problématique

**Voir aussi** : ADR-060 (Testing Philosophy) pour la stratégie de tests, ADR-050 (Security) pour les outils de sécurité (Sobelow)

Défis qualité code :

Sans automation :
- Oubli de formater le code avant commit
- Violations Credo non détectées localement
- Vulnérabilités Sobelow découvertes en production
- Tests non exécutés localement (manque de temps)
- Dépendances vulnérables (CVE) non détectées
- Code non cohérent entre développeurs

Sans CI/CD :
- Pas de validation objective avant merge
- Broken main branch (tests échouent après merge)
- Pas de détection régression
- Déploiement manuel error-prone

Conséquences :
- Bugs en production
- Vulnérabilités sécurité
- Dette technique accumulée
- Perte de confiance dans codebase

## Options Considérées

### Option 1: Validation Manuelle Uniquement

Approche : Développeur exécute manuellement les vérifications avant commit.

Commandes manuelles :

```bash
# Avant chaque commit
mix format
mix credo
mix test
mix deps.audit
mix sobelow
```

Avantages :
- Simplicité (pas de setup)
- Contrôle total développeur

Inconvénients :
- Dépend discipline développeur (oubli fréquent)
- Chronophage (5-10 min par commit)
- Pas de garantie (peut être skippé)
- Inconsistant entre développeurs

Décision : Rejeté. Trop fragile et error-prone.

### Option 2: Git Hooks Locaux (Husky-like)

Approche : Hook pre-commit Git exécute validations automatiquement.

Configuration :

```bash
# .git/hooks/pre-commit
#!/bin/sh
mix format --check-formatted || exit 1
mix credo --strict || exit 1
mix test || exit 1
```

Avantages :
- Automatique (pas d'oubli possible)
- Bloque commit si échec
- Local (feedback rapide)

Inconvénients :
- Hooks Git non versionnés (chaque dev doit setup)
- Peut être contourné (`git commit --no-verify`)
- Ralentit workflow (tests longs)
- Pas de validation centrale (CI manquant)

Décision : Rejeté comme solution unique. Complément possible de Option 3.

### Option 3: Alias Mix + CI/CD GitHub Actions (CHOIX RETENU)

Approche : Alias `mix precommit` pour validation locale + CI GitHub Actions obligatoire.

Architecture :

```
Local Development          GitHub Actions CI
──────────────            ──────────────────

Developer                 On Push/PR
    ↓                          ↓
mix precommit            Checkout Code
    ↓                          ↓
┌──────────────┐         ┌──────────────┐
│ format       │         │ Lint Job     │
│ credo        │         │ - format     │
│ test         │         │ - credo      │
│ deps.audit   │         │ - sobelow    │
│ sobelow      │         │ - deps.audit │
│ docs         │         └──────────────┘
└──────────────┘                ↓
    ↓                    ┌──────────────┐
✅ ou ❌                 │ Test Job     │
                         │ - mix test   │
                         └──────────────┘
                                ↓
                         ┌──────────────┐
                         │ Build Job    │
                         │ - compile    │
                         │ - release    │
                         └──────────────┘
                                ↓
                         ✅ ou ❌ (block merge)
```

Avantages :
- Local : `mix precommit` rapide et facile à exécuter
- Central : CI bloque merge si échec
- Versioned : Configuration dans git (mix.exs, .github/)
- Obligatoire : PR ne peut pas merge si CI rouge
- Complet : Tous checks automatisés

Inconvénients :
- Setup initial CI requis
- Coût CI/CD (mitigé : GitHub Actions gratuit pour projets publics)
- Légère latence CI (quelques minutes)

Décision : ACCEPTÉ - Meilleur compromis automation/rigueur.

### Option 4: Pre-commit Framework (Python)

Approche : Utiliser framework `pre-commit` (Python) pour gérer hooks.

Configuration :

```yaml
# .pre-commit-config.yaml
repos:
  - repo: local
    hooks:
      - id: mix-format
        name: mix format
        entry: mix format --check-formatted
        language: system
        pass_filenames: false
```

Avantages :
- Framework mature et populaire
- Configuration versionnée
- Auto-installation hooks

Inconvénients :
- Dépendance Python (projet Elixir)
- Over-engineering pour besoin simple
- Moins idiomatique Elixir

Décision : Rejeté. Alias Mix plus idiomatique.

## Décision

L'option choisie est : Option 3 - Alias Mix precommit + CI/CD GitHub Actions

Configuration double validation :
1. Locale : `mix precommit` pour feedback rapide développeur
2. Centrale : GitHub Actions pour validation objective et blocage merge

### Justification

Cette approche combine :

Rapidité : Développeur obtient feedback local en quelques secondes
Rigueur : CI valide objectivement avant merge (pas de contournement)
Simplicité : Alias Mix familier aux développeurs Elixir
Versioning : Configuration dans git (reproductible)
Gratuit : GitHub Actions gratuit pour projets publics

## Configuration Détaillée

### Alias Mix Precommit

#### Configuration mix.exs

```elixir
# mix.exs:143-151
defp aliases do
  [
    precommit: [
      "format --check-formatted",   # 1. Vérifier formatage
      "credo --strict",              # 2. Analyse statique
      "test",                        # 3. Tests
      "deps.audit",                  # 4. Audit dépendances CVE
      "sobelow --config",            # 5. Audit sécurité
      "docs"                         # 6. Générer documentation
    ]
  ]
end
```

#### Checks Détaillés

##### 1. mix format --check-formatted

Rôle : Vérifie que tout le code est formaté selon style Elixir.

Commande :
```bash
mix format --check-formatted
```

Configuration :

```elixir
# .formatter.exs
[
  import_deps: [:ecto, :ecto_sql, :phoenix],
  subdirectories: ["priv/*/migrations"],
  plugins: [Phoenix.LiveView.HTMLFormatter],
  inputs: ["*.{heex,ex,exs}", "{config,lib,test}/**/*.{heex,ex,exs}", "priv/*/seeds.exs"]
]
```

Vérifications :
- Indentation (2 espaces)
- Espaces autour opérateurs
- Ordre des imports/alias
- Formatage HEEx templates (LiveView)
- Longueur lignes (98 caractères par défaut)

Exemple erreur :

```
** (Mix) mix format failed due to --check-formatted.
The following files are not formatted:

/lib/portfolio_web/live/admin/user_live/index.html.heex

 14  14  |  </div>
 15  15  |
 16     -|
     16 +|  <!-- Espace blanc manquant -->
```

Correction :
```bash
mix format
git add .
```

Priorité : CRITIQUE (bloque precommit)

##### 2. mix credo --strict

Rôle : Analyse statique pour détecter problèmes qualité et style.

Commande :
```bash
mix credo --strict
```

Configuration :

```elixir
# .credo.exs (absente = utilise défaut)
# Pas de config custom, utilise defaults Credo strict
```

Catégories checks :

Catégorie | Exemples | Sévérité
---|---|---
Consistency | Alias ordre, naming | Warning
Design | Large modules (> 500 lignes), complex functions | Suggestion
Readability | Code comments, pipe chains | Suggestion
Refactor | Nesting profond, duplication | Warning
Warning | Unused variables, deprecated functions | Warning

Exemple warning :

```
┃ [W] ↗ Found a TODO tag in a comment: # TODO: refactor this
┃     lib/portfolio/photography.ex:42:5 (Portfolio.Photography)
```

Exemple refactor :

```
┃ [R] ↗ Function is too complex (ABC size is 45, max is 40)
┃     lib/portfolio/services/photo_upload_service.ex:25 (upload_photos)
```

Priorité : HAUTE (permet warnings, bloque uniquement errors)

Mode strict : `--strict` élève warnings en errors (plus rigoureux)

##### 3. mix test

Rôle : Exécute toute la suite de tests automatisés.

Commande :
```bash
mix test
```

Configuration :

```elixir
# mix.exs
test_coverage: [tool: ExCoveralls],
preferred_cli_env: [
  coveralls: :test,
  precommit: :test  # Force env test pour precommit
]
```

Vérifications :
- 776 tests passent (0 failures)
- Aucune régression comportement
- Coverage maintenu (≥ 80%)

Options utiles :

```bash
# Tests uniquement modifiés (fast feedback)
mix test --stale

# Stop au premier échec (debug rapide)
mix test --max-failures=1

# Tests spécifiques
mix test test/portfolio/photography_test.exs:42
```

Priorité : CRITIQUE (bloque precommit si 1+ test échoue)

Parallélisation : Tests async réduit temps (8.2s total)

##### 4. mix deps.audit

Rôle : Audit dépendances hex.pm pour vulnérabilités CVE connues.

Commande :
```bash
mix deps.audit
```

Dépendance :

```elixir
# mix.exs
{:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false}
```

Vérifications :
- CVE database hex.pm à jour
- Aucune dépendance vulnérable
- Aucun package retired

Exemple alerte :

```
[MEDIUM] Known security vulnerability in package phoenix
CVE-2023-12345: XSS vulnerability in LiveView
Affected versions: < 1.7.10
Recommendation: Upgrade to phoenix ~> 1.7.10
```

Action si CVE :

```bash
# Mise à jour dépendance
mix deps.update phoenix
mix deps.get
mix test  # Vérifier compatibilité
```

Priorité : HAUTE (sécurité critique)

Exceptions : Certains CVE peuvent être ignorés si non applicables (documenter)

##### 5. mix sobelow --config

Rôle : Audit sécurité spécifique Elixir/Phoenix (OWASP).

Commande :
```bash
mix sobelow --config
```

Dépendance :

```elixir
# mix.exs
{:sobelow, "~> 0.13", only: [:dev, :test], runtime: false}
```

Configuration :

```elixir
# .sobelow-conf
[
  verbose: true,
  private: false,
  skip: false,
  router: "lib/portfolio_web/router.ex",
  exit: "low",
  format: "txt",
  threshold: "low",
  ignore: [
    # CSP configuré dans endpoint.ex via put_secure_headers/2
    "Config.CSP",
    # String.to_atom dans composants tiers Mishka (pas user input)
    "DOS.StringToAtom:lib/portfolio_web/components/mishka_chelekom_components/",
    # HTTPS configuré en production via reverse proxy
    "Config.HTTPS",
    # Traversal validé avec validate_path_safety/1, UUID-based paths
    "Traversal.FileModule:lib/portfolio/photography/storage/local_storage.ex",
    "Traversal.FileModule:lib/portfolio/image_processor.ex"
  ]
]
```

Catégories vérifications :

Catégorie | Exemples | Sévérité
---|---|---
XSS | `raw/1`, `html_escape: false` | High
SQL Injection | String interpolation dans queries | High
CSRF | Pipeline sans `protect_from_forgery` | Medium
Traversal | `File.read(user_input)` | High
Config | HTTPS disabled, CSP missing | Medium
DOS | `String.to_atom(user_input)` | Medium

Exemple finding :

```
[HIGH] XSS: Potential HTML injection with raw/1
lib/portfolio_web/components/core_components.ex:245

Recommendation: Avoid raw/1 on user-supplied data. Use HEEx escaping.
```

Priorité : HAUTE (sécurité critique)

Ignore justifié : Certains findings peuvent être ignorés avec justification (voir config)

##### 6. mix docs

Rôle : Génère documentation ExDoc pour vérifier docstrings complètes.

Commande :
```bash
mix docs
```

Dépendance :

```elixir
# mix.exs
{:ex_doc, "~> 0.31", only: :dev, runtime: false}
```

Vérifications :
- Tous modules publics ont `@moduledoc`
- Toutes fonctions publiques ont `@doc`
- Typespecs cohérentes (`@spec`)
- Links internes valides

Exemple warning :

```
warning: undefined @doc attribute for public function create_album/2
  lib/portfolio/photography.ex:42
```

Priorité : MOYENNE (documentation importante mais pas bloquante)

Output : Génère docs/ en HTML (ignoré par git)

### GitHub Actions CI/CD

#### Configuration Workflow

```yaml
# .github/workflows/ci.yml
name: CI
on:
  push:
    branches: [main]
    tags: ["*"]
  pull_request:
    branches: [main]

permissions:
  contents: read

env:
  MIX_ENV: test

jobs:
  lint:
    name: LINT
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2  # Setup Elixir/Erlang
      
      - name: Cache dependencies
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: lint-${{ hashFiles('**/mix.lock') }}
      
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - run: mix format --check-formatted
      - run: mix deps.unlock --check-unused
      - run: mix hex.audit
      - run: mix deps.audit
      - run: mix credo
      - run: mix sobelow --config

  test:
    name: TEST
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      
      - name: Cache dependencies
        uses: actions/cache@v4
        with:
          path: |
            deps
            _build
          key: test-${{ hashFiles('**/mix.lock') }}
      
      - run: mix deps.get
      - run: mix test --max-failures=1 --color

  build:
    name: BUILD
    needs: [lint, test]
    runs-on: ubuntu-24.04
    env:
      MIX_ENV: prod
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v2
      
      - run: mix deps.get --only prod
      - run: mix assets.setup
      - run: mix assets.deploy
      - run: mix compile --warnings-as-errors
      - run: mix release --overwrite
      
      # Docker build + push si tag
      - uses: docker/build-push-action@v6
        if: contains(github.ref, 'refs/tags/')
        with:
          push: true
          tags: thibaultsan/portfolio:${{ github.ref_name }}
```

#### Jobs CI

##### Job 1: Lint (Qualité et Sécurité)

Durée : ~2-3 minutes

Checks :
1. `mix compile --warnings-as-errors` : Aucun warning compilation
2. `mix format --check-formatted` : Code formaté
3. `mix deps.unlock --check-unused` : Pas de deps inutilisées
4. `mix hex.audit` : Audit hex.pm registry
5. `mix deps.audit` : CVE dépendances
6. `mix credo` : Analyse statique
7. `mix sobelow --config` : Audit sécurité

Blocage : PR ne peut pas merge si job échoue

Cache : Dependencies cachées (accélère CI)

##### Job 2: Test (Comportement)

Durée : ~3-4 minutes

Checks :
1. `mix test --max-failures=1` : Tous tests passent
2. Stop au premier échec (feedback rapide)

Blocage : PR ne peut pas merge si 1+ test échoue

Parallélisation : Tests async réduit temps

##### Job 3: Build (Release Production)

Durée : ~5-6 minutes

Checks :
1. Compile production (MIX_ENV=prod)
2. Build assets (Tailwind, esbuild)
3. Déploiement assets (phx.digest)
4. Release Elixir
5. Build Docker image (si tag)

Blocage : PR ne peut pas merge si build échoue

Artifact : Docker image pushée vers Docker Hub si tag release

#### Stratégie Branches

```
Feature Branch          Main Branch          Production
──────────────         ────────────         ──────────

feature/new-album
    ↓
mix precommit (local)
    ↓
git push
    ↓
PR créée
    ↓
CI: lint, test, build ──→ ✅ ou ❌
    ↓
Code review
    ↓
Merge → main ──────────→ CI: lint, test, build
                              ↓
                         Tag v1.2.3
                              ↓
                         CI: build + Docker push
                              ↓
                         Deploy Kamal ────→ Production
```

Protection branches :
- Main branch : require PR + CI pass
- Pas de push direct sur main
- Require 1 review (si équipe)

#### Badge Status CI

```markdown
# README.md
[![CI](https://github.com/thibaultsan/portfolio/actions/workflows/ci.yml/badge.svg)](https://github.com/thibaultsan/portfolio/actions/workflows/ci.yml)
```

Affiche statut CI (vert = pass, rouge = fail)

### Workflow Développeur

#### Développement Local

```bash
# 1. Créer feature branch
git checkout -b feature/new-album

# 2. Développer + tester au fil de l'eau
mix test test/portfolio/photography_test.exs

# 3. Avant commit : precommit
mix precommit

# Si échec format
mix format
mix precommit

# Si échec credo
# Corriger violations
mix precommit

# Si échec tests
mix test --failed  # Rejouer tests échoués uniquement
mix precommit

# 4. Commit
git add .
git commit -m "feat: add album management"

# 5. Push
git push origin feature/new-album
```

#### Code Review + CI

```bash
# 6. Créer PR sur GitHub
# CI démarre automatiquement

# 7. CI échoue → corrections
git add .
git commit -m "fix: credo violations"
git push

# 8. CI passe → review code
# Reviewer approuve

# 9. Merge PR → main
# CI re-run sur main

# 10. Tag release
git tag v1.2.3
git push --tags

# 11. CI build + push Docker
# 12. Deploy via Kamal (manuel ou auto)
```

### Optimisations Performance

#### Cache Dependencies CI

```yaml
- uses: actions/cache@v4
  with:
    path: |
      deps
      _build
    key: ${{ env.MIX_ENV }}-${{ hashFiles('mix.lock') }}
```

Bénéfice : Réduit temps CI de 5-6 min → 2-3 min

#### Tests Stale Localement

```bash
# Rejouer uniquement tests modifiés
mix test --stale
```

Bénéfice : Feedback rapide (1-2s vs 8s)

#### Parallel Jobs CI

```yaml
jobs:
  lint:
    # Pas de dépendance, run en parallèle
  test:
    # Pas de dépendance, run en parallèle
  build:
    needs: [lint, test]  # Attend lint + test
```

Bénéfice : Lint et Test en parallèle (total 3-4 min vs 6-8 min séquentiel)

## Métriques et Monitoring

### Métriques Precommit Local

Temps exécution :

Check | Durée Typique
---|---
format --check-formatted | < 1s
credo --strict | 2-3s
test | 8s
deps.audit | 1-2s
sobelow --config | 3-4s
docs | 2-3s
Total | ~20s

Optimisation si trop lent :

```bash
# Skip docs si pas modifié modules publics
mix format --check-formatted && \
mix credo --strict && \
mix test && \
mix deps.audit && \
mix sobelow --config
# Total: ~15s
```

### Métriques CI GitHub Actions

Durée jobs :

Job | Durée Moyenne | Durée avec Cache
---|---|---
Lint | 5-6 min | 2-3 min
Test | 6-7 min | 3-4 min
Build | 8-10 min | 5-6 min
Total | ~15-20 min | ~8-10 min

Temps total PR :
- Lint + Test (parallèle) : ~3-4 min
- Build (après lint/test) : ~5-6 min
- Total PR validation : ~8-10 min

Minutes CI gratuites GitHub :
- Plan gratuit : 2000 min/mois
- Usage actuel : ~10 min/PR × 40 PR/mois = 400 min/mois
- Marge : 1600 min/mois restantes

### Dashboard CI

GitHub Actions fournit dashboard avec :
- Historique runs (succès/échecs)
- Durée par job
- Logs détaillés
- Artifacts (Docker images)

URL : `https://github.com/thibaultsan/portfolio/actions`

## Exceptions et Contournements

### Skip Precommit (Urgence Uniquement)

Cas exceptionnels :
- Hotfix production critique
- WIP commit (work in progress)
- Docs seules (pas de code)

Commande :

```bash
# Skip precommit local (déconseillé)
git commit -m "wip: draft" --no-verify

# ⚠️ CI validera quand même lors du push
```

Règle : Toujours fixer avant merge (CI bloquera)

### Skip CI (Docs Uniquement)

Cas valides :
- Modification README.md uniquement
- Ajout docs/ markdown
- Correction typos

Commande :

```bash
git commit -m "docs: fix typo [skip ci]"
```

Note : `[skip ci]` dans message commit désactive CI GitHub Actions

Règle : Utiliser uniquement pour docs (pas de code)

### Ignore Sobelow Finding

Cas valides :
- False positive documenté
- Mitigation en place (validé manuellement)
- Code tiers (bibliothèques)

Configuration :

```elixir
# .sobelow-conf
ignore: [
  "Config.CSP",  # CSP configuré dans endpoint.ex (justifié)
]
```

Règle : Toujours documenter raison ignore (commentaire config)

## Plan d'Action

### Court Terme (Priorité: HAUTE)

1. Fixer format user_live/index.html.heex
   - Erreur détectée lors du run precommit
   - Espaces blancs trailing lines
   - Estimation : 0.1 jour

2. Vérifier Sobelow ignores
   - Valider que tous ignores sont justifiés
   - Documenter raisons dans .sobelow-conf
   - Estimation : 0.25 jour

3. Documentation workflow
   - Guide développeur dans docs/development/
   - Workflow precommit + CI/CD
   - Estimation : 0.5 jour

### Moyen Terme (Priorité: MOYENNE)

1. Ajouter coverage gate CI
   - Bloquer PR si coverage < 80%
   - Intégration Codecov ou Coveralls
   - Estimation : 0.5 jour

2. Pre-commit hooks optionnels
   - Setup automatique hooks Git (optionnel)
   - Script `.git/hooks/pre-commit` symlink
   - Estimation : 0.5 jour

3. Notifications Slack CI
   - Webhook CI vers canal Slack
   - Alertes échecs build main
   - Estimation : 0.25 jour

### Long Terme (Priorité: BASSE)

1. Déploiement automatique CD
   - Auto-deploy sur tag release
   - Kamal deploy via CI
   - Estimation : 1 jour

2. Linting JavaScript/CSS
   - ESLint pour hooks.js
   - Stylelint pour CSS custom
   - Estimation : 1 jour

3. Performance regression tests
   - Benchmarks dans CI
   - Bloquer si régression > 10%
   - Estimation : 2 jours

## Conséquences

### Positives

- Qualité code garantie (format, credo, tests)
- Sécurité vérifiée (sobelow, deps.audit)
- Feedback rapide local (precommit 20s)
- Validation objective CI (pas de contournement)
- Main branch toujours stable (CI bloque merge)
- Documentation vivante (mix docs)
- Gratuit (GitHub Actions plan free)
- Historique qualité (dashboard CI)

### Négatives

- Temps precommit local (20s delay avant commit)
- Temps CI (8-10 min delay avant merge)
- Discipline requise (exécuter precommit systématiquement)
- Setup initial CI (configuration workflow)

### Neutres

- Minutes CI limitées (2000/mois plan free, suffisant)
- Precommit peut être skippé localement (CI validera quand même)
- Documentation requise (mix docs) peut être lourde

## Références

### Documentation Outils

- Mix : https://hexdocs.pm/mix/
- ExUnit : https://hexdocs.pm/ex_unit/
- Credo : https://hexdocs.pm/credo/
- Sobelow : https://hexdocs.pm/sobelow/
- ExDoc : https://hexdocs.pm/ex_doc/

### GitHub Actions

- GitHub Actions Docs : https://docs.github.com/en/actions
- actions/checkout : https://github.com/actions/checkout
- actions/cache : https://github.com/actions/cache
- jdx/mise-action : https://github.com/jdx/mise-action

### Best Practices

- Elixir Style Guide : https://github.com/christopheradams/elixir_style_guide
- Phoenix Security Best Practices : https://hexdocs.pm/phoenix/security.html
- OWASP Secure Coding : https://owasp.org/www-project-secure-coding-practices-quick-reference-guide/

### Fichiers Code Concernés

- `mix.exs:143-151` : Alias precommit
- `.github/workflows/ci.yml` : CI/CD GitHub Actions
- `.sobelow-conf` : Configuration Sobelow
- `.formatter.exs` : Configuration format

### ADRs Connexes

- ADR-060 : Testing Philosophy Strategy (tests inclus dans precommit)
- ADR-050 : Security Layered Defense (sobelow, deps.audit)
- ADR-042 : Telemetry Metrics Monitoring (métriques CI futures)

---

Date de création: 2025-11-11  
Dernière révision: 2025-11-11
