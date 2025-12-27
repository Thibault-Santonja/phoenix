# ADR-020: Authentification Passwordless par Magic Link

Statut: Accepté
Date: 2025-07

## Contexte

Le syst�me d'authentification est un composant critique de toute application web. Plusieurs approches existent pour gérer l'authentification des utilisateurs, chacune avec ses avantages et inconvénients en termes de sécurité, d'expérience utilisateur et de complexité d'implémentation.

Les principales options considérées étaient :
- Authentification traditionnelle par mot de passe (avec bcrypt ou argon2)
- Authentification passwordless par magic link envoyé par email
- OAuth avec providers externes (Google, GitHub, etc.)
- Passkeys (WebAuthn)

Pour ce projet portfolio personnel avec un nombre d'utilisateurs limité et un besoin de simplicité, le choix s'est porté sur une authentification passwordless par magic link.

## Décision

Le syst�me d'authentification repose exclusivement sur l'envoi de magic links par email. L'utilisateur saisit son adresse email, reçoit un lien temporaire par email, et clique sur ce lien pour s'authentifier.

### Architecture technique

#### 1. Schema MagicLink

Le schéma `Portfolio.Auth.MagicLink` modélise les liens d'authentification temporaires :

```elixir
schema "magic_links" do
  belongs_to :user, User
  field :token, :string
  field :expires_at, :utc_datetime
  field :used_at, :utc_datetime
  timestamps(type: :utc_datetime, updated_at: false)
end
```

Fonctions principales :
- `expired?/1` : vérifie si le lien a expiré (15 minutes)
- `used?/1` : vérifie si le lien a déj� été utilisé
- `valid?/1` : combine les deux vérifications précédentes

#### 2. MagicLinkService

Le service `Portfolio.Auth.MagicLinkService` g�re le cycle de vie des magic links :

- `request_magic_link/1` : création d'un nouveau magic link
- `verify_magic_link/1` : vérification et consommation d'un token
- `delete_expired_magic_links/0` : nettoyage des liens expirés

#### 3. MagicLinkAuthService

Le service d'orchestration `Portfolio.Auth.Services.MagicLinkAuthService` coordonne :
- La génération du token sécurisé
- La création du magic link en base
- L'envoi de l'email via `Portfolio.Email.send_magic_link_email/2`
- La génération de l'URL compl�te avec le token

#### 4. Génération de token

Le token utilise une génération cryptographiquement sécurisée :

```elixir
defp generate_token do
  :crypto.strong_rand_bytes(32) |> Base.url_encode64(padding: false)
end
```

Caractéristiques :
- 32 octets de données aléatoires cryptographiquement sûres
- Encodage Base64 URL-safe sans padding
- Résistant aux attaques par force brute (2^256 possibilités)

#### 5. Rate Limiting

Le module `Portfolio.RateLimiter` prot�ge le syst�me contre les abus via la biblioth�que Hammer avec backend ETS :

```elixir
@rate_limits %{
  magic_link_request: {5, :timer.hours(1)},
  magic_link_verify: {10, :timer.minutes(5)}
}
```

Limites appliquées :
- Demande de magic link : 5 tentatives par heure par email
- Vérification de token : 10 tentatives toutes les 5 minutes

#### 6. Configuration temporelle

- Expiration des magic links : 15 minutes apr�s création
- Délai basé sur l'expérience pratique d'utilisation d'autres syst�mes similaires
- Compromis entre sécurité et expérience utilisateur

### Flux d'authentification

1. L'utilisateur saisit son email sur la page de connexion
2. Le syst�me vérifie le rate limiting
3. Un magic link est créé avec un token unique
4. Un email est envoyé avec l'URL d'authentification
5. L'utilisateur clique sur le lien dans son email
6. Le syst�me vérifie la validité du token (existence, expiration, non-utilisation)
7. Le magic link est marqué comme utilisé
8. Une session utilisateur est créée

## Risques identifiés et mesures d'atténuation

### 1. Token transmis en GET (URGENT)

Risque : Le token est actuellement transmis dans l'URL via une requête GET. Cela expose le token dans :
- Les logs serveur (Nginx, Phoenix Logger)
- L'historique de navigation du navigateur
- Les outils d'analytics (Google Analytics, etc.)
- Le header Referer si l'utilisateur navigue ailleurs apr�s connexion

Atténuation actuelle :
- Token � usage unique (marqué comme utilisé apr�s consommation)
- Expiration courte (15 minutes)
- Rate limiting sur les tentatives de vérification

Plan d'amélioration :
- Migration vers un flow POST : le lien pointe vers une page intermédiaire qui soumet automatiquement le token en POST
- Alternative : stockage du token dans sessionStorage et envoi via JavaScript
- Priorité : moyenne (non urgent mais recommandé � moyen terme)

### 2. Transmission email en clair

Risque : Si le serveur SMTP n'utilise pas TLS, le contenu de l'email (incluant le magic link) peut être intercepté en transit.

Recommandations :
- Vérifier que la configuration SMTP utilise TLS/STARTTLS
- Documenter dans la configuration de production l'obligation d'utiliser un provider SMTP avec chiffrement
- Considérer l'utilisation de services d'email transactionnel (SendGrid, Mailgun, etc.) qui appliquent TLS par défaut

### 3. Nettoyage des magic links expirés

