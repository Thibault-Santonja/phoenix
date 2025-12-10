# ADR-002: Architecture Multi-Sous-Domaines

Statut: Accepté
Date: 2025-05

## Contexte

Le portfolio personnel couvre plusieurs domaines d'activité distincts :

1. Photographie : Galerie professionnelle avec albums, timeline, gestion d'images
2. Technique : Blog tech, articles sur Elixir, CI/CD, Kamal, projets open-source
3. AMVCC : Association de Mise en Valeur du Château de Coucy (recherche historique, reconstitution)

Chaque domaine a des besoins spécifiques :
- Identité visuelle propre : Couleurs, typographie, navigation différentes (surtout photographie)
- Public cible distinct : Photographes vs développeurs vs passionnés d'histoire
- **Évolution indépendante** : Chaque section peut évoluer sans impacter les autres

### Contraintes

1. Budget limité : Projet personnel non rémunérateur, pas de budget pour acheter plusieurs domaines
2. Infrastructure unique : Un seul serveur Hetzner pour héberger l'ensemble
3. Simplicité opérationnelle : Déploiement unique via Kamal, pas de gestion multi-serveurs
4. SEO : Besoin d'indexation séparée par domaine d'activité
5. Branding professionnel : Impression de sites dédiés plutôt que de sous-pages

### Besoins Fonctionnels

**Administration centralisée** :
- Interface admin unique pour gérer tous les contenus
- Authentification globale (actuellement limitée � la photographie)
- Possibilité future d'étendre l'auth � d'autres sections

**Évolutivité** :
- Ajout facile de nouvelles sections (ex: blog voyage, portfolio design)
- Possibilité de migration future vers microservices si nécessaire
- Refactoring vers Phoenix Umbrella envisageable sans refonte compl�te

## Options Considérées

### Option 1: Architecture Multi-Sous-Domaines

Description :
Un domaine principal avec sous-domaines dédiés par section.

Architecture :
```
thibaultsan.com                 (Landing page + Admin)
 photo.thibaultsan.com       (Portfolio photographique)
 tech.thibaultsan.com        (Blog technique)
 amvcc.thibaultsan.com       (Association AMVCC)
```

**Implémentation Phoenix:**
```elixir
# Router avec host matching
scope "/", PortfolioWeb, host: "photo." do
  pipe_through :photography
  live "/", PhotographyLive.Index, :index
  live "/gallery", PhotographyLive.Gallery, :index
  live "/timeline", PhotographyLive.Timeline, :index
end

scope "/", PortfolioWeb, host: "tech." do
  pipe_through :tech
  live "/", TechLive.Index, :index
  live "/blog/ci", TechLive.Blog.Ci, :index
end

scope "/", PortfolioWeb, host: "amvcc." do
  pipe_through :amvcc
  live "/", AmvccLive.Index, :index
  live "/blog", AmvccLive.Blog, :index
end

# Admin sur domaine principal
scope "/admin", PortfolioWeb.Admin do
  pipe_through :require_authenticated_admin
  live "/", DashboardLive.Index, :index
end
```

**Pipelines spécialisés:**
Chaque pipeline applique un layout différent pour l'identité visuelle propre :
```elixir
pipeline :photography do
  plug :put_root_layout, html: {PortfolioWeb.Layouts, :photography}
  # ... autres plugs
end

pipeline :tech do
  plug :put_root_layout, html: {PortfolioWeb.Layouts, :tech}
end

pipeline :amvcc do
  plug :put_root_layout, html: {PortfolioWeb.Layouts, :amvcc}
end
```

**Configuration DNS (Cloudflare):**
```
A     *                  157.180.70.8     (Wildcard pour tous sous-domaines)
A     thibaultsan.com    157.180.70.8
CNAME www                thibaultsan.com
```

**SSL/TLS:**
Wildcard SSL Cloudflare (`*.thibaultsan.com`) géré automatiquement.

Avantages :
- Séparation conceptuelle forte : Chaque domaine a son identité
- SEO optimisé : Google indexe les sous-domaines comme sites distincts
- Branding professionnel : `photo.thibaultsan.com` donne impression de site dédié
- Évolutivité : Ajout de nouveaux sous-domaines trivial
- Layouts personnalisés par domaine (couleurs, menus, typographie)
- Infrastructure unique : Un seul serveur, un seul déploiement
- Coût minimal : Pas d'achat de domaines supplémentaires
- Migration future possible : Peut évoluer vers microservices ou Umbrella si besoin
- Configuration Phoenix simple : Host matching natif

