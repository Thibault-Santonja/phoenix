# ADR-001: Choix de la Stack Technique

Statut: Accepté
Date: 2025-05

## Contexte

Au démarrage du projet Portfolio en mai 2024, le choix de la stack technique devait répondre à plusieurs contraintes et objectifs :

### Objectifs Principaux

1. **Perfectionnement technique** : Approfondir l'expérience Elixir acquise précédemment
2. **Focus méthodologique** : Concentrer l'effort sur les pratiques (DDD, TDD, Clean Code, documentation) plutôt que sur l'apprentissage d'une nouvelle technologie
3. **Développement rapide** : Livrer un portfolio fonctionnel en quelques mois
4. **Philosophie** : Utiliser un écosystème dont la philosophie résonne (concurrence, fault-tolerance, "let it crash")

### Contraintes

1. **Budget limité** : Projet solo sans objectif commercial, coût d'hébergement minimal
2. **Déploiement simplifié** : Compétences limitées en infrastructure et frontend
3. **Maintenabilité solo** : Pas d'équipe à former, choix techniques assumables seul
4. **Temps limité** : Pas de marge pour apprendre une technologie entièrement nouvelle

### Cas d'Usage

Portfolio photographique avec :
- Gestion d'albums et photos
- Interface d'administration
- Galerie publique avec lazy loading
- Traitement asynchrone d'images (génération de variantes)
- Authentification administrateur
- Trafic attendu faible (< 1000 visiteurs/mois initialement)

## Options Considérées

### Option 1: Elixir + Phoenix + LiveView

**Description:**
Stack fonctionnelle complète basée sur Elixir/Phoenix avec LiveView pour le frontend et PostgreSQL comme base de données.

**Stack détaillée:**
- Backend: Elixir 1.18 + Phoenix 1.8
- Frontend: Phoenix LiveView + TailwindCSS
- BDD: PostgreSQL 16
- Traitement images: Vix (libvips), formats WebP + AVIF
- Background jobs: Oban
- Hébergement: Hetzner VPS + Kamal + Docker + Cloudflare

