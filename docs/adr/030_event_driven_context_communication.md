# ADR-030: Communication Event-Driven entre Bounded Contexts

Statut: Accepté
Date: 2025-11-11

## Contexte

Dans une architecture Domain-Driven Design (DDD) avec plusieurs bounded contexts (Photography, Auth), la communication entre ces contextes doit être soigneusement orchestrée pour maintenir le découplage et l'indépendance de chaque domaine.

### Problématique

Le portfolio Photography comporte deux bounded contexts principaux :
- Photography Context : Gestion des albums et photos
- Auth Context : Authentification et gestion des utilisateurs

Ces contextes doivent parfois réagir aux événements de l'autre contexte. Par exemple :
- Lorsqu'un album est publié, il faut invalider le cache CDN et l'application cache
- Lorsqu'une photo est uploadée, il faut extraire les métadonnées EXIF
- Lorsqu'un magic link est vérifié, on pourrait vouloir logger l'événement

La question centrale est : Comment faire communiquer ces contextes sans créer de couplage fort ?

### Contraintes

- Découplage : Les contextes ne doivent pas avoir de dépendances directes entre eux
- Extensibilité : Ajouter de nouveaux comportements sans modifier le code existant
- Simplicité : Solution pragmatique adaptée � la taille du projet (1 développeur, petit serveur Hetzner)
- Observabilité : Tracer les événements pour debugging et monitoring
- Infrastructure existante : Utiliser les outils déj� disponibles dans l'écosyst�me Elixir/Phoenix

### Impact si aucune décision n'est prise

Sans syst�me d'événements, les options sont :
1. Appels directs : `Auth.something()` appelé depuis `Photography` � couplage fort
2. Callbacks : Fonctions de callback passées en param�tres � complexité élevée
3. Polling : Vérifier périodiquement les changements � inefficace et latence

Ces approches créent du couplage, réduisent la maintenabilité et violent les principes DDD.

## Options considérées

### Option 1: Appels directs entre contextes

Description :

Les contextes s'appellent directement via leur API publique. Par exemple, `Photography.publish_album/1` appellerait directement `CacheInvalidator.invalidate/1` et `CDN.purge/1`.

```elixir
def publish_album(%Album{} = album) do
  with {:ok, album} <- AlbumRepository.update(album, %{published: true}),
       :ok <- CacheInvalidator.clear_albums(),
       :ok <- CDN.invalidate_album(album.slug) do
    {:ok, album}
  end
end
```

Avantages :
- Tr�s simple � implémenter et comprendre
- Exécution synchrone, facile � débugger
- Pas de dépendances externes (PubSub, brokers)
- Visibilité directe du workflow dans le code

Inconvénients :
- Couplage fort entre modules et contextes
- Impossible d'ajouter de nouveaux comportements sans modifier le code source
- Viole le principe Open/Closed (SOLID)
- Difficile � tester unitairement (mocking nécessaire)
- Si un side-effect échoue, toute l'opération échoue

Effort estimé : Faible

Risques :
- Dette technique importante [Probabilité: Élevée, Impact: Moyen]
- Difficulté � faire évoluer l'application [Probabilité: Élevée, Impact: Élevé]

### Option 2: Phoenix.PubSub avec Domain Events

Description :

Utiliser Phoenix.PubSub (inclus nativement dans Phoenix) pour diffuser des événements domaine. Les bounded contexts publient des événements lorsque des actions métier importantes se produisent, et des handlers dédiés (GenServer) s'abonnent et réagissent � ces événements.

Architecture :

```
Publisher (Context)           PubSub              Subscribers (Handlers)
                   
Photography.publish_album
       �
       > DomainEvents.publish(:album_published, %AlbumPublished{...})
                                  �
                                  > PubSub.broadcast
                                              �
                      �
                      �                       �                       �
            AlbumPublishedHandler   PhotoUploadedHandler   MagicLinkHandler
            (invalidate CDN/cache)  (extract EXIF)         (log events)
```

Implémentation :