Inconvénients :
- Configuration DNS lég�rement plus complexe que paths simples
- Sessions non partagées entre sous-domaines par défaut (feature/bug selon cas)
- Tests nécessitent host mocking
- Développement local nécessite `/etc/hosts` ou DNS local

Effort estimé : Faible (Phoenix supporte nativement le host matching)

Risques :
- Complexité DNS sous-estimée [Probabilité: Faible, Impact: Faible]
  - Mitigation: Cloudflare simplifie la gestion, wildcard DNS suffit
- Sessions non partagées posent probl�me [Probabilité: Faible, Impact: Moyen]
  - Mitigation: Auth actuellement limitée au domaine principal, extension future via cookie domain `.thibaultsan.com` si besoin

---

### Option 2: Path-Based Routing

Description :
Routes basées sur chemins sous un seul domaine.

Architecture :
```
thibaultsan.com/photography
thibaultsan.com/tech
thibaultsan.com/amvcc
thibaultsan.com/admin
```

Implémentation :
```elixir
scope "/photography", PortfolioWeb do
  pipe_through :photography
  live "/", PhotographyLive.Index, :index
  live "/gallery", PhotographyLive.Gallery, :index
end

scope "/tech", PortfolioWeb do
  pipe_through :tech
  live "/", TechLive.Index, :index
end
```

Avantages :
- Configuration DNS triviale (un seul domaine)
- Sessions partagées naturellement
- Développement local simplifié (pas de config hosts)
- Tests plus simples (pas de host mocking)

Inconvénients :
- Séparation conceptuelle faible : Tout perçu comme un seul site
- SEO moins optimal : Google indexe comme sections d'un site unique
- Branding amateur : `/photography` donne impression de sous-page
- URLs longues : `thibaultsan.com/photography/gallery/voyage-japon`
- Layouts partagés difficiles � différencier fortement
- Pas de migration possible vers microservices sans refonte URLs

Effort estimé : Tr�s faible (routing Phoenix standard)

**Décision:** Rejeté en raison de la faiblesse de séparation conceptuelle et du SEO sous-optimal.

---

### Option 3: Phoenix Umbrella

Description :
Applications Phoenix séparées dans un monorepo Umbrella.

Architecture :
```
apps/
 photography/       # App Phoenix indépendante
 tech_blog/         # App Phoenix indépendante
 amvcc/             # App Phoenix indépendante
 admin/             # App Phoenix pour admin
```

Avantages :
- Isolation maximale : Chaque app a ses dépendances, config, DB
- Déploiement indépendant possible
- Équipes séparées possibles
- Scalabilité horizontale facilitée

Inconvénients :
- Complexité élevée : Gestion de 4 applications distinctes
- Duplication code : Auth, composants UI, helpers dupliqués
- Overhead infrastructure : Potentiellement plusieurs serveurs/DB
- Effort développement multiplié : Chaque feature dupliquée 4 fois
- Over-engineering : Pas de besoin actuel de cette séparation forte

Effort estimé : Tr�s élevé (refactoring complet, nouvelles dépendances, config multi-apps)

Risques :
- Complexité ingérable pour développeur solo [Probabilité: Élevée, Impact: Critique]
- Dérive vers microservices prématurée [Probabilité: Moyenne, Impact: Élevé]

**Décision:** Rejeté car over-engineering pour taille actuelle. Envisageable en refactoring futur si croissance significative.

---

### Option 4: Domaines Séparés

Description :
Acheter et gérer plusieurs domaines distincts.

Architecture :
```
thibault-photography.com
thibault-tech.fr
amvcc-coucy.fr
```

Avantages :
- Séparation maximale : Sites compl�tement indépendants
- SEO optimal : Domaines dédiés par activité
- Branding ultra-professionnel

Inconvénients :
- Coût élevé : 3-4 domaines � 10-15��/an = 40-60��/an
- Fragmentation branding : Nom "Thibault San" dilué
- Complexité DNS : Gestion de plusieurs zones DNS
- Infrastructure multiple : Potentiellement plusieurs serveurs
- Maintenance multipliée : Renouvellements, configs séparées

Effort estimé : Élevé (gestion administrative et technique multipliée)

Risques :
- Coût annuel récurrent prohibitif [Probabilité: Certaine, Impact: Élevé]
- Fragmentation identité personnelle [Probabilité: Élevée, Impact: Moyen]

