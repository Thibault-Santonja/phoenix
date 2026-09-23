# Guide 002 : déployer le portfolio en production

Ce guide s'adresse à quelqu'un qui n'a jamais déployé ce projet. Il explique
ce qui se passe à chaque étape, pas seulement la commande à taper. Pour les
raisons du choix de Kamal, voir [ADR-043](../adr/043_deployment_docker_kamal_hetzner.md).

## 1. Ce que « déployer » veut dire ici

Le projet est une application Elixir compilée en *release* : un dossier
autonome contenant la machine virtuelle Erlang et le code compilé, qui se
lance avec `bin/portfolio start`. Cette release est empaquetée dans une image
Docker, puis cette image est lancée sur un serveur.

Le déploiement enchaîne donc quatre opérations :

1. **Build** : construire l'image Docker à partir du code source.
2. **Push** : envoyer l'image sur un registre (Docker Hub), qui sert de dépôt
   d'images.
3. **Pull** : le serveur télécharge l'image depuis le registre.
4. **Boot** : le serveur démarre un conteneur avec la nouvelle image, attend
   que le contrôle de santé réponde, puis bascule le trafic dessus et arrête
   l'ancien conteneur.

L'outil qui orchestre ces quatre étapes est [Kamal](https://kamal-deploy.org/)
(version 2.12 ici). Il n'y a ni Kubernetes ni plateforme managée : Kamal se
connecte au serveur en SSH et pilote Docker à distance.

Le serveur héberge aussi un *proxy* (kamal-proxy) qui termine le TLS, obtient
les certificats Let's Encrypt et route chaque nom de domaine vers le conteneur.
C'est lui qui permet la bascule sans coupure : le trafic ne part vers le
nouveau conteneur qu'une fois son contrôle de santé validé.

## 2. La carte des lieux

| Élément | Valeur | Où c'est défini |
| --- | --- | --- |
| Serveur | variable de shell `KAMAL_WEB_HOST` (Hetzner CX22, 2 vCPU, 4 Go) | `config/deploy.yml`, clés `servers`, `accessories.db.host`, `builder.remote` |
| Utilisateur SSH | variable de shell `KAMAL_SSH_USER` | `config/deploy.yml`, clé `ssh`. **La même valeur que la plateforme photographique**, faute de quoi le garde-fou de `kamal remove` devient aveugle et un retrait mal ciblé supprime le proxy partagé |
| Domaines servis | `thibaultsan.com`, `amvcc.`, `photo.`, `tech.` | `config/deploy.yml`, clé `proxy.hosts` |
| Image | `thibaultsan/portfolio` sur Docker Hub | `config/deploy.yml`, clé `image` |
| Port applicatif | 4000 dans le conteneur | `Dockerfile`, `proxy.app_port` |
| Contrôle de santé | `GET /health` toutes les 30 s | `config/deploy.yml`, `Dockerfile` |
| Base de données | conteneur `postgres:16-alpine` sur le même serveur, publié sur `127.0.0.1:5432` uniquement | `config/deploy.yml`, clé `accessories.db` |
| Plafonds | 400 Mo et 0,5 vCPU pour l'application, 250 Mo pour la base | `config/deploy.yml`, clés `options`. Gardés par `test/portfolio/config/deploy_test.exs` |
| Données persistantes | `/var/portfolio/uploads`, `/var/portfolio/backups`, `/var/portfolio/db` | clés `volumes` et `accessories.db.directories` |

Les fichiers envoyés par les visiteurs et la base vivent **en dehors** du
conteneur, dans des volumes montés depuis le serveur. C'est ce qui permet de
détruire et recréer le conteneur sans rien perdre.

## 3. Préparer sa machine (une seule fois)

### 3.1 Outils

- Docker, en fonctionnement (`docker info` doit répondre).
- Kamal : `gem install kamal` ou via mise, comme le reste de l'outillage.
- Les variables `KAMAL_WEB_HOST` et `KAMAL_SSH_USER` exportées dans le shell
  de déploiement, et un accès SSH au serveur avec ce compte (tester :
  `ssh "$KAMAL_SSH_USER@$KAMAL_WEB_HOST" true`). Une variable oubliée arrête
  Kamal immédiatement, en local, sur `should be a string` : lancer
  `kamal config` avant tout déploiement provoque volontairement cette erreur
  franche.

### 3.2 Les secrets

Kamal ne stocke aucun mot de passe. Le fichier `.kamal/secrets` déclare
seulement **quels noms** il va chercher, et les lit dans l'environnement du
shell. Les variables attendues :