```elixir
# 1. Module central pour publier/subscribe
defmodule Portfolio.DomainEvents do
  def publish(event_type, payload) do
    PubSub.broadcast(Portfolio.PubSub, "domain_events:#{event_type}", {event_type, payload})
  end

  def subscribe(event_type) do
    PubSub.subscribe(Portfolio.PubSub, "domain_events:#{event_type}")
  end
end

# 2. Structs d'événements typés
defmodule Portfolio.Photography.Events.AlbumPublished do
  @enforce_keys [:album_id, :title, :slug, :published_at]
  defstruct [:album_id, :title, :slug, :published_at, :user_id]
end

# 3. Handler GenServer supervisé
defmodule Portfolio.Photography.EventHandlers.AlbumPublishedHandler do
  use GenServer

  def init(_) do
    DomainEvents.subscribe(:album_published)
    {:ok, %{}}
  end

  def handle_info({:album_published, event}, state) do
    # Side-effects : invalidate cache, CDN, logs...
    {:noreply, state}
  end
end
```

Avantages :
- Découplage fort : Les contextes ne se connaissent pas mutuellement
- Extensibilité : Ajouter un handler = créer un nouveau GenServer, pas de modification du publisher
- **Open/Closed** : Ouvert � l'extension, fermé � la modification
- Testabilité : Facile de tester publishers et handlers séparément
- Observabilité : Les événements sont visibles dans les logs
- Infrastructure native : Phoenix.PubSub déj� inclus, pas de dépendance externe
- Distribution Erlang : PubSub supporte nativement la distribution entre n�uds (si scale horizontal futur)
- Supervision : Les handlers GenServer sont supervisés et redémarrent automatiquement

Inconvénients :
- Asynchrone : Les side-effects ne sont pas garantis synchrones (peut être un avantage)
- Pas de persistence : Si un handler est down, l'événement est perdu
- Pas de retry automatique : Si un handler échoue, l'événement n'est pas rejoué
- Complexité cognitive : Workflow moins visible qu'appels directs (nécessite de suivre les événements)
- Ordre non garanti : Deux événements successifs peuvent arriver dans le désordre

Effort estimé : Moyen

Risques :
- Événements perdus si handlers down [Probabilité: Faible, Impact: Moyen]
- Difficile de débugger le workflow complet [Probabilité: Moyen, Impact: Faible]

### Option 3: GenStage / Broadway

Description :

Utiliser GenStage (pipelines de traitement) ou Broadway (framework basé sur GenStage avec backpressure) pour créer des pipelines d'événements avec gestion de la charge.

Avantages :
- Gestion de la backpressure (ralentit la production si consommateurs surchargés)
- Batching automatique des événements
- Architecture pipeline claire

Inconvénients :
- Complexité élevée pour les besoins actuels
- Courbe d'apprentissage importante
- Overhead de configuration et maintenance
- Pas nécessaire pour le volume actuel (max 1000 événements/jour)

Effort estimé : Élevé

Risques :
- Over-engineering [Probabilité: Élevée, Impact: Élevé]
- Maintenance complexe pour équipe réduite [Probabilité: Élevée, Impact: Moyen]

### Option 4: Message Broker Externe (RabbitMQ, Redis Streams, Kafka)

Description :

Utiliser un broker de messages externe pour garantir la persistence et la livraison des événements.

Avantages :
- Persistence des événements (pas de perte si handler down)
- Retry automatique en cas d'échec
- Dead-letter queues pour événements non traitables
- Distribution entre instances multiples
- Audit trail des événements

Inconvénients :
- Infrastructure supplémentaire � gérer (RabbitMQ, Redis)
- Coût serveur additionnel (mémoire/CPU)
- Complexité opérationnelle (monitoring, backup, failover)
- Dépendance externe critique
- Overhead réseau entre application et broker
- Over-engineering pour volume actuel (max 1000 événements/jour)

Effort estimé : Élevé

Risques :
- Coût infrastructure trop élevé pour petit serveur Hetzner [Probabilité: Élevée, Impact: Élevé]
- Point de défaillance unique si broker down [Probabilité: Moyen, Impact: Élevé]
- Complexité opérationnelle trop importante [Probabilité: Élevée, Impact: Moyen]