**Décision:** Rejeté en raison du coût et de la fragmentation du branding personnel.

---

## Décision

L'option choisie est: **Option 1 - Architecture Multi-Sous-Domaines**

### Justification

La décision est basée sur les crit�res suivants :

**1. Séparation Conceptuelle (Critique)**

Chaque domaine d'activité a besoin d'une identité forte :
- Photographie : Portfolio professionnel avec esthétique épurée, focus images
- Tech : Blog technique avec code samples, design sobre et fonctionnel
- AMVCC : Contenu historique/culturel avec esthétique médiévale

Les sous-domaines permettent cette séparation sans fragmenter le branding "Thibault San".

**2. Branding Professionnel (Tr�s important)**

`photo.thibaultsan.com` donne l'impression d'un site photographique dédié, pas d'une simple sous-page. Crucial pour crédibilité professionnelle aupr�s de clients potentiels.

Comparaison perçue :
- `photo.thibaultsan.com` � "Photographe avec site dédié"
- `thibaultsan.com/photography` � "Développeur qui fait aussi de la photo"

**3. SEO (Important)**

Google indexe les sous-domaines comme sites distincts, permettant :
- Mots-clés différenciés par domaine (`photographie mariage`, `elixir phoenix`, `château de coucy`)
- Autorité de domaine construite indépendamment
- Backlinks ciblés par activité

**4. Coût Maîtrisé (Important)**

Infrastructure unique :
- Un seul domaine � acheter/renouveler : ~12��/an
- Un seul serveur Hetzner : 4.51��/mois
- Un seul déploiement Kamal
- SSL wildcard Cloudflare gratuit

Vs domaines séparés : 40-60��/an + potentiellement plusieurs serveurs.

**5. Évolutivité (Souhaitable)**

Architecture permet évolutions futures :
- Ajout de nouveaux sous-domaines trivial (ex: `blog.thibaultsan.com`, `design.thibaultsan.com`)
- Migration vers Phoenix Umbrella possible sans changer URLs
- Séparation en microservices envisageable si trafic justifie
- Possibilité future de déployer certains sous-domaines sur serveurs dédiés

### Implémentation Technique

**Routing Phoenix:**

Host matching natif dans le router :
```elixir
scope "/", PortfolioWeb, host: "photo." do
  pipe_through :photography
  # Routes photography
end

scope "/", PortfolioWeb, host: "tech." do
  pipe_through :tech
  # Routes tech
end

scope "/", PortfolioWeb, host: "amvcc." do
  pipe_through :amvcc
  # Routes amvcc
end

scope "/", PortfolioWeb do
  pipe_through :browser
  # Landing page + Admin sur domaine principal
end
```

**Configuration Production:**
```elixir
# config/runtime.exs
config :portfolio, PortfolioWeb.Endpoint,
  check_origin: [
    "https://#{host}",
    "https://amvcc.#{host}",
    "https://photo.#{host}",
    "https://tech.#{host}"
  ],
  url: [host: host, port: 443, scheme: "https"]
```

**Configuration Développement:**
```elixir
# config/dev.exs
config :portfolio, PortfolioWeb.Endpoint,
  check_origin: false  # Simplifie développement local
```

Développement local utilise `/etc/hosts` :
```
127.0.0.1 localhost
127.0.0.1 photo.localhost
127.0.0.1 tech.localhost
127.0.0.1 amvcc.localhost
```

**DNS Cloudflare:**

Configuration actuelle (simple et efficace) :
```
Type    Name             Content          Proxy Status
A       *                157.180.70.8     Proxied
A       thibaultsan.com  157.180.70.8     Proxied
CNAME   www              thibaultsan.com  Proxied
```

Le wildcard `*` capture tous les sous-domaines (photo, tech, amvcc, futurs).

**SSL/TLS:**

Cloudflare g�re automatiquement le wildcard SSL `*.thibaultsan.com` (plan gratuit).

### Layouts Personnalisés

Chaque pipeline applique un layout distinct pour identité visuelle propre :

**Photography** : Design épuré, focus images, palette noir/blanc/or
**Tech** : Design sobre, code blocks, palette bleu/gris
**AMVCC** : Design médiéval, palette terre/or, typographie gothique

Implémentation :
```elixir
# lib/portfolio_web/components/layouts/photography.html.heex
# lib/portfolio_web/components/layouts/tech.html.heex
# lib/portfolio_web/components/layouts/amvcc.html.heex
```