**Avantages:**
- Expérience préalable en Elixir (courbe d'apprentissage réduite)
- Écosystème Phoenix mature et productif (générateurs, conventions)
- LiveView élimine la complexité SPA (pas de duplication logique client/serveur)
- Déploiement simplifié : release Elixir = binaire autosuffisant
- Performance exceptionnelle avec faible consommation ressources
- Concurrence native (traitement images parallèle, connexions simultanées)
- Philosophie "let it crash" et fault-tolerance adaptée au long terme
- Coût hébergement minimal (serveur Hetzner CX22 4€/mois suffit)
- Hot code reloading en production possible

**Inconvénients:**
- Écosystème plus restreint que Node.js ou Python
- Courbe d'apprentissage Elixir si besoin de contributeurs futurs
- LiveView = connexions WebSocket persistantes (charge mémoire)
- Moins de ressources d'apprentissage en français

**Effort estimé:** Moyen (stack connue, focus sur architecture et méthodologie)

**Risques:**
- Difficulté à trouver des contributeurs Elixir [Probabilité: Faible, Impact: Moyen]
  - Mitigation: Projet solo pour le moment, pas de besoin immédiat
- Charge serveur avec LiveView si trafic élevé [Probabilité: Très faible, Impact: Faible]
  - Mitigation: Trafic attendu < 100 connexions simultanées, Phoenix gère facilement 100k+ connexions

---

### Option 2: Python + Django/FastAPI

**Description:**
Stack Python avec Django (batteries included) ou FastAPI (moderne, async) + React/Vue pour le frontend.

**Avantages:**
- Maîtrise excellente de Python
- Écosystème très riche (data science, ML si besoin futur)
- Documentation abondante
- Communauté large

**Inconvénients:**
- Déploiement complexe : virtualenvs, pip dependencies, gunicorn/uvicorn config, workers
- Coût serveur plus élevé (besoin de plus de ressources pour workers)
- Gestion asynchrone moins naturelle que Elixir
- Si SPA : duplication logique client/serveur, complexité accrue
- Pas d'expérience récente en déploiement Python production

**Effort estimé:** Élevé (déploiement complexe, setup frontend si SPA)

**Risques:**
- Complexité déploiement sous-estimée [Probabilité: Élevée, Impact: Élevé]
- Coût serveur dépassant le budget [Probabilité: Moyenne, Impact: Moyen]

**Décision:** Rejeté en raison de la complexité de déploiement et du coût.

---

### Option 3: Rust + Framework Web

**Description:**
Rust avec Actix-web ou Axum pour des performances maximales.

**Avantages:**
- Performance exceptionnelle
- Type safety extrême
- Pas de garbage collector
- Intérêt personnel pour apprendre Rust

**Inconvénients:**
- Compétences Rust très limitées (débutant)
- Courbe d'apprentissage très raide
- Productivité initiale faible
- Écosystème web moins mature que Elixir/Phoenix
- Ownership/borrowing complexifie le développement rapide
- Pas de focus possible sur DDD/méthodologie si apprentissage langage simultané

**Effort estimé:** Très élevé (apprentissage langage + paradigmes + écosystème web)

**Risques:**
- Délai de livraison largement dépassé [Probabilité: Très élevée, Impact: Élevé]
- Abandon du projet par frustration [Probabilité: Moyenne, Impact: Critique]

**Décision:** Rejeté car objectif principal = méthodologie, pas apprentissage langage.

---

### Option 4: Node.js + Express/NestJS + React/Vue

**Description:**
Stack JavaScript/TypeScript full-stack avec SPA moderne.

**Avantages:**
- Écosystème le plus large (npm)
- Communauté énorme
- Isomorphisme JavaScript client/serveur possible
- Beaucoup de ressources d'apprentissage

**Inconvénients:**
- Aversion personnelle pour JavaScript/TypeScript
- Callback hell / complexité async (même avec async/await)
- Pas de fault-tolerance native
- SPA = complexité accrue (webpack, state management, hydration)
- Consommation mémoire élevée comparée à Elixir
- Pas de plaisir de développement attendu

**Effort estimé:** Moyen à élevé (complexité SPA)

**Risques:**
- Démotivation par manque de plaisir de développement [Probabilité: Élevée, Impact: Élevé]

**Décision:** Rejeté en raison de l'aversion technologique et du manque d'intérêt.

---

### Option 5: Ruby on Rails

**Description:**
Framework Ruby mature et productif, conventions fortes.

**Avantages:**
- Productivité très élevée (convention over configuration)
- Écosystème mature (gems)
- Turbo/Stimulus pour interactivité moderne

**Inconvénients:**
- Pas d'intérêt personnel pour Ruby
- Performance inférieure à Elixir
- Pas d'expérience Ruby préalable
- Pas de real-time aussi naturel que LiveView
- Coût serveur plus élevé (besoin de workers pour async)

**Effort estimé:** Moyen (courbe apprentissage Rails)

**Risques:**
- Manque de motivation [Probabilité: Moyenne, Impact: Moyen]

**Décision:** Rejeté car aucun intérêt personnel ni avantage décisif sur Elixir.

---

## Décision

L'option choisie est: **Option 1 - Elixir + Phoenix + LiveView**

### Justification

La décision est basée sur les critères suivants, par ordre d'importance :

**1. Coût d'hébergement (Critique)**

Le budget étant la contrainte principale, Elixir offre le meilleur ratio performance/coût :
- Serveur Hetzner CX22 (2 vCPU, 4 GB RAM) : 4.51€/mois
- Pas besoin de workers séparés (OTP gère la concurrence nativement)
- Un seul serveur suffit pour trafic < 10k visiteurs/jour
- Comparable : Python nécessiterait 2-3x plus de ressources (workers Celery, Redis)

**2. Plaisir de développement / Apprentissage (Très important)**

Projet personnel sans pression commerciale, le plaisir est essentiel :
- Expérience Elixir préalable = zone de confort avec possibilité d'approfondissement
- Philosophie Erlang/OTP résonne personnellement (fault-tolerance, "let it crash")
- Pattern matching, pipe operator, immutabilité = paradigmes appréciés
- Évite JavaScript/TypeScript (aversion personnelle)

**3. Productivité / Rapidité de développement (Important)**

Objectif de livraison en quelques mois :
- Phoenix générateurs accélèrent développement (`mix phx.gen.live`)
- LiveView élimine complexité SPA (pas de build frontend, pas de state management)
- Conventions Phoenix réduisent décisions architecturales
- Ecto migrations et changesets = robustesse avec peu d'effort
- Hot reloading dev très rapide

**4. Performance / Scalabilité (Souhaitable)**

Bien que trafic faible attendu, la marge de manœuvre est rassurante :
- Phoenix : 2M+ connexions WebSocket démontrées sur hardware modeste
- Traitement images parallèle natif avec Task.async_stream
- Latency < 10ms pour requêtes typiques
- Possibilité de scaler verticalement puis horizontalement si besoin

### Architecture de Déploiement

Le choix d'hébergement a suivi un processus distinct :

**Hébergeurs considérés:**
- **Fly.io** : Rejeté (américain, data sovereignty)
- **OVH** : Français, mais plus cher que Hetzner
- **Infomaniak** : Suisse, mais gamme limitée
- **Hetzner** : Choisi (allemand, RGPD, rapport qualité/prix exceptionnel)

**Stack de déploiement:**
- **Docker** : Containerisation standard
- **Kamal** : Déploiement simplifié (alternative à Capistrano, inspiré des pratiques 37signals)
- **Cloudflare** : DNS + CDN + protection DDoS (gratuit)

Kamal a été privilégié après lecture d'articles AppSignal démontrant sa simplicité pour déployer des applications Elixir sur VPS. Alternative Fly.io aurait été plus simple mais impliquait data hébergée aux USA.

### Librairies JavaScript Complémentaires

Bien que LiveView minimise le besoin de JavaScript, certaines interactions nécessitent des librairies spécialisées :

- **anime.js** : Animations fluides (galerie photos, transitions)
- **sortable.js** : Drag & drop pour réorganiser photos dans albums
- **Alpine.js** : Non utilisé actuellement, pourrait être ajouté pour interactions immédiates sans round-trip serveur (dropdowns, tooltips)

Ces librairies sont ajoutées progressivement selon les besoins, pas d'over-engineering initial.

### Trade-offs Acceptés

**Courbe d'apprentissage pour contributeurs:**
- Elixir moins connu que JavaScript/Python
- Mitigation : Projet solo, pas de besoin de contributeurs à court terme
- Documentation exhaustive pour onboarding futur si nécessaire

**Écosystème plus restreint:**
- Moins de packages Hex que npm ou PyPI
- Mitigation : Phoenix écosystème mature couvre 95% des besoins web
- Communauté active et réactive

**Connexions WebSocket persistantes (LiveView):**
- Chaque utilisateur = process Elixir en mémoire
- Mitigation : Trafic faible attendu (< 100 connexions simultanées), Phoenix gère 100k+ connexions sur 1-2 GB RAM
- Si problème futur : possibilité de migrer certaines pages en HTML statique

**Moins de ressources en français:**
- Documentation majoritairement anglaise
- Mitigation : Niveau d'anglais technique suffisant, communauté francophone Elixir existe (ElixirFrance Slack)

## Conséquences

### Positives

- **Coût maîtrisé** : Hébergement < 5€/mois pour plusieurs années de trafic
- **Déploiement simplifié** : `kamal deploy` suffit, pas de configuration complexe
- **Performance garantie** : Marge confortable pour croissance trafic (10x minimum)
- **Plaisir de développement** : Motivation maintenue sur durée longue
- **Concurrence native** : Traitement images parallèle sans complexité
- **Fault-tolerance** : Supervision OTP = récupération automatique erreurs
- **Focus méthodologie** : Temps disponible pour DDD, TDD, Clean Code, documentation
- **Scalabilité future** : Architecture permet croissance sans refonte

### Négatives

- **Écosystème de niche** : Moins de packages que JavaScript/Python
  - Gestion : Vérifier disponibilité packages critiques avant de les nécessiter
- **Recrutement difficile** : Si besoin de contributeurs, pool Elixir restreint
  - Gestion : Documentation exhaustive pour onboarding, rester projet solo acceptable
- **Investissement apprentissage** : Contributeurs futurs devront apprendre Elixir
  - Gestion : Code idiomatique et bien documenté facilite apprentissage

### Neutres

- **LiveView vs SPA** : Choix architectural fort, migration SPA future complexe
  - Acceptable : Pas de besoin SPA identifié, LiveView suffit pour use case
- **Vendor lock-in Elixir** : Migration vers autre langage coûteuse
  - Acceptable : Elixir stable et pérenne (10+ ans), pas de risque abandon
- **Connexions persistantes** : Charge serveur proportionnelle aux utilisateurs actifs
  - Surveillance : Monitoring Telemetry pour anticiper scaling si besoin

## Plan d'Action

1. **Phase 1: Setup Initial**
   - Installation Elixir 1.18, Phoenix 1.8
   - Configuration PostgreSQL 16
   - Setup Hetzner VPS + Kamal
   - Configuration Cloudflare DNS

2. **Phase 2: Architecture DDD**
   - Définition Bounded Contexts (Photography, Auth)
   - Implémentation Aggregates (Album, Photo, User)
   - Repositories pattern
   - Domain Events via PubSub

3. **Phase 3: Features Core**
   - Authentification Magic Link
   - Gestion Albums et Photos
   - Traitement images asynchrone (Oban + Vix) : 3 WebP + 1 AVIF
   - Interface admin LiveView

4. **Phase 4: Optimisations** (En cours)
   - Lazy loading images (IntersectionObserver)
   - Cache avec Cachex
   - Monitoring Telemetry
   - SEO optimizations

**Critères de succès:**
-  Application déployée en production < 3 mois
-  Coût hébergement < 10€/mois
-  Temps de réponse < 100ms (P95)
-  Couverture tests > 80%
-  Documentation architecture complète

**Rollback plan:**

Si Elixir/Phoenix s'avère inadapté (peu probable) :
1. Identifier pain points spécifiques
2. Envisager migration progressive :
   - Option A : Garder backend Elixir, ajouter API REST + SPA
   - Option B : Migration complète vers Python + Django (6-12 mois effort)
3. Exporter données PostgreSQL (format standard, migration facilitée)

## Références

- [Documentation Phoenix](https://hexdocs.pm/phoenix/overview.html)
- [Phoenix LiveView Documentation](https://hexdocs.pm/phoenix_live_view/)
- [Articles AppSignal sur déploiement Elixir](https://blog.appsignal.com/category/elixir.html)
- [Kamal Documentation](https://kamal-deploy.org/)
- [Hetzner Cloud](https://www.hetzner.com/cloud)
- [Pragmatic Studio - Elixir Courses](https://pragmaticstudio.com/elixir)

Documentation projet connexe :
- `docs/adr/043_deployment_docker_kamal_hetzner.md` (ADR déploiement détaillé)
- `docs/studies/deployment_docker_kamal_hetzner.md` (Guide opérationnel)

## Notes

### Considérations Futures

**Si trafic > 10k visiteurs/jour:**
- Ajouter serveur PostgreSQL dédié (PgBouncer pooling)
- Implémenter CDN pour assets statiques (Cloudflare R2)
- Clustering multi-VPS avec libcluster

**Si besoin mobile app:**
- Option 1 : LiveView Native (iOS/Android natif en Elixir) - expérimental
- Option 2 : API REST Phoenix + Flutter
- Option 3 : API GraphQL (Absinthe) + React Native

**Si besoin offline-first:**
- Réévaluer architecture : SPA + Service Workers + IndexedDB
- Possibilité d'hybride : pages statiques + LiveView pour admin

### Lessons Learned (Après 6+ mois)

**Satisfactions:**
- Déploiement Kamal + Hetzner extrêmement simple et fiable
- LiveView productivité exceptionnelle, pas de regret vs SPA
- Performance Elixir largement au-delà des attentes
- Coût hébergement conforme (4.51€/mois stable)

**Ajustements:**
- Ajout anime.js et sortable.js pour UX (non prévu initialement)
- Alpine.js pas encore nécessaire, à réévaluer si interactions immédiates requises
- Oban indispensable pour traitement images, bon choix

**Confirmations:**
- Pas de regret sur rejet Python (déploiement aurait été cauchemar)
- Pas de regret sur rejet Rust (focus méthodologie réussi)
- Pas de regret sur rejet JavaScript (plaisir développement maintenu)

---

**Participants à la décision:**
- Thibault San - Développeur Solo

**Révisé par:**
- Thibault San - 2025-11-10