## Décision

L'option choisie est: **Option 2 - Phoenix.PubSub avec Domain Events**

Avec une amélioration critique : **Migration progressive des side-effects de Task.start vers Oban jobs** pour garantir la persistence et le retry en cas d'échec.

### Justification de la décision

**Crit�res de décision:**

- **Alignement avec l'architecture DDD/Clean Architecture:** Excellente séparation des bounded contexts via événements domaine. Les contextes publient des faits métier sans connaître les consommateurs. Respecte le principe de découplage DDD.

- **Impact sur la dette technique:** Réduit significativement la dette technique par rapport aux appels directs. Permet d'ajouter des comportements sans modifier le code existant. Migration vers Oban corrigera la dette actuelle (Task.start non fiable).

- **Maintenabilité:** Tr�s bonne. Ajouter un nouveau comportement = créer un nouveau handler GenServer sans toucher au code publisher. Supervision automatique garantit la résilience.

- **Performance:** Adapté au volume actuel (max 1000 événements/jour). Asynchrone = pas de blocage des opérations métier. Overhead minimal (PubSub in-memory).

- **Sécurité:** Neutre. Les événements ne contiennent pas de données sensibles (pas de tokens, passwords). Les IDs sont suffisants.

- **Coût/Effort:** Optimal. Phoenix.PubSub déj� inclus = zéro coût infrastructure. Effort moyen pour implémenter les handlers mais investissement rentabilisé rapidement.

- **Réversibilité:** Élevée. Possible de migrer vers un broker externe (RabbitMQ, Redis) si nécessaire en gardant la même interface DomainEvents. Seule l'implémentation sous-jacente changerait.

**Décision finale:**

Phoenix.PubSub est le meilleur compromis entre **simplicité, découplage et pragmatisme**. Cette solution :
1. Respecte les principes DDD et Clean Architecture
2. Utilise l'infrastructure native Elixir/Phoenix (pas de dépendance externe)
3. Est adaptée au volume actuel (1000 événements/jour max)
4. Permet une évolution future vers un broker externe si nécessaire

Le principal compromis accepté est l'**absence de persistence native des événements**. Ce compromis est mitigé par :
- La migration progressive vers Oban pour les side-effects critiques (extraction EXIF, invalidation CDN)
- Le faible volume d'événements (perte acceptable en cas de crash)
- La supervision automatique des handlers GenServer

## Conséquences

### Positives