| Variable | À quoi elle sert |
| --- | --- |
| `KAMAL_REGISTRY_USERNAME` | compte Docker Hub qui reçoit l'image |
| `KAMAL_REGISTRY_PASSWORD` | jeton d'accès Docker Hub (pas le mot de passe du compte) |
| `SECRET_KEY_BASE` | signature des sessions et des jetons Phoenix |
| `DATABASE_URL` | adresse complète de la base pour l'application |
| `POSTGRES_PASSWORD` | mot de passe du conteneur PostgreSQL |
| `LIVE_VIEW_SIGNING_SALT` | exigée par `config/runtime.exs` : sans elle l'application refuse de démarrer |
| `SMTP_USERNAME`, `SMTP_PASSWORD` | envoi des courriels (liens magiques), relais `smtp.protonmail.ch` |
| `ADMIN_EMAIL` | compte administrateur créé au premier démarrage |

Si une variable manque, Kamal s'arrête avec un message explicite avant de
toucher au serveur. Rien n'est déployé à moitié.

> `SECRET_KEY_BASE` et `DATABASE_URL` ne doivent jamais changer entre deux
> déploiements sans intention : changer la première déconnecte toutes les
> sessions, changer la seconde pointe l'application vers une autre base.

### 3.3 Où le build se passe, et pourquoi

Le serveur est en x86_64 (amd64), la machine de développement est un Mac Apple
Silicon (arm64). L'image doit donc être construite pour une architecture qui
n'est pas celle de la machine.

Construire en émulation ne fonctionne pas ici : la machine virtuelle Erlang
se corrompt pendant `mix deps.compile`, avec des erreurs qui n'ont aucun
rapport apparent avec le code (`could not call Module.put_attribute/3`, puis
`no next heap size found: 2305825417730925309` et un abandon du processus).
Le même build passe sans erreur en arm64 natif et sur le serveur. Rosetta ne
corrige pas le problème.

La configuration prévoit donc un **builder distant** :

```yaml
builder:
  context: .
  arch: amd64
  remote: ssh://<%= ENV["KAMAL_SSH_USER"] %>@<%= ENV["KAMAL_WEB_HOST"] %>
```

Kamal envoie le contexte de build au serveur en SSH et y lance `docker build`,
nativement. La compilation des 46 dépendances y prend environ 100 secondes.
Conséquence à connaître : pendant un déploiement, le serveur compile **et**
sert le site. Sur 2 vCPU, le site reste disponible mais répond plus lentement
quelques minutes.

## 4. Déployer

### 4.1 Avant de lancer

```bash
mix test               # la suite complète
mix check              # formatage, compilation, Credo, Sobelow, Dialyzer
git status             # l'arbre doit être propre
kamal config           # lecture seule, ne touche à aucun serveur
```

`kamal config` est le pré-vol. Il prouve deux choses, et il est le seul à les
prouver : que toutes les variables `KAMAL_*` sont exportées (une variable
oubliée arrête Kamal sur `should be a string`, franchement et localement), et
que le fichier passe la validation de schéma de Kamal. Relire dans sa sortie
`ssh_options.user`, `builder.remote`, le bloc `accessories` en entier et
`logging`.

