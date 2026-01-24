# ADR-005: Séparation Communication Context

Statut: Accepté
Date: 2025-11-12

## Contexte

Le portfolio photographique actuel se concentre sur les bounded contexts Photography et Auth. L'évolution future prévoit des fonctionnalités de communication par email (notifications, newsletter) actuellement inexistantes ou embryonnaires.

### Besoins Métier Identifiés

**Notifications transactionnelles** :
- Email propriétaire lors publication album/projet
- Email abonnés lors publication nouveau contenu
- Confirmation abonnement newsletter (double opt-in RGPD)

**Newsletter périodique** :
- Contenu personnalisé (texte libre markdown)
- Sélection albums/projets récents à inclure
- Liens externes vers artistes inspirants
- Envoi massif à abonnés actifs
- Fréquence : Mensuelle (hypothétique)

**Gestion abonnés** :
- Inscription avec confirmation email (double opt-in)
- Désinscription facile (lien dans footer email)
- Données minimales (email + dates) pour conformité RGPD
- Droits accès et effacement (RGPD Article 15, 17)

### Problèmes Architecture Actuelle

**Couplage Photography - Email** :
- Logique envoi emails potentiellement mélangée dans Photography context
- Violation Single Responsibility : Photography ne devrait pas gérer emails
- Difficulté évolution : Ajout newsletter nécessite modification Photography
- Tests complexes : Tester publication album teste aussi envoi email

**Pas de bounded context dédié** :
- Communication est domaine métier à part entière (emails, notifications, abonnés)
- Ubiquitous language différent (Notification, Newsletter, Abonné vs Album, Photo)
- Règles métier spécifiques (double opt-in, RGPD, templates)

**Anticipation croissance** :
- Ajout types notifications (commentaires, favoris, mentions)
- Intégration canaux multiples (email, SMS futur, push notifications)
- Analytics communication (taux ouverture, clics, conversions)
- A/B testing templates emails

### Contraintes Techniques

**Découplage nécessaire** :
- Photography ne doit pas connaître détails Communication
- Communication écoute événements Photography (Publisher-Subscriber)
- Pas de dépendances directes entre contexts

**Performance email** :
- Envoi asynchrone obligatoire (pas de blocage requête HTTP)
- Retry automatique en cas échec temporaire
- Batch processing pour newsletter (envoi par groupe 100 abonnés)

**Conformité RGPD** :
- Double opt-in abonnement (preuve consentement)
- Données minimales (email + dates uniquement)
- Désinscription facile (lien dans footer)
- Droit accès et effacement

## Options Considérées

### Option 1: Communication Context Séparé (Bounded Context)

**Description:**
Création bounded context Communication dédié gérant notifications, newsletter, abonnés. Communication écoute événements Photography via Phoenix.PubSub.

**Architecture:**
```
lib/portfolio/
├── photography/              # Bounded Context Photography
│   ├── album.ex
│   ├── photo.ex
│   └── ...
├── auth/                     # Bounded Context Auth
│   └── ...
├── communication/            # Bounded Context Communication (NOUVEAU)
│   ├── notification.ex      # Aggregate (emails transactionnels)
│   ├── newsletter.ex        # Aggregate (emails périodiques)
│   ├── abonne.ex            # Entity (inscriptions)
│   ├── repositories/
│   │   ├── notification_repository.ex
│   │   ├── newsletter_repository.ex
│   │   └── abonne_repository.ex
│   ├── services/
│   │   ├── notification_service.ex
│   │   ├── newsletter_service.ex
│   │   └── email_sender_service.ex
│   ├── ports/
│   │   └── email_provider.ex  # Port (Swoosh, Mock)
│   ├── event_handlers/
│   │   ├── album_published_listener.ex
│   │   └── projet_published_listener.ex
│   └── templates/
│       ├── album_published.html.heex
│       ├── projet_published.html.heex
│       └── newsletter.html.heex
└── communication.ex          # Context Facade
```