Probl�me identifié : Aucun processus automatique de nettoyage n'est actuellement configuré. La table `magic_links` croît indéfiniment.

Solution � implémenter :
- Ajouter `Oban.Plugins.Cron` dans la configuration Oban
- Créer un worker `CleanupExpiredMagicLinksWorker` exécuté quotidiennement
- Appel � `MagicLinkService.delete_expired_magic_links/0`

Configuration requise dans `config/config.exs` :

```elixir
{Oban.Plugins.Cron,
  crontab: [
    {"0 2 * * *", Portfolio.Workers.CleanupExpiredMagicLinksWorker}
  ]
}
```

Implémentation du worker :

```elixir
defmodule Portfolio.Workers.CleanupExpiredMagicLinksWorker do
  use Oban.Worker, queue: :default

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    {count, _} = MagicLinkService.delete_expired_magic_links()
    Logger.info("Cleaned up expired magic links", count: count)
    :ok
  end
end
```

Priorité : haute (� implémenter rapidement pour éviter la croissance illimitée de la table)

### 4. Sécurité email vs mot de passe

Observation : L'authentification repose enti�rement sur la sécurité du compte email de l'utilisateur.

Analyse comparative :

Avantages vs mot de passe :
- Pas de réutilisation de mot de passe faible
- Pas de stockage de hash de mot de passe (supprime une surface d'attaque)
- Simplicité pour l'utilisateur (pas de mémorisation)

Inconvénients vs mot de passe :
- Dépendance totale � la sécurité du compte email
- Vulnérabilité si le compte email est compromis
- Pas d'authentification possible si l'email est temporairement inaccessible

Contexte d'acceptabilité :
- Pour un portfolio personnel avec utilisateurs limités et de confiance
- Les utilisateurs sont présumés avoir des comptes email sécurisés (2FA recommandé)
- Le niveau de sécurité requis est adapté au risque métier

## Alternatives considérées

### Authentification par mot de passe (bcrypt/argon2)

Avantages :
- Indépendance du compte email
- Standard éprouvé
- Authentification hors ligne possible

Inconvénients :
- Complexité accrue (gestion des mots de passe, reset, force des mots de passe)
- Risque de mots de passe faibles
- Nécessite une UI supplémentaire (formulaires, validation, reset)

Rejet : jugé trop complexe pour le besoin actuel d'un portfolio personnel.

### OAuth (Google, GitHub, etc.)

Avantages :
- Délégation de l'authentification � des providers fiables
- Expérience utilisateur fluide
- Sécurité renforcée (2FA géré par le provider)

Inconvénients :
- Dépendance � des services externes
- Configuration et maintenance des applications OAuth
- Expérience utilisateur variable selon les providers

Statut : considéré comme évolution future si le nombre d'utilisateurs croît.

### Passkeys (WebAuthn)

Avantages :
- Sécurité maximale (cryptographie asymétrique, résistance au phishing)
- Expérience utilisateur moderne
- Standard FIDO2

Inconvénients :
- Complexité d'implémentation
- Support navigateur/dispositif variable
- Nécessite un fallback pour dispositifs non compatibles

Statut : considéré comme évolution future pour améliorer la sécurité, mais jugé trop complexe pour la premi�re version.

## Conséquences

### Positives

- Simplicité d'implémentation et de maintenance
- Expérience utilisateur fluide (pas de mémorisation de mot de passe)
- Réduction de la surface d'attaque (pas de hash de mot de passe � protéger)
- Code bien structuré avec séparation des responsabilités

### Négatives

- Dépendance totale � la sécurité des comptes email
- Nécessite un serveur SMTP fonctionnel en production
- Impossible de s'authentifier sans acc�s � l'email
- Token actuellement transmis en GET (plan de migration identifié)
- Absence de nettoyage automatique des magic links expirés (solution identifiée)

### Neutres

- Approprié pour un portfolio personnel avec utilisateurs limités
- Évolutivité possible vers OAuth ou Passkeys si nécessaire � l'avenir
- Nécessite une éducation des utilisateurs sur la sécurité de leur compte email

## Migration et évolutions futures

### Court terme (priorité haute)
1. Implémenter le nettoyage automatique des magic links expirés via Oban Cron
2. Vérifier la configuration TLS du serveur SMTP en production

### Moyen terme (priorité moyenne)
1. Migrer vers un flow POST pour la transmission du token
2. Ajouter des logs détaillés des tentatives d'authentification pour monitoring

### Long terme (évolutions futures)
1. Ajouter OAuth comme option d'authentification alternative
2. Évaluer l'implémentation de Passkeys pour les utilisateurs avancés
3. Implémenter un syst�me de notification des connexions suspectes

## Références

- Documentation Hammer : https://github.com/ExHammer/hammer
- Documentation Oban : https://hexdocs.pm/oban/
- Guide OWASP Authentication : https://cheatsheetseries.owasp.org/cheatsheets/Authentication_Cheat_Sheet.html
- Fichiers concernés :
  - `lib/portfolio/auth/magic_link.ex`
  - `lib/portfolio/auth/magic_link_service.ex`
  - `lib/portfolio/services/auth/magic_link_auth_service.ex`
  - `lib/portfolio/rate_limiter.ex`
  - `lib/portfolio_web/controllers/auth_controller.ex`