**Ce qu'il ne montre pas**, et qu'il ne faut pas croire y lire : sa sortie rend
`Kamal::Configuration#to_h`, qui omet `servers.web.options` (donc le plafond
mémoire et la part processeur de l'application), `minimum_version`, `proxy` et
`service`. Vérifié contre Kamal 2.12.0. C'est
`test/portfolio/config/deploy_test.exs`, dans la suite de tests, qui garde ces
valeurs-là.

Le crochet git `pre-commit` rejoue déjà une partie de ces contrôles (format,
compilation sans avertissement, Sobelow) à chaque commit, mais il ne lance pas
les tests : ils restent à lancer à la main avant un déploiement.

Kamal accepte de construire avec des modifications non commitées, mais il le
signale (`Building with uncommitted changes`) et étiquette l'image avec un
suffixe `_uncommitted`. À éviter : l'image déployée ne correspond alors à
aucun commit, donc à rien de reproductible.

La version affichée en pied de site vient du dernier tag git (voir
`git_version/0` dans `mix.exs`). Pour livrer une version identifiable :

```bash
git tag 0.4.7 && git push --tags
```

### 4.2 La commande

```bash
kamal deploy
```

Déroulé, avec ce qu'il faut vérifier à chaque étape :

| Étape | Ce que Kamal fait | Si ça casse |
| --- | --- | --- |
| `Log into image registry` | connexion Docker Hub | jeton expiré ou absent de l'environnement |
| `Build and push app image` | build sur le serveur, envoi au registre | erreurs de compilation, voir §6 |
| `Ensure app can pass healthcheck` | démarre le conteneur, interroge `/health` | l'application démarre mais ne répond pas : variables d'environnement ou base |
| `Detect stale containers` | repère les vieux conteneurs | sans conséquence |
| `Deploy app` | le proxy bascule le trafic, l'ancien conteneur s'arrête | rien à faire, la bascule est atomique |

Tant que le contrôle de santé échoue, **l'ancienne version continue de servir
le trafic**. Un déploiement raté ne coupe pas le site.

### 4.3 Les migrations de base

Aucun crochet (`hook`) ne les lance : les fichiers de `.kamal/hooks/` sont
tous des `.sample`, donc inactifs. Après un déploiement qui ajoute une
migration :

```bash
kamal app exec 'bin/portfolio eval "Portfolio.Release.migrate()"'
```

`Portfolio.Release.migrate_and_bootstrap()` fait la même chose en créant en
plus le compte administrateur, utile seulement sur une base neuve.

> Ordre à respecter : une migration qui **supprime** une colonne doit être
> appliquée après le déploiement du code qui cesse de l'utiliser, jamais
> avant, sinon l'ancienne version encore en ligne plante.

### 4.4 Vérifier

```bash
kamal app logs -f                       # ou l'alias : kamal logs
curl -I https://thibaultsan.com/health
```

Et, après le premier démarrage, la seule vérification de ce que le conteneur a
réellement reçu :

```bash
docker inspect portfolio-web-<version> \
  --format '{{.HostConfig.Memory}} {{.HostConfig.NanoCpus}} {{.HostConfig.LogConfig.Type}}'
# attendu : 419430400 500000000 journald
```

Trois contrôles croisés avec la plateforme photographique, qui vit sur la même
machine et qu'aucun outil ne compare :

- `ssh.user` identique dans les deux `config/deploy.yml` (les deux lisent
  `KAMAL_SSH_USER`, donc la même valeur par construction). Deux comptes
  distincts rendent aveugle le garde-fou de `kamal remove`, qui supprime alors
  le proxy partagé et les six noms d'hôtes ;
- bloc `proxy.run` identique au caractère près (`version: v0.9.2`,
  `log_max_size: 10m`). Kamal ne le vérifie pas entre applications : la
  première qui crée le proxy impose sa configuration, définitivement ;
- ports d'accessoires distincts : 5432 pour cette base, 5433 pour celle de la
  plateforme, les deux sur `127.0.0.1` uniquement.

## 5. Les autres commandes utiles

| Commande | Effet |
| --- | --- |
| `kamal setup` | première installation sur un serveur neuf : installe Docker, le proxy, les accessoires, puis déploie |
| `kamal rollback <version>` | redémarre la version précédente, déjà présente sur le serveur (la plus rapide des réparations) |
| `kamal app logs -f` | suivre les journaux en direct |
| `kamal iex` | console Elixir connectée à l'application en production |
| `kamal ssh` | shell dans le conteneur |
| `kamal app details` | état des conteneurs |
| `kamal proxy logs` | journaux du proxy, utiles pour un problème de certificat ou de domaine |
| `kamal accessory reboot db` | redémarrer PostgreSQL |

`kamal rollback` est le premier réflexe quand une version déployée se comporte
mal : elle réutilise une image déjà téléchargée, donc la remise en état prend
quelques secondes, sans rebuild.

## 6. Les pannes déjà rencontrées

**`error: 1Password: failed to fill whole buffer` au moment du commit.**
Les commits sont signés en SSH via 1Password. Le coffre est verrouillé :
le déverrouiller et refaire le commit, plutôt que de contourner avec
`--no-gpg-sign`, ce qui produirait un commit non signé dans l'historique.

**`could not call Module.put_attribute/3` ou `no next heap size found` pendant
`mix deps.compile`.** Le build tourne en émulation amd64. Vérifier que
`builder.remote` est bien présent dans `config/deploy.yml` (voir §3.3). Ce
n'est pas un problème de dépendances : le même `mix.lock` compile sans erreur
en natif.

**Le contrôle de santé échoue en boucle.** Lire les journaux du conteneur
(`kamal app logs`). Les causes les plus fréquentes : `DATABASE_URL` erronée,
`SECRET_KEY_BASE` absente, ou une migration non appliquée qui fait planter une
requête au démarrage.

**Le certificat TLS n'est pas émis.** Le domaine doit pointer vers le serveur
**avant** le déploiement : Let's Encrypt valide la propriété du domaine par
une requête HTTP. Vérifier l'enregistrement DNS, puis `kamal proxy logs`.

## 7. Pour aller plus loin

- Cours complet sur Kamal, indépendant de ce projet, avec les pannes déjà
  rencontrées et leur diagnostic : `~/Notes/Tech/kamal-deploiement.md`
- [Documentation officielle de Kamal](https://kamal-deploy.org/docs/installation/)
- Références internes :
  [deploying-phoenix-with-kamal](../references/deployment/deploying-phoenix-with-kamal.md),
  [advanced-phoenix-kamal-deployment](../references/deployment/advanced-phoenix-kamal-deployment.md)
- Décisions liées : [ADR-044 (CDN)](../adr/044_cdn_strategy_cloudflare.md),
  [ADR-045 (sauvegardes)](../adr/045_backup_automation_strategy.md),
  [ADR-046 (préproduction)](../adr/046_docker_preprod_environment.md),
  [ADR-053 (HTTPS et proxy)](../adr/053_https_reverse_proxy_architecture.md)
