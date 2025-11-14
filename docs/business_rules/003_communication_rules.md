# 003 - Règles Métier Communication Context

Date: 2025-11-12

Ce document détaille les règles métier du Communication Context. Pour vue d'ensemble, consulter docs/ddd/005_communication_context.md.

## Notifications Transactionnelles

### PC-001 : Envoi Asynchrone

**Catégorie** : Règle architecture

**Description** : Notifications envoyées via job Oban pour performance.

**Règle** : Jamais d'envoi email synchrone dans requête HTTP.

**Processus** :
1. Événement métier (AlbumPublié, ProjetPublié)
2. Création Notification (statut pending)
3. Insert job Oban SendNotificationWorker
4. Réponse HTTP immédiate
5. Job traite envoi en arrière-plan

**Avantages** :
- Performance : pas de blocage requête (timeout email)
- Résilience : retry automatique en cas échec
- Scalabilité : traitement parallèle via workers

### PC-002 : Retry Échecs Temporaires

**Catégorie** : Règle résilience

**Description** : Tentatives répétées si erreur temporaire réseau.

**Configuration Oban** :
```
max_attempts: 3
Backoff exponentiel: 15s, 2min, 10min
```

**Erreurs temporaires** :
- Timeout réseau
- Serveur SMTP temporairement indisponible (5xx)
- Rate limit provider email

**Erreurs définitives** (pas de retry) :
- Email invalide (550 Invalid recipient)
- Domaine inexistant

**Statut final** :
- Succès → statut sent
- Échec définitif → statut failed + erreur stockée

### PC-003 : Destinataires Notifications

**Catégorie** : Règle métier

**Description** : Qui reçoit les notifications de publication.

**Règle** :
```
Destinataires = Propriétaire + Tous abonnés actifs
```