Composants partagés possibles via imports, mais layouts racine distincts.

### Authentification

**Stratégie actuelle:**
- Auth limitée au domaine principal (admin photographie)
- Sessions isolées par sous-domaine (cookie domain par défaut)

**Évolution future:**
Si besoin d'auth partagée (ex: commentaires blog tech, acc�s restreint AMVCC) :
```elixir
config :portfolio, PortfolioWeb.Endpoint,
  session_options: [
    domain: ".thibaultsan.com",  # Partage cookies entre sous-domaines
    secure: true,
    http_only: true
  ]
```

Pour l'instant, cette complexité n'est pas nécessaire.

### Trade-offs Acceptés

**Configuration DNS/SSL lég�rement plus complexe:**
- Wildcard DNS nécessaire
- SSL wildcard (géré automatiquement par Cloudflare)
- Acceptable : Configuration one-time, pas de maintenance récurrente

**Sessions non partagées par défaut:**
- Cookies limités au sous-domaine actuel
- Acceptable : Auth actuellement centralisée sur domaine principal
- Migration facile si besoin futur via `domain: ".thibaultsan.com"`

**Tests avec host mocking:**
```elixir
test "photo subdomain routes correctly" do
  conn = build_conn(:get, "http://photo.localhost:4000/")
  conn = get(conn, "/")
  assert html_response(conn, 200) =~ "Portfolio"
end
```
- Acceptable : Phoenix facilite le host mocking, pas de complexité majeure

**Préoccupation ségrégation admin en DB:**
- Actuellement : Admin et contenus partagent la même DB PostgreSQL
- Inquiétude : Séparation logique vs séparation physique
- Options futures si besoin :
  - PostgreSQL schemas séparés par contexte
  - Bases de données séparées
  - Migration vers Umbrella avec DBs indépendantes
- Pour l'instant : Séparation via bounded contexts DDD suffisante

## Conséquences

### Positives

- Identité visuelle forte : Chaque domaine a son design unique (couleurs, typo, navigation)
- SEO optimisé : Indexation séparée par Google, autorité domaine ciblée
- Branding professionnel : Impression de sites dédiés, pas de sous-pages
- Infrastructure simple : Un serveur, un déploiement, coût maîtrisé (< 5��/mois)
- **Évolutivité facile** : Ajout nouveaux sous-domaines sans refonte
- Migration possible : Peut évoluer vers Umbrella ou microservices sans casser URLs
- Administration centralisée : Un seul admin pour gérer tous les contenus
- Layouts personnalisés : Chaque section a sa propre charte graphique
- **Coût minimal** : Un seul domaine, SSL wildcard gratuit

### Négatives

- Configuration initiale DNS : Wildcard + vérification propagation
  - Gestion : Documentation config Cloudflare, one-time setup
- Sessions isolées : Auth non partagée entre sous-domaines par défaut
  - Gestion : Acceptable actuellement, cookie domain partageable si besoin futur
- Tests lég�rement complexes : Host mocking nécessaire
  - Gestion : Helpers de test créés pour simplifier
- Inquiétude ségrégation DB : Admin et contenus partagent même base
  - Surveillance : Évaluer besoin séparation physique si croissance
  - Gestion : DDD bounded contexts assurent séparation logique pour l'instant

### Neutres

- Développement local : Nécessite `/etc/hosts` configuration
  - Documentation : Guide setup local dans README
- **Pas de SEO cross-domain** : Backlinks photography ne profitent pas � tech
  - Acceptable : Activités distinctes avec audiences différentes
- **Vendor lock-in DNS Cloudflare** : Migration DNS complexe si changement provider
  - Acceptable : Standards DNS, export/import possible, Cloudflare stable

## Plan d'Action

1. **Phase 1: Configuration Infrastructure**
   - Configuration DNS Cloudflare (wildcard `*`)
   - Vérification SSL wildcard Cloudflare
   - Configuration `/etc/hosts` développement local

2. **Phase 2: Implémentation Routing**
   - Pipelines spécialisés par sous-domaine
   - Host matching dans router Phoenix
   - Layouts personnalisés (photography, tech, amvcc)
   - Configuration `check_origin` production

3. **Phase 3: Déploiement Sous-Domaines**
   - `photo.thibaultsan.com` : Portfolio photographique complet
   - `tech.thibaultsan.com` : Blog technique avec articles CI/Kamal/Elixir
   - `amvcc.thibaultsan.com` : Contenu association AMVCC
   - Domaine principal : Landing page + Admin centralisé