**Communication inter-contexts:**
```elixir
# Photography publie événements
defmodule Portfolio.Photography.Services.AlbumPublicationService do
  def publier(album_id) do
    # ... logique publication
    
    Phoenix.PubSub.broadcast(
      Portfolio.PubSub,
      "photography:events",
      {:album_published, %{
        album_id: album.id,
        titre: album.titre,
        slug: album.slug,
        url_public: "/photography/albums/#{album.slug}",
        couverture_url: couverture_url(album)
      }}
    )
  end
end

# Communication écoute événements
defmodule Portfolio.Communication.EventHandlers.AlbumPublishedListener do
  use GenServer
  
  def init(state) do
    Phoenix.PubSub.subscribe(Portfolio.PubSub, "photography:events")
    {:ok, state}
  end
  
  def handle_info({:album_published, data}, state) do
    Portfolio.Communication.Services.NotificationService.notify_album_published(data)
    {:noreply, state}
  end
end
```

**Avantages:**
- Séparation responsabilités : Photography = photos/albums, Communication = emails
- Découplage complet : Photography ignore existence Communication
- Extensibilité : Ajout canaux (SMS, push) sans toucher Photography
- Testabilité : Tests Photography indépendants Communication
- Ubiquitous language dédié : Notification, Newsletter, Abonné, Template
- Évolution indépendante : Refactoring Communication sans impact Photography
- RGPD centralisé : Logique conformité isolée dans Communication
- Réutilisabilité : Communication réutilisable pour futur Blog context

**Inconvénients:**
- Complexité initiale accrue : Nouveau context, event handlers, PubSub
- Overhead infrastructure : Listeners, workers, topics PubSub
- Latence événements : Asynchrone (délai milliseconde entre publish et handle)
- Debugging complexe : Suivre flux événements multi-contexts

**Effort estimé:** Élevé (nouveau context complet + event handlers)