- Découplage fort entre bounded contexts : Photography et Auth ne se connaissent pas, communication via événements uniquement
- Extensibilité sans modification : Nouveau handler = nouveau GenServer, pas de changement dans les publishers
- Observabilité améliorée : Tous les événements métier loggés avec contexte structuré
- Testabilité : Publishers et handlers testables indépendamment
- Audit trail : Historique des événements métier dans les logs (peut être enrichi avec table d'audit)
- Résilience : Handlers supervisés redémarrent automatiquement en cas de crash

### Négatives

- **Événements éphém�res** : Pas de persistence native, événements perdus si handler down (sera corrigé par migration Oban pour side-effects critiques)
- Workflow moins visible : Nécessite de suivre les événements � travers les handlers pour comprendre le flow complet
- Ordre non garanti : Deux événements rapides peuvent arriver dans le désordre aux subscribers (acceptable pour le domaine métier actuel)
- **Pas d'idempotence garantie** : Les handlers doivent être conçus pour être idempotents (� vérifier et documenter)

### Neutres

- **Passage � l'asynchrone** : Les side-effects sont asynchrones, ce qui peut nécessiter des ajustements dans les tests et la logique métier
- Apprentissage GenServer : Nécessite de comprendre le mod�le GenServer/OTP pour maintenir les handlers
- Migration progressive vers Oban : Travail additionnel pour migrer les Task.start existants vers Oban

## Plan d'action

### Phase 1: Audit et Documentation (Priorité: CRITIQUE)

Tâches :
1. Vérifier l'idempotence de tous les event handlers existants :
   - `AlbumPublishedHandler.clear_albums_cache()` � Idempotent
   - `PhotoUploadedHandler.extract_and_store_exif()` � � vérifier (merge ou overwrite ?)
   - `MagicLinkHandler` � Actuellement logging only, idempotent
2. Documenter le comportement en cas d'exception dans un handler (crash � restart � événement perdu)
3. Vérifier comment les handlers sont gérés en environnement test (démarrés ? mockés ?)
4. Documenter la politique de choix des données � inclure dans les événements
5. Clarifier le but de `verified_at` dans `MagicLinkVerified`

Crit�res de succ�s :
- Documentation compl�te du comportement des handlers
- Liste des handlers non-idempotents identifiée
- Guide de test des événements créé

**Estimation:** 1 jour

### Phase 2: Migration Task.start vers Oban (Priorité: HAUTE)

Contexte :

Actuellement, plusieurs handlers utilisent `Task.start/1` pour lancer des side-effects asynchrones. Cette approche présente des risques :
- Pas de persistence : si le processus crash, le travail est perdu
- Pas de retry : échec = échec définitif
- Pas de monitoring : impossible de tracker l'état des tâches

Tâches :
1. Créer les Oban workers pour remplacer les Task.start :
   - `Portfolio.Workers.CDNInvalidationWorker` (remplace Task.start dans AlbumPublishedHandler)
   - `Portfolio.Workers.EXIFExtractionWorker` (remplace Task.start dans PhotoUploadedHandler)
2. Configurer les queues Oban dédiées :
   - Queue `:cdn` avec 2 workers max
   - Queue `:image_processing` avec 3 workers max (déj� existante)
3. Modifier les handlers pour enqueuer des jobs Oban au lieu de Task.start
4. Ajouter retry strategy dans Oban workers (max_attempts: 5, exponential backoff)
5. Tester la résilience (simuler échecs, vérifier retry)

**Exemple de migration:**

Avant (dette technique) :
```elixir
def handle_info({:album_published, event}, state) do
  Task.start(fn -> invalidate_cdn_cache(event) end)  # - Pas de retry
  {:noreply, state}
end
```

Apr�s (avec Oban) :
```elixir
def handle_info({:album_published, event}, state) do
  %{album_slug: event.slug, paths: [...]}
  |> Portfolio.Workers.CDNInvalidationWorker.new()
  |> Oban.insert()  # - Persistence + retry
  {:noreply, state}
end
```

Crit�res de succ�s :
- Zéro Task.start dans les event handlers
- Tous les workers Oban testés avec simulation d'échec
- Métriques Telemetry ajoutées pour tracking des jobs

**Estimation:** 2-3 jours

### Phase 3: Nettoyage des dettes techniques (Priorité: MOYENNE)

Tâches :
1. Supprimer `user_id` optionnel des événements (remplacer par `user_id` obligatoire ou créer événements séparés)
2. Nettoyer les timestamps redondants :
   - `uploaded_at` dans `PhotoUploaded` � Utiliser `inserted_at` d'Ecto ?
   - Garder `published_at`, `verified_at` (timestamps métier importants)
3. Implémenter les side-effects manquants dans `MagicLinkHandler` :
   - Mettre � jour `user.last_login_at` lors de `MagicLinkVerified`
   - Envoyer welcome email pour nouveaux utilisateurs
4. Évaluer la nécessité d'un syst�me de deduplication/event ID

Crit�res de succ�s :
- Structs d'événements cohérents et propres
- MagicLinkHandler fonctionnel avec tous les side-effects

**Estimation:** 2 jours

### Phase 4: Monitoring et Observabilité (Priorité: MOYENNE)

Tâches :
1. Ajouter métriques Telemetry pour les événements :
   - Nombre d'événements publiés par type (counter)
   - Nombre d'événements traités par handler (counter)
   - Durée de traitement dans chaque handler (histogram)
   - Nombre d'erreurs/crashes des handlers (counter)
2. Configurer Telemetry.Metrics dans l'application
3. Documenter le plan de monitoring (dashboard Grafana prévu mais pas encore implémenté)
4. Ajouter structured logging avec corrélation IDs pour suivre un événement de bout en bout

**Exemple Telemetry:**
```elixir
:telemetry.execute(
  [:portfolio, :domain_events, :published],
  %{count: 1},
  %{event_type: :album_published}
)
```

Crit�res de succ�s :
- Métriques Telemetry émises pour tous les événements
- Dashboard basique accessible (Telemetry.Metrics + LiveDashboard)
- Documentation du plan monitoring futur

**Estimation:** 1-2 jours

### Phase 5: Amélioration Future (Optionnel, si besoin)

Contexte :

Si le projet évolue et nécessite plus de garanties (audit trail complet, replay d'événements), envisager ces améliorations :

**Tâches potentielles:**
1. Créer une table `domain_events_log` pour audit trail simple (pas Event Sourcing complet) :
   ```elixir
   create table(:domain_events_log) do
     add :event_type, :string, null: false
     add :event_data, :map, null: false
     add :aggregate_id, :uuid
     add :user_id, :uuid
     timestamps(updated_at: false)
   end
   ```
2. Évaluer la migration vers un message broker externe (RabbitMQ, Redis Streams) si scale horizontal nécessaire
3. Implémenter un syst�me de deduplication avec event IDs si probl�mes identifiés

**Déclencheurs:**
- Volume d'événements > 10 000/jour
- Scale horizontal nécessaire (plusieurs instances)
- Besoin d'audit trail pour compliance
- Probl�mes récurrents d'événements perdus

**Estimation:** � évaluer si nécessaire

### Rollback Plan

Si cette architecture d'événements pose des probl�mes critiques, voici les étapes de rollback :

1. **Identifier les événements problématiques** (logs, Telemetry, monitoring)
2. **Basculer temporairement vers appels directs** dans les contextes concernés
3. **Désactiver les handlers GenServer** en les retirant de la supervision (Application.ex)
4. **Garder les structs d'événements** pour réactivation future
5. Évaluer l'alternative : Oban jobs synchrones, GenStage, ou broker externe

**Probabilité de rollback:** Tr�s faible (architecture éprouvée dans l'écosyst�me Elixir)

## Événements Domaine Actuels

### Photography Context

**AlbumPublished** (`lib/portfolio/photography/events.ex:10`)
```elixir
%AlbumPublished{
  album_id: UUID,        # ID de l'album publié
  title: String,         # Titre de l'album (snapshot au moment de publication)
  slug: String,          # Slug URL (utilisé pour invalidation CDN)
  published_at: DateTime,# Timestamp métier de publication
  user_id: UUID | nil    # ID de l'utilisateur (nil pour syst�me) - DETTE: � rendre obligatoire
}
```
**Handlers:**
- `AlbumPublishedHandler` : Invalide CDN + application cache

**AlbumUnpublished**
```elixir
%AlbumUnpublished{
  album_id: UUID,
  title: String,
  slug: String,
  unpublished_at: DateTime,
  user_id: UUID | nil
}
```
**Handlers:** Idem AlbumPublished (invalidation cache)

**AlbumDeleted**
```elixir
%AlbumDeleted{
  album_id: UUID,
  title: String,
  slug: String,
  deleted_at: DateTime,
  user_id: UUID,         # Obligatoire (toujours un user qui supprime)
  photo_count: integer   # Nombre de photos supprimées avec l'album
}
```
**Handlers:** Logging audit, métriques storage

**PhotoUploaded**
```elixir
%PhotoUploaded{
  photo_id: UUID,
  album_id: UUID,
  file_path: String,     # Chemin storage de la photo
  hash: String,          # SHA256 pour intégrité
  uploaded_at: DateTime  # DETTE: redondant avec inserted_at ?
}
```
**Handlers:**
- `PhotoUploadedHandler` : Extraction EXIF asynchrone (� migrer vers Oban)

**PhotoDeleted**
```elixir
%PhotoDeleted{
  photo_id: UUID,
  album_id: UUID,
  file_path: String,
  deleted_at: DateTime
}
```
**Handlers:** Logging audit, métriques storage

### Auth Context

**UserCreated** (`lib/portfolio/auth/events.ex:15`)
```elixir
%UserCreated{
  user_id: UUID,
  email: String,
  role: atom,            # :admin | :user
  created_at: DateTime
}
```
**Handlers:** Future - Welcome email, analytics

**SessionCreated**
```elixir
%SessionCreated{
  session_id: UUID,
  user_id: UUID,
  email: String,
  created_at: DateTime,
  expires_at: DateTime
}
```
**Handlers:** Logging, métriques login

**MagicLinkRequested**
```elixir
%MagicLinkRequested{
  magic_link_id: UUID,
  email: String,
  token: String,         # Token généré (32 bytes Base64)
  requested_at: DateTime,
  expires_at: DateTime   # requested_at + 15 minutes
}
```
**Handlers:**
- `MagicLinkHandler` : Logging uniquement (email déj� envoyé par MagicLinkAuthService)

**MagicLinkVerified**
```elixir
%MagicLinkVerified{
  magic_link_id: UUID,
  user_id: UUID,
  email: String,
  verified_at: DateTime  # DETTE: clarifier le but (timestamp de vérification du magic link)
}
```
**Handlers:**
- `MagicLinkHandler` : Logging (TODO: update last_login_at, welcome email)

## Politique de Design des Événements

### R�gles de conception

**1. Nommage : Past Tense (Passé)**

Les événements représentent des faits accomplis, pas des commandes futures.
- Correct : `:album_published`, `:photo_uploaded`, `:magic_link_verified`
- Incorrect : `:publish_album`, `:upload_photo`, `:verify_magic_link`

**Justification:** Convention DDD universelle pour distinguer événements (faits) et commandes (intentions).

**2. Contenu : Données essentielles dénormalisées**

Inclure les données qui seront utilisées par la majorité des handlers pour éviter des requêtes DB inutiles.

**R�gles:**
- - Inclure : IDs obligatoires + données souvent utilisées (title, slug, email)
- - Inclure : Snapshots de données mutables au moment de l'événement
- - Exclure : Structures compl�tes, associations, données rarement utilisées
- - Exclure : Données sensibles (passwords, tokens secrets)

**Exemple:** `AlbumPublished` contient `title` et `slug` car utilisés pour logs et invalidation CDN, évitant une requête `AlbumRepository.get(album_id)`.

**3. Immutabilité : @enforce_keys obligatoire**

Tous les champs critiques doivent être marqués avec `@enforce_keys` pour garantir leur présence � la compilation.

```elixir
@enforce_keys [:album_id, :title, :slug, :published_at]
defstruct [:album_id, :title, :slug, :published_at, :user_id]
```

**4. Timestamps : Timestamps métier, pas techniques**

Privilégier les timestamps métier qui ont une signification domaine :
- - `published_at` : Date de publication métier (important pour le domaine)
- - `verified_at` : Date de vérification du magic link
- - `uploaded_at` : Redondant avec `inserted_at` d'Ecto (dette � nettoyer)

**5. Optionnalité : Minimiser les champs optionnels**

Les champs optionnels (`| nil`) doivent être l'exception, pas la r�gle. Si un champ est souvent `nil`, envisager de créer des événements séparés.

**Exemple de dette technique actuelle:**
```elixir
# - user_id optionnel dans plusieurs événements
defstruct [:album_id, :title, :slug, :published_at, :user_id]

# - Mieux : créer deux événements distincts
defmodule AlbumPublishedByUser
defmodule AlbumPublishedBySystem
```

## Références

- [Phoenix.PubSub Documentation](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)
- [Domain Events Pattern - Martin Fowler](https://martinfowler.com/eaaDev/DomainEvent.html)
- [Event-Driven Architecture in Elixir](https://dashbit.co/blog/event-driven-architecture-in-elixir)
- Code source :
  - `lib/portfolio/domain_events.ex` : Module central DomainEvents
  - `lib/portfolio/photography/events.ex` : Événements Photography
  - `lib/portfolio/auth/events.ex` : Événements Auth
  - `lib/portfolio/photography/event_handlers/` : Handlers Photography
  - `lib/portfolio/auth/event_handlers/` : Handlers Auth
  - `lib/portfolio/application.ex:28-30` : Supervision des handlers

## Notes

### Event Sourcing : Pourquoi pas ?

**Event Sourcing complet** (persister tous les événements comme source de vérité) n'a pas été retenu pour ces raisons :

**Inconvénients :**
- Complexité architecture élevée (Event Store, projections, event versioning)
- Courbe d'apprentissage importante pour équipe réduite
- Overhead storage et performance (replay de millions d'événements)
- Over-engineering pour un portfolio photography

**Alternative retenue :**

Si besoin d'audit trail � l'avenir, ajouter une simple table `domain_events_log` pour logger les événements sans adopter Event Sourcing complet. Cela donne un historique des événements sans la complexité d'ES.

### Scale Horizontal : Considérations Futures

**Actuellement:** Pas de scale horizontal prévu. Une seule instance Hetzner.

**Si scale horizontal nécessaire � l'avenir:**

Phoenix.PubSub supporte nativement la distribution entre n�uds Erlang via pg2. Les événements seraient automatiquement distribués entre instances connectées.

**Précautions � prendre:**
- Configurer la distribution Erlang entre n�uds (BEAM cluster)
- Vérifier que tous les n�uds peuvent communiquer (réseau, firewall)
- Tester la résilience en cas de split-brain

**Alternative si distribution Erlang complexe:**
- Migrer vers Redis PubSub (simple, externe)
- Migrer vers RabbitMQ (robuste, persistence)

### Ordre et Idempotence

**Ordre des événements:**

Phoenix.PubSub ne garantit pas l'ordre entre différents subscribers. Si deux événements sont publiés rapidement (ex: `PhotoUploaded` puis `AlbumPublished`), un handler peut les recevoir dans le désordre.

**Impact sur le domaine métier actuel:** Acceptable. Les événements sont indépendants et ne dépendent pas d'un ordre strict.

**Si ordre critique � l'avenir:** Utiliser des event IDs séquentiels ou timestamps pour ordonner côté consumer.

**Idempotence:**

Les handlers doivent être conçus pour être idempotents (traiter deux fois le même événement = même résultat qu'une fois).

**État actuel:**
- `clear_albums_cache()` : Idempotent 
- `invalidate_cdn_cache()` : Idempotent - (invalider deux fois = même résultat)
- `extract_and_store_exif()` : � vérifier (merge ou overwrite des données EXIF ?)

**� documenter:** Vérifier l'idempotence de tous les handlers dans Phase 1.

### Tests et Environnement Test

**� vérifier:**
- Les handlers GenServer sont-ils démarrés en environnement `:test` ?
- Faut-il les mocker pour éviter side-effects (emails, CDN) ?
- Créer des helpers de test pour émettre des événements et vérifier les side-effects

**Documentation � compléter apr�s audit.**

### TODO Issues � Créer

Liste des issues identifiées lors de la création de cet ADR :

1. Migrer tous les event handlers de Task.start vers Oban jobs
2. Supprimer la dette technique `user_id` optionnel dans les événements
3. Corriger AlbumPublishedHandler : utiliser Oban au lieu de Task.start pour invalidation CDN
4. Corriger PhotoUploadedHandler : utiliser Oban au lieu de Task.start pour extraction EXIF
5. Vérifier et documenter le comportement des handlers en cas d'exception (crash + restart)
6. Vérifier si les probl�mes d'ordre des événements peuvent impacter le domaine métier
7. Vérifier l'idempotence de tous les event handlers
8. Évaluer la nécessité d'un syst�me de deduplication/event ID
9. Vérifier et documenter la testabilité des event handlers
10. Vérifier comment les GenServer handlers sont gérés en environnement test
11. Ajouter métriques Telemetry pour les événements domaine (publish, traitement, erreurs)
12. Documenter le plan de monitoring/observabilité (dashboard, Grafana)
13. Nettoyer les timestamps redondants dans les événements (uploaded_at vs inserted_at)
14. Clarifier le but de verified_at dans MagicLinkVerified
15. Implémenter les side-effects manquants dans MagicLinkHandler (last_login_at, welcome email)