**Liste destinataires** :
1. Utilisateur propriétaire (utilisateur_id de l'album/projet)
2. Tous abonnés WHERE statut = 'active'

**Exemple** :
```
Album publié par user@example.com
Abonnés actifs : subscriber1@test.com, subscriber2@test.com

Notifications créées : 3
  1. user@example.com (propriétaire)
  2. subscriber1@test.com
  3. subscriber2@test.com
```

---

## Newsletter

### PC-004 : Contenu Personnalisé

**Catégorie** : Règle métier

**Description** : Newsletter permet contenu libre en plus des albums/projets.

**Composants** :
1. Texte libre personnalisé (Markdown)
2. Sélection albums récents (N-N)
3. Sélection projets récents (N-N)
4. Liens externes artistes

**Format entrée** : Markdown (contenu_personnalise).

**Format sortie** : HTML généré avec template newsletter.html.heex.

**Exemple contenu** :
```markdown
## Actualités du mois

Ce mois-ci j'ai exploré la photographie de rue à Tokyo...

### Albums et projets récents
[Généré automatiquement depuis sélection]

### Artistes à découvrir
- [Photographe inspirant](https://example.com)
```

### PC-005 : Programmation Future

**Catégorie** : Règle fonctionnelle

**Description** : Newsletter peut être programmée à date future.

**États** :
- draft : En cours rédaction
- scheduled : Programmée (job Oban delayed)
- sent : Envoyée

**Processus programmation** :
1. Création newsletter (statut draft)
2. Rédaction contenu + sélection albums/projets
3. Programmation date envoi future
4. Changement statut → scheduled
5. Insert job Oban SendNewsletterWorker avec schedule_in
6. À date prévue → job s'exécute
7. Envoi massif à tous abonnés actifs
8. Changement statut → sent

**Validation date** : date_envoi doit être dans le futur.

### PC-006 : Envoi Massif Optimisé

**Catégorie** : Règle performance

**Description** : Envoi par batch pour éviter timeout et surcharge.

**Règle** : Traitement par groupe de 100 abonnés.

**Processus** :
```
abonnes_actifs = get_all_active_subscribers()
batches = chunk(abonnes_actifs, 100)

Pour chaque batch:
  Pour chaque abonné dans batch:
    generer_email_personnalise(abonné)
    envoyer_email()
  
  attendre 1 seconde (rate limiting provider)
```

**Suivi** :
- Compteur succès/échecs par campagne
- Calcul taux succès
- Stockage dans newsletter.metadata

**Timeout** : Job Oban avec timeout 30 minutes (max 3000 abonnés).

---

## Gestion Abonnés

### PC-007 : Double Opt-In Obligatoire (RGPD)

**Catégorie** : Règle légale RGPD

**Description** : Confirmation par email obligatoire pour activation abonnement.

**Processus** :
1. Utilisateur saisit email formulaire inscription
2. Validation format email
3. Vérification email non déjà abonné
4. Création Abonné (statut pending_confirmation)
5. Génération token_confirmation (UUID v4)
6. Génération token_desinscription (UUID v4)
7. Envoi email confirmation avec lien
8. Utilisateur clique lien /newsletter/confirm?token={token}
9. Validation token existe
10. UPDATE statut → active, date_confirmation = NOW()
11. Page confirmation "Abonnement confirmé"

**Conformité RGPD** :
- Article 6(1)(a) : Consentement explicite
- Preuve consentement : date_confirmation stockée
- Opt-in actif requis (pas de case pré-cochée)

**Email non confirmé** :
- Statut pending_confirmation
- Pas d'envoi notifications/newsletter
- Cleanup automatique après 7 jours (job hebdomadaire)

### PC-008 : Email Unique Abonné

**Catégorie** : Invariant métier

**Description** : Un seul abonnement par adresse email.

**Règle** : Index unique sur colonne email.

**Validation avant insert** :
```
SELECT COUNT(*) FROM abonnes WHERE email = ?
Si count > 0 → Exception "Email déjà inscrit"
```

**Cas réinscription** :
- Si statut = unsubscribed → Permettre réinscription (nouveau token_confirmation)
- Sinon → Message "Email déjà inscrit"

### PC-009 : Désinscription Facile (RGPD)

**Catégorie** : Règle légale RGPD

**Description** : Lien désinscription dans footer de chaque email.

**Règle** : URL désinscription avec token unique.

**Footer email** :
```html
<footer>
  <a href="/newsletter/unsubscribe?token={token_desinscription}">
    Se désinscrire
  </a>
</footer>
```

**Processus désinscription** :
1. Clic lien désinscription
2. Validation token existe
3. UPDATE statut → unsubscribed, date_desinscription = NOW()
4. Page confirmation "Désinscription confirmée"
5. Email conservé (historique, pas suppression)

**Pas de confirmation** : Désinscription immédiate sans validation supplémentaire.

**Réinscription possible** : Utilisateur peut se réinscrire ultérieurement.

### PC-010 : Données Minimales (RGPD)

**Catégorie** : Règle légale RGPD

**Description** : Collecte minimale de données personnelles.

**Données collectées** :
- email (obligatoire, identifiant)
- date_inscription (technique, traçabilité)
- date_confirmation (preuve consentement)
- statut (technique, gestion abonnement)

**Données NON collectées** :
- Nom, prénom
- Adresse IP
- Tracking ouverture emails
- Clics liens (analytics)

**Base légale** : Consentement explicite (Article 6(1)(a) RGPD).

**Finalité** : "Recevoir des notifications lors de la publication de nouveaux albums/projets photographiques".

### PC-011 : Droit Accès et Effacement (RGPD)

**Catégorie** : Règle légale RGPD

**Description** : Utilisateur peut accéder à ses données et demander suppression.

**Droit accès** :
- Email avec lien temporaire /newsletter/my-data?token={token}
- Page affichant : email + date_inscription + date_confirmation + statut
- Format : HTML lisible

**Droit effacement** :
- Lien "Supprimer mes données" sur page my-data
- Confirmation suppression définitive
- DELETE FROM abonnes WHERE id = ?
- Pas de soft delete pour abonnés (données minimales)

**Délai traitement** : Immédiat pour effacement automatique, max 30 jours si demande manuelle.

**Exception conservation** : Aucune (pas d'obligation légale conservation emails abonnés).

### PC-012 : Cleanup Confirmations Non Validées

**Catégorie** : Règle technique

**Description** : Suppression automatique inscriptions non confirmées après 7 jours.

**Règle** : Job hebdomadaire CleanPendingSubscriptionsWorker.

**Processus** :
```
DELETE FROM abonnes
WHERE statut = 'pending_confirmation'
AND inserted_at < NOW() - INTERVAL '7 days'
```

**Justification** :
- Éviter accumulation données inutiles
- Conformité minimisation données (RGPD)
- Libérer emails pour réinscription

---

## Templates Email

### PC-013 : Templates HEEx

**Catégorie** : Règle technique

**Description** : Emails générés via templates HEEx (HTML + Elixir).

**Templates disponibles** :
- album_published.html.heex : Notification album publié
- projet_published.html.heex : Notification projet publié
- newsletter.html.heex : Newsletter périodique
- confirmation_email.html.heex : Confirmation abonnement

**Variables injectées** :
```elixir
%{
  titre: "Mon Album 2024",
  url_public: "https://portfolio.dev/photography/albums/mon-album-2024",
  couverture_url: "https://cdn.portfolio.dev/photos/abc123/large.avif",
  nombre_photos: 15,
  token_desinscription: "uuid-v4"
}
```

**Structure email** :
- Header : Logo, titre
- Body : Contenu personnalisé
- Footer : Lien désinscription, mentions légales

### PC-014 : Responsive Email Design

**Catégorie** : Règle qualité

**Description** : Emails compatibles clients desktop et mobile.

**Contraintes techniques** :
- Inline CSS (clients email ne supportent pas <style>)
- Tables pour layout (flexbox non supporté partout)
- Largeur max 600px
- Images avec alt text (accessibilité)
- Fallback texte si images désactivées

**Test compatibilité** :
- Gmail (web, iOS, Android)
- Outlook (Windows, Mac)
- Apple Mail (iOS, macOS)

---

## Workflows Composites

### Workflow : Publication Album avec Notification

**Description** : Processus complet publication → notification abonnés.

**Étapes** :
1. Photography Context : AlbumPublicationService.publier(album_id)
2. Validation règles métier (PM-005)
3. UPDATE album SET statut = 'published'
4. Émission event AlbumPublié via Phoenix.PubSub
5. Communication Context : AlbumPublishedListener reçoit event
6. Récupération liste destinataires (PC-003)
7. Pour chaque destinataire : Création Notification (statut pending)
8. Insert jobs Oban SendNotificationWorker
9. Job génère HTML depuis template (PC-013)
10. Job envoie email via EmailProvider
11. UPDATE notification SET statut = 'sent', envoye_le = NOW()

**Points échec** :
- Validation album (PM-005) → Exception, rollback
- Échec envoi email temporaire (PC-002) → Retry automatique
- Échec définitif → statut failed, erreur loggée

### Workflow : Newsletter Programmée

**Description** : Processus complet création → programmation → envoi newsletter.

**Étapes** :
1. Admin crée newsletter (statut draft)
2. Rédaction contenu Markdown personnalisé
3. Sélection albums/projets via interface
4. Preview newsletter (génération HTML temporaire)
5. Programmation date envoi (validation future)
6. UPDATE newsletter SET statut = 'scheduled', date_envoi = ?
7. Insert job Oban SendNewsletterWorker avec schedule_in
8. À date prévue : Job s'exécute
9. Récupération abonnés actifs
10. Traitement par batch 100 abonnés (PC-006)
11. Génération HTML personnalisé par abonné (PC-004)
12. Envoi emails via EmailProvider
13. Comptage succès/échecs
14. UPDATE newsletter SET statut = 'sent', metadata = %{succes: X, echecs: Y}

**Annulation programmation** :
- DELETE job Oban si statut = 'scheduled'
- UPDATE newsletter SET statut = 'draft'

## PC-015 : Validation Format Email Abonné

**Catégorie** : Validation Value Object

**Description** : Validation format email identique à User Context (réutilisation règle PU-002).

**Règle** : Regex RFC 5322 simplifiée + normalisation lowercase.

**Validation** :
```
Regex: ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$

Normalisation:
  1. Trim espaces début/fin
  2. Conversion minuscules
  3. Validation regex
```

**Exemples valides** :
- "user@example.com"
- "User.Name+Tag@Example.Co.UK" → normalisé "user.name+tag@example.co.uk"

**Exemples invalides** :
- "user@example" (pas de TLD)
- "@example.com" (pas de local part)
- "user @example.com" (espace)

**Erreurs** :
- Format invalide → "Format email invalide"

**Réutilisation** : Même validation que utilisateurs (cohérence système).

## PC-016 : Rate Limiting Inscription Newsletter

**Catégorie** : Règle sécurité

**Description** : Protection contre spam et abus lors inscriptions newsletter.

**Règle** : Maximum 10 inscriptions par adresse IP par heure.

**Implémentation** :
```
# Clé cache: "newsletter:ratelimit:#{ip_address}"
count = Cachex.get(:portfolio_cache, "newsletter:ratelimit:#{ip}")

Si count >= 10 → Exception "Trop de tentatives. Réessayez dans X minutes."

Cachex.incr(:portfolio_cache, "newsletter:ratelimit:#{ip}")
Cachex.expire(:portfolio_cache, "newsletter:ratelimit:#{ip}", :timer.hours(1))
```

**Fenêtre glissante** : 1 heure avec TTL automatique.

**Message utilisateur** : "Trop de tentatives d'inscription. Veuillez réessayer plus tard."

**Justification** :
- Protection contre bots
- Éviter spam inscriptions massives
- Limiter abus formulaire public

**Exemption** : Pas d'exemption (même admins limités).

## PC-017 : Validation Token Expiration

**Catégorie** : Règle sécurité

**Description** : Tokens confirmation inscription ont durée validité limitée.

**Règle** : Token confirmation expire après 7 jours.

**Processus** :
1. Inscription abonné → token_confirmation généré
2. Email confirmation envoyé
3. Utilisateur clique lien /newsletter/confirm?token={token}
4. Validation token existe
5. Vérification date_inscription < NOW() - 7 jours
6. Si expiré → Message "Lien expiré. Veuillez vous réinscrire."
7. Si valide → Confirmation abonnement

**Calcul expiration** :
```
expires_at = date_inscription + 7 jours
Si NOW() > expires_at → Token expiré
```

**Comportement expiration** :
- Lien expiré → Redirection formulaire inscription
- Invitation réinscription avec même email
- Ancien abonné pending supprimé via PC-012

**Justification** : Limiter validité tokens (sécurité).

## PC-018 : Prévention Spam Notification

**Catégorie** : Règle qualité

**Description** : Limitation fréquence notifications pour éviter spam utilisateurs.

**Règle** : Maximum 1 notification par type par destinataire par jour.

**Implémentation** :
```
# Avant création notification
SELECT COUNT(*) FROM notifications
WHERE destinataire = ?
AND type = ?
AND DATE(envoye_le) = CURRENT_DATE
AND statut = 'sent'

Si count >= 1 → Agrégation au lieu de nouvelle notification
```

**Agrégation** :
```
Si 5 albums publiés même jour:
  Au lieu de 5 notifications séparées
  → 1 notification agrégée "5 nouveaux albums publiés aujourd'hui"

Contenu:
  - Liste albums avec liens
  - Preview première couverture
```

**Exception** : Pas d'agrégation pour newsletter (type différent).

**Justification** :
- Meilleure expérience utilisateur
- Éviter saturation boîte email
- Réduction coûts envoi email

**Configuration** : Limite configurable (actuellement 1/jour/type).

## Documents Liés

- Communication Context : docs/ddd/005_communication_context.md
- Vue d'ensemble : docs/ddd/001_vue_ensemble.md
- Photography Context : docs/ddd/002_photography_context.md