**Risques:**
- Over-engineering pour features hypothétiques [Probabilité: Moyenne, Impact: Moyen]
  - Mitigation : Implémentation progressive (notifications d'abord, newsletter plus tard)
- Complexité debugging événements [Probabilité: Faible, Impact: Faible]
  - Mitigation : Telemetry events, logging exhaustif
- Latence asynchrone [Probabilité: Faible, Impact: Très faible]
  - Acceptable : Emails asynchrones par nature (Oban workers)

---

### Option 2: Module Communication dans Photography Context

**Description:**
Ajout module `Portfolio.Photography.Communication` dans Photography context. Pas de bounded context séparé.

**Architecture:**
```
lib/portfolio/photography/
├── album.ex
├── photo.ex
├── communication/           # Sous-module Photography
│   ├── notification.ex
│   └── mailer.ex
```

**Avantages:**
- Simplicité : Pas de nouveau context
- Colocalisé : Emails proches logique publication
- Pas de PubSub : Appel direct depuis AlbumPublicationService

**Inconvénients:**
- Violation SRP : Photography responsable photos ET emails
- Couplage fort : Photography connaît détails email
- Tests couplés : Tester publication teste aussi email
- Difficulté évolution : Newsletter nécessite modification Photography
- Pas d'ubiquitous language dédié : Termes email mélangés avec photos
- Non réutilisable : Email logic liée à Photography (pas utilisable pour Blog)

**Effort estimé:** Moyen

**Décision:** Rejeté car viole SRP et couple Photography à infrastructure email.

---

### Option 3: Librairie Partagée (lib/portfolio/shared/mailer)

**Description:**
Module mailer partagé utilisé par tous contexts. Pas de bounded context Communication.

**Architecture:**
```
lib/portfolio/
├── photography/
│   └── ... (appelle Shared.Mailer)
├── auth/
│   └── ... (appelle Shared.Mailer)
├── shared/
│   └── mailer.ex         # Utilitaire partagé
```

**Avantages:**
- Réutilisable : Tous contexts utilisent même mailer
- Pas de duplication : Logique email centralisée

**Inconvénients:**
- Pas de domaine métier : Mailer est utilitaire, pas bounded context
- Pas d'aggregates : Notification, Newsletter, Abonné non modélisés
- Pas d'événements : Couplage fort (appel direct depuis contexts)
- Pas d'ubiquitous language : Termes techniques (send_email) vs métier (Notification)
- RGPD dispersé : Logique conformité éparpillée dans plusieurs contexts

**Effort estimé:** Faible

**Décision:** Rejeté car ne modélise pas domaine Communication et disperse logique RGPD.

---

### Option 4: Inline Email (pas de séparation)

**Description:**
Logique email directement dans AlbumPublicationService. Pas de module dédié.

**Exemple:**
```elixir
defmodule Portfolio.Photography.Services.AlbumPublicationService do
  def publier(album_id) do
    # ... publication
    
    # Email inline
    Swoosh.Email.new()
    |> to("user@example.com")
    |> subject("Nouvel album publié")
    |> html_body("<h1>Album #{album.titre}</h1>")
    |> Portfolio.Mailer.deliver()
  end
end
```

**Avantages:**
- Simplicité maximale : Pas de module séparé
- Colocalisé : Email au moment publication

**Inconvénients:**
- Violation SRP : Service publication fait trop de choses
- Duplication : Logique email répétée (ProjetPublicationService aussi)
- Tests complexes : Mock Swoosh dans tests publication
- Pas testable isolément : Email logic couplée à publication
- Pas de templates : HTML inline non maintenable
- Pas de retry : Échec email = échec publication (mauvais)

**Effort estimé:** Très faible

**Décision:** Rejeté car anti-pattern (violation SRP, duplication, couplage fort).

---

## Décision

L'option choisie est: **Option 1 - Communication Context Séparé (Bounded Context)**

### Justification

**1. Séparation Responsabilités (Critique)**

Communication est domaine métier distinct :
- Ubiquitous language propre : Notification, Newsletter, Abonné, Template, double opt-in
- Règles métier spécifiques : RGPD, confirmation email, désinscription, batch processing
- Cycle de vie indépendant : Newsletter créée sans publication album

Photography ne devrait pas gérer communication email (violation SRP).

**2. Découplage Complet (Très important)**

Publisher-Subscriber via Phoenix.PubSub :
- Photography publie événements (AlbumPublié, ProjetPublié)
- Communication écoute événements
- Pas de dépendance directe : Photography ignore Communication
- Testabilité : Tests Photography sans Communication (mocking PubSub)

Option 2, 3, 4 couplent Photography à email.

**3. Extensibilité Future (Important)**

Communication context facilite évolutions :
- Ajout types notifications (commentaires, favoris, mentions)
- Ajout canaux (SMS, push notifications, webhooks)
- Analytics communication (taux ouverture, clics, A/B testing)
- Templates email avancés (personnalisation, i18n)

Context séparé permet évolution indépendante sans toucher Photography.

**4. Réutilisabilité (Souhaitable)**

Communication réutilisable pour futurs contexts :
- Blog context publiera ArticlePublié → Communication notifie
- Auth context publiera UserSuspended → Communication notifie admin
- Pas de duplication logique email

**5. Conformité RGPD Centralisée (Important)**

Communication centralise logique RGPD :
- Double opt-in abonnement (confirmation email)
- Données minimales (email + dates)
- Désinscription facile (lien footer)
- Droits accès et effacement (Article 15, 17)

RGPD éparpillé dans plusieurs contexts (Option 3) complique audit conformité.

### Implémentation Tactique

**Aggregates Communication:**

```elixir
defmodule Portfolio.Communication.Notification do
  defstruct [:id, :destinataire, :type, :sujet, :contenu, 
             :statut, :envoye_le, :erreur]
  
  # Aggregate Root : Email transactionnel
  def creer(attrs) do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      destinataire: attrs.email,
      type: attrs.type, # :album_publie, :projet_publie
      sujet: attrs.sujet,
      contenu: attrs.contenu,
      statut: :pending
    }
  end
  
  def marquer_envoye(notification) do
    %{notification | statut: :sent, envoye_le: DateTime.utc_now()}
  end
  
  def marquer_echec(notification, erreur) do
    %{notification | statut: :failed, erreur: erreur}
  end
end

defmodule Portfolio.Communication.Newsletter do
  defstruct [:id, :titre, :contenu_personnalise, :albums_inclus, 
             :projets_inclus, :statut, :date_envoi]
  
  # Aggregate Root : Email périodique
  def creer(attrs) do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      titre: attrs.titre,
      contenu_personnalise: attrs.contenu, # Markdown
      albums_inclus: attrs.albums || [],
      projets_inclus: attrs.projets || [],
      statut: :draft
    }
  end
  
  def programmer(newsletter, date_envoi) do
    if DateTime.compare(date_envoi, DateTime.utc_now()) == :gt do
      %{newsletter | statut: :scheduled, date_envoi: date_envoi}
    else
      {:error, :date_passee}
    end
  end
end

defmodule Portfolio.Communication.Abonne do
  defstruct [:id, :email, :statut, :token_confirmation, 
             :token_desinscription, :date_confirmation]
  
  # Entity : Inscription newsletter
  def inscrire(email) do
    %__MODULE__{
      id: Ecto.UUID.generate(),
      email: email,
      statut: :pending_confirmation,
      token_confirmation: Ecto.UUID.generate(),
      token_desinscription: Ecto.UUID.generate()
    }
  end
  
  def confirmer(abonne) do
    %{abonne | statut: :active, date_confirmation: DateTime.utc_now()}
  end
  
  def desinscrire(abonne) do
    %{abonne | statut: :unsubscribed}
  end
end
```

**Event Handlers (Listeners):**

```elixir
defmodule Portfolio.Communication.EventHandlers.AlbumPublishedListener do
  use GenServer
  
  alias Portfolio.Communication.Services.NotificationService
  
  def start_link(_) do
    GenServer.start_link(__MODULE__, %{}, name: __MODULE__)
  end
  
  def init(state) do
    Phoenix.PubSub.subscribe(Portfolio.PubSub, "photography:events")
    {:ok, state}
  end
  
  def handle_info({:album_published, data}, state) do
    # Récupérer destinataires (propriétaire + abonnés actifs)
    destinataires = NotificationService.get_notification_recipients(data.utilisateur_id)
    
    # Créer notifications
    Enum.each(destinataires, fn email ->
      NotificationService.notify_album_published(%{
        email: email,
        album_titre: data.titre,
        album_url: data.url_public,
        couverture_url: data.couverture_url
      })
    end)
    
    {:noreply, state}
  end
  
  def handle_info(_, state), do: {:noreply, state}
end

defmodule Portfolio.Communication.EventHandlers.ProjetPublishedListener do
  use GenServer
  
  # Même logique que AlbumPublishedListener
end
```

**NotificationService (Orchestration):**

```elixir
defmodule Portfolio.Communication.Services.NotificationService do
  alias Portfolio.Communication.{Notification, NotificationRepository}
  alias Portfolio.Communication.Services.EmailSenderService
  
  def notify_album_published(attrs) do
    notification = Notification.creer(%{
      email: attrs.email,
      type: :album_publie,
      sujet: "Nouvel album publié : #{attrs.album_titre}",
      contenu: render_template("album_published", attrs)
    })
    
    NotificationRepository.create(notification)
    
    # Enqueue job Oban
    %{notification_id: notification.id}
    |> Portfolio.Workers.SendNotificationWorker.new()
    |> Oban.insert()
  end
  
  def get_notification_recipients(utilisateur_id) do
    utilisateur = Portfolio.User.get(utilisateur_id)
    abonnes = Portfolio.Communication.AbonneRepository.list_actifs()
    
    [utilisateur.email | Enum.map(abonnes, & &1.email)]
  end
  
  defp render_template(template_name, assigns) do
    Phoenix.View.render_to_string(
      PortfolioWeb.EmailView,
      "#{template_name}.html",
      assigns
    )
  end
end
```

**EmailProvider Port (ACL):**

```elixir
defmodule Portfolio.Communication.Ports.EmailProvider do
  @callback send_email(to, subject, body, opts) :: {:ok, id} | {:error, term()}
end

defmodule Portfolio.Communication.EmailProviders.Swoosh do
  @behaviour Portfolio.Communication.Ports.EmailProvider
  
  def send_email(to, subject, body, _opts) do
    Swoosh.Email.new()
    |> Swoosh.Email.to(to)
    |> Swoosh.Email.subject(subject)
    |> Swoosh.Email.html_body(body)
    |> Portfolio.Mailer.deliver()
  end
end

defmodule Portfolio.Communication.EmailProviders.Mock do
  @behaviour Portfolio.Communication.Ports.EmailProvider
  
  def send_email(_to, _subject, _body, _opts) do
    {:ok, Ecto.UUID.generate()}
  end
end
```

**Configuration:**

```elixir
# config/config.exs
config :portfolio, :email_provider, Portfolio.Communication.EmailProviders.Swoosh

# config/test.exs
config :portfolio, :email_provider, Portfolio.Communication.EmailProviders.Mock
```

**Oban Worker (Envoi Asynchrone):**

```elixir
defmodule Portfolio.Workers.SendNotificationWorker do
  use Oban.Worker, queue: :mailers, max_attempts: 3
  
  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"notification_id" => id}}) do
    notification = NotificationRepository.get(id)
    email_provider = Application.get_env(:portfolio, :email_provider)
    
    case email_provider.send_email(
      notification.destinataire,
      notification.sujet,
      notification.contenu,
      []
    ) do
      {:ok, _} ->
        NotificationRepository.update(notification, %{
          statut: :sent,
          envoye_le: DateTime.utc_now()
        })
        :ok
        
      {:error, reason} ->
        NotificationRepository.update(notification, %{
          statut: :failed,
          erreur: inspect(reason)
        })
        {:error, reason}
    end
  end
end
```

### Trade-offs Acceptés

**Complexité initiale accrue** :
- Coût : Nouveau context complet (aggregates, repos, services, event handlers)
- Justification : Séparation responsabilités, découplage, extensibilité
- Acceptable : Complexité localisée dans Communication, pas d'impact Photography

**Overhead infrastructure PubSub** :
- Coût : Event handlers, topics, latence asynchrone (< 10ms)
- Justification : Découplage complet, testabilité, extensibilité
- Acceptable : Emails asynchrones par nature (Oban workers), latence négligeable

**Implémentation progressive nécessaire** :
- Coût : Context créé en avance (newsletter hypothétique)
- Mitigation : Implémentation par étapes (notifications d'abord, newsletter plus tard)
- Acceptable : Architecture préparée, pas de refactoring majeur futur

**Debugging événements multi-contexts** :
- Coût : Suivre flux Photography → PubSub → Communication complexe
- Mitigation : Telemetry events, logging exhaustif, dashboard Oban
- Acceptable : Debugging événements pattern standard DDD

## Conséquences

### Positives

- **Séparation responsabilités** : Photography = photos/albums, Communication = emails/abonnés
- **Découplage complet** : Photography ignore Communication (Publisher-Subscriber)
- **Testabilité** : Tests Photography indépendants Communication (mocking PubSub)
- **Extensibilité** : Ajout canaux (SMS, push) sans toucher Photography
- **Réutilisabilité** : Communication réutilisable pour Blog context futur
- **Ubiquitous language dédié** : Notification, Newsletter, Abonné, Template
- **Conformité RGPD centralisée** : Logique isolée dans Communication
- **Anti-Corruption Layer** : EmailProvider abstrait Swoosh (testabilité)
- **Évolution indépendante** : Refactoring Communication sans impact Photography
- **Analytics centralisés** : Métriques communication (taux envoi, ouverture) isolées

### Négatives

- **Complexité initiale accrue** : Nouveau context, event handlers, PubSub topics
  - Surveillance : Documentation architecture événements (diagrammes)
  - Gestion : Implémentation progressive (notifications → newsletter)
- **Overhead infrastructure** : GenServers listeners, topics PubSub, Oban queues
  - Surveillance : Monitoring PubSub (backlog messages, latence)
  - Gestion : Configuration PubSub adaptée (buffer size, timeouts)
- **Latence asynchrone** : Délai publish → handle < 10ms
  - Acceptable : Emails asynchrones par nature (Oban workers)
- **Debugging événements** : Suivre flux multi-contexts complexe
  - Surveillance : Telemetry events, logging exhaustif
  - Gestion : Dashboard visualisation flux événements (futur)
- **Over-engineering possible** : Newsletter hypothétique (pas confirmée)
  - Mitigation : Implémentation newsletter uniquement si besoin confirmé
  - Acceptable : Architecture préparée, pas de refactoring majeur

### Neutres

- **Event handlers GenServers** : Processus dédiés écoutant PubSub
  - Infrastructure standard Elixir/Phoenix (supervision tree)
- **Oban workers mailers** : Queue dédiée (séparation mailers vs default)
  - Performance : Pas de blocage queue default par envois emails
- **Templates HEEx** : Génération HTML emails
  - Maintenabilité : Templates versionnés, pas de HTML inline

## Plan d'Action

1. **Phase 1: Infrastructure Base**
   - Création lib/portfolio/communication/
   - Schéma DB (notifications, newsletters, abonnes)
   - Configuration PubSub topics (photography:events)

2. **Phase 2: Aggregates et Repositories**
   - Notification (Aggregate Root)
   - Newsletter (Aggregate Root)
   - Abonne (Entity)
   - NotificationRepository, NewsletterRepository, AbonnéRepository

3. **Phase 3: Event Handlers (Listeners)**
   - AlbumPublishedListener (subscription photography:events)
   - ProjetPublishedListener
   - Démarrage listeners dans supervision tree

4. **Phase 4: Services**
   - NotificationService (création notifications + enqueue Oban)
   - NewsletterService (création newsletter + programmation envoi)
   - EmailSenderService (envoi via EmailProvider)

5. **Phase 5: EmailProvider Port (ACL)**
   - Interface EmailProvider (behaviour)
   - SwooshEmailProvider (production)
   - MockEmailProvider (tests)
   - Configuration environment-specific

6. **Phase 6: Oban Workers**
   - SendNotificationWorker (envoi notifications)
   - SendNewsletterWorker (envoi newsletter par batch)
   - Configuration queue :mailers (séparée de :default)

7. **Phase 7: Templates Email**
   - album_published.html.heex
   - projet_published.html.heex
   - newsletter.html.heex
   - confirmation_email.html.heex (double opt-in)

8. **Phase 8: LiveView Admin**
   - NotificationIndex (historique notifications)
   - NewsletterIndex (gestion newsletters)
   - AbonnéIndex (gestion abonnés)

9. **Phase 9: Tests Exhaustifs**
   - Tests event handlers (AlbumPublishedListener)
   - Tests services (NotificationService)
   - Tests workers (SendNotificationWorker avec MockEmailProvider)
   - Tests RGPD (double opt-in, désinscription)
   - Tests performance (envoi batch newsletter)

10. **Phase 10: Documentation**
    - docs/ddd/005_communication_context.md
    - docs/business_rules/003_communication_rules.md
    - Diagrammes flux événements (Photography → Communication)

**Critères de succès:**
- Communication context opérationnel (notifications album/projet)
- Découplage complet : Photography ignore Communication
- Tests Photography sans Communication (mocking PubSub)
- Envoi asynchrone fiable (Oban workers)
- Conformité RGPD (double opt-in, désinscription)
- Newsletter fonctionnelle (création, programmation, envoi batch)
- Documentation complète (architecture, événements, RGPD)

**Rollback plan:**

Si Communication context inadapté :
1. Identifier pain point : Complexité ? Performance ? Over-engineering ?
2. Option A : Simplifier Communication (supprimer newsletter, garder notifications)
   - Réduire scope context (notifications uniquement)
   - Garder découplage Photography
3. Option B : Fusionner dans Photography (module Photography.Communication)
   - Supprimer event handlers
   - Appel direct depuis AlbumPublicationService
   - Perte découplage, mais réduction complexité
4. Option C : Librairie partagée (Shared.Mailer)
   - Supprimer context Communication
   - Utilitaire email simple sans aggregates
5. Effort rollback : 2-3 semaines (suppression context, refactor appels)

## Références

- [Domain Events - Vaughn Vernon](https://vaughnvernon.com/domain-events/)
- [Publisher-Subscriber Pattern](https://en.wikipedia.org/wiki/Publish%E2%80%93subscribe_pattern)
- [Phoenix PubSub](https://hexdocs.pm/phoenix_pubsub/Phoenix.PubSub.html)
- [Swoosh Email Library](https://hexdocs.pm/swoosh/Swoosh.html)
- [GDPR Article 15 (Right to Access)](https://gdpr-info.eu/art-15-gdpr/)
- [GDPR Article 17 (Right to Erasure)](https://gdpr-info.eu/art-17-gdpr/)

Documentation projet :
- docs/ddd/005_communication_context.md
- docs/business_rules/003_communication_rules.md

ADRs liés :
- ADR-003 : Adoption Domain-Driven Design (Bounded Contexts)
- ADR-041 : Oban Background Jobs
- ADR-032 : Repository Pattern Data Access

## Notes

### État Actuel (Novembre 2025)

**Implémentation:**
- 🔄 Phase 1 : Infrastructure base (en cours documentation)
- ⏳ Phases 2-10 : À implémenter

**Communication context choisi car:**
- Séparation responsabilités (Photography ≠ emails)
- Découplage complet (Publisher-Subscriber)
- Extensibilité future (SMS, push, analytics)
- Conformité RGPD centralisée

**Alternatives rejetées:**
- Module dans Photography : Violation SRP, couplage fort
- Librairie partagée : Pas de domaine métier, RGPD dispersé
- Inline email : Anti-pattern (duplication, couplage)

### Lessons Learned (À documenter après implémentation)

**Anticipations:**
- PubSub suffisant (pas besoin message queue externe type RabbitMQ)
- Latence asynchrone négligeable (< 10ms publish → handle)
- EmailProvider ACL utile (testabilité avec MockEmailProvider)
- Oban workers fiables (retry automatique, dead letter queue)

**À surveiller:**
- Performance PubSub (backlog messages si listeners lents)
- Taux succès envoi emails (provider limits, bounces)
- Volumétrie abonnés (batch size newsletter adaptée ?)
- Conformité RGPD (audit régulier double opt-in, désinscription)

**Évolutions futures:**
- Analytics communication (taux ouverture, clics) via tracking pixels
- A/B testing templates emails (variation sujet, contenu)
- Canaux supplémentaires (SMS via Twilio, push notifications)
- Intégration CRM (Hubspot, Mailchimp) pour marketing automation

---

**Participants à la décision:**
- Thibault San - Développeur Solo

**Révisé par:**
- Thibault San - 2025-11-12