4. **Phase 4: Tests et Monitoring**
   - Tests host matching par sous-domaine
   - Vérification SEO indexation séparée
   - Monitoring Telemetry par sous-domaine

5. **Phase 5: Évolutions Futures** (En attente de besoin)
   - Ajout nouveaux sous-domaines si nouvelles activités
   - Auth partagée via cookie domain si nécessaire
   - Ségrégation DB (schemas ou bases séparées) si croissance
   - Migration vers Umbrella si complexité justifie

**Crit�res de succ�s:**
-  3+ sous-domaines fonctionnels en production
-  Layouts distincts par sous-domaine appliqués
-  Indexation Google séparée par sous-domaine
-  Infrastructure unique (1 serveur, 1 déploiement)
-  Coût < 10��/mois (domaine + hébergement)

**Rollback plan:**

Si architecture sous-domaines pose probl�me (peu probable) :
1. Identifier pain points spécifiques (DNS ? Sessions ? SEO ?)
2. Solutions graduelles :
   - Probl�me DNS � Simplifier avec A records directs
   - Probl�me sessions � Cookie domain partagé `.thibaultsan.com`
   - Probl�me SEO � Redirections 301 préservent autorité
3. Dernier recours : Migration vers path-based routing
   - Redirections 301 : `photo.thibaultsan.com/*` � `thibaultsan.com/photography/*`
   - Refactoring router (1-2 jours effort)

## Références

- [Phoenix Host-based Routing](https://hexdocs.pm/phoenix/routing.html#scoped-routes)
- [Subdomain vs Subdirectory for SEO - Moz](https://moz.com/blog/subdomains-vs-subfolders)
- [Cloudflare DNS Documentation](https://developers.cloudflare.com/dns/)
- [Phoenix Endpoint Configuration](https://hexdocs.pm/phoenix/Phoenix.Endpoint.html)

Documentation projet connexe :
- `docs/adr/001_choix_technologiques_stack.md` (Justification stack Phoenix)
- `docs/adr/003_domain_driven_design_adoption.md` (Bounded contexts alignés sur sous-domaines)

## Notes

### État Actuel (Novembre 2024)

**Sous-domaines en production:**
-  `photo.thibaultsan.com` : Portfolio photographique complet
-  `tech.thibaultsan.com` : Blog technique (CI, Kamal, Elixir)
-  `amvcc.thibaultsan.com` : Association AMVCC
-  `thibaultsan.com` : Landing page + Admin

**Satisfaction:**
- Tr�s content du choix d'architecture
- Layouts personnalisés permettent identité visuelle forte
- SEO indexation séparée fonctionne bien
- Aucune difficulté technique rencontrée

**Préoccupations actuelles:**
- Ségrégation admin/DB : Pour l'instant acceptable avec DDD
- � surveiller si croissance significative du contenu

### Évolutions Futures Possibles

**Nouveaux sous-domaines envisagés:**
- `blog.thibaultsan.com` : Blog personnel (voyage, vie)
- `design.thibaultsan.com` : Portfolio design UI/UX si pivot

**Migration Umbrella:**
Si projet grandit significativement (équipe, trafic) :
- Séparer photography, tech, amvcc en apps indépendantes
- DBs séparées par contexte
- Déploiement indépendant possible
- URLs inchangées (pas de breaking change)

**Microservices:**
Scénario extrême (peu probable pour portfolio personnel) :
- Photography sur serveur dédié (scaling images)
- Tech/AMVCC sur serveur partagé
- Admin centralisé avec API vers services

### Lessons Learned

**Surprises positives:**
- Configuration DNS Cloudflare tr�s simple (wildcard efficace)
- Phoenix host matching robuste et performant
- Aucun probl�me développement local avec `/etc/hosts`
- SSL wildcard Cloudflare transparent

**Confirmations:**
- Path-based routing aurait été insuffisant pour branding
- Umbrella aurait été over-engineering prématuré
- Domaines séparés auraient coûté trop cher sans bénéfice clair

**Ajustements:**
- Aucun regret sur architecture choisie
- Ségrégation DB � évaluer dans 1-2 ans selon évolution

---

**Participants � la décision:**
- Thibault San - Développeur Solo

**Révisé par:**
- Thibault San - 2025-11-10
