# 002 - Règles Métier Auth et User Contexts

Date: 2025-11-12

Ce document détaille les règles métier des contextes Auth et User. Pour vue d'ensemble, consulter docs/ddd/003_auth_context.md et docs/ddd/004_user_context.md.

## Auth Context

### PA-001 : Rate Limiting MagicLink

**Catégorie** : Règle sécurité

**Description** : Protection contre spam et attaques brute-force sur génération de liens de connexion.

**Règle** : Maximum 5 MagicLinks par adresse email par heure.

**Implémentation** :
```
SELECT COUNT(*) FROM magic_links
WHERE email = ? AND inserted_at >= NOW() - INTERVAL '1 hour'

Si count >= 5 → Exception "Limite atteinte. Réessayez dans X minutes."
```

**Fenêtre glissante** : 1 heure depuis création du lien le plus ancien.

**Message utilisateur** : "Trop de demandes. Veuillez réessayer dans X minutes."

**Référence** : ADR 020 - Magic Link Passwordless Auth

### PA-002 : Expiration MagicLink 15 Minutes

**Catégorie** : Règle sécurité

**Description** : Limitation temporelle validité lien de connexion.

**Règle** : MagicLink expire 15 minutes après création.

**Calcul** :
```
expires_at = inserted_at + 15 minutes
Validation : NOW() < expires_at
```

**Comportement expiration** :
- Clic lien expiré → Message "Lien expiré. Demandez un nouveau lien."
- Redirection formulaire demande nouveau lien

**Justification** : Équilibre sécurité (courte validité) et UX (temps suffisant).

### PA-003 : Usage Unique MagicLink

**Catégorie** : Invariant sécurité

**Description** : Un token de connexion ne peut être utilisé qu'une seule fois.

**Règle** : Colonne used (boolean), validation used = false avant acceptation.

**Processus** :
1. Validation token existe
2. Validation NOT expired
3. Validation used = false
4. Création session
5. UPDATE used = true

**Protection replay attack** : Token invalidé immédiatement après usage.

**Tentative réutilisation** : Erreur "Lien déjà utilisé. Demandez un nouveau lien."

### PA-004 : Token Unique

**Catégorie** : Invariant technique

**Description** : Chaque MagicLink possède un token unique non prédictible.

**Règle** : Génération UUID v4 (128 bits entropie).

**Implémentation** :
- Génération : Ecto.UUID.generate()
- Index unique sur colonne token (base de données)
- Probabilité collision : négligeable (2^64 tokens générés avant 50% collision)

**Sécurité** : Impossible de deviner token valide par brute-force.

### PA-005 : Expiration Session 30 Jours

**Catégorie** : Règle sécurité

**Description** : Limitation temporelle session authentifiée.

**Règle** : Session expire 30 jours après création.

**Calcul** :
```
expires_at = inserted_at + 30 jours
Validation : NOW() < expires_at
```

**Cleanup automatique** :
- Job Oban quotidien : CleanExpiredSessionsWorker
- Suppression sessions WHERE expires_at < NOW()

**Renouvellement** : Pas de renouvellement automatique. Utilisateur doit se reconnecter après 30 jours.

### PA-006 : Token Session Unique

**Catégorie** : Invariant technique

**Description** : Chaque session possède un token unique non prédictible.

**Règle** : Génération UUID v4, index unique.

**Stockage** : Cookie HTTP-only, Secure, SameSite=Lax.

**Révocation** : DELETE session rend token invalide immédiatement.

### PA-007 : Révocation Cascade Sessions

**Catégorie** : Règle sécurité

**Description** : Suspension utilisateur entraîne révocation de toutes ses sessions actives.

**Règle** :
```
DELETE FROM sessions WHERE utilisateur_id = ?
```

**Déclenchement** : Event UtilisateurSuspendu depuis User Context.

**Conséquence** : Déconnexion immédiate sur tous appareils.

**Cas usage** : Compromission compte, suspension administrative.

---

## User Context

### PU-001 : Email Unique

**Catégorie** : Invariant métier

**Description** : Un utilisateur par adresse email.

**Règle** : Index unique sur colonne email.

**Validation avant insert** :
```
SELECT COUNT(*) FROM utilisateurs WHERE email = ?
Si count > 0 → Exception "Email déjà utilisé"
```

**Normalisation** : Email converti en minuscules avant stockage.

**Message erreur** : "Un compte existe déjà avec cet email."

### PU-002 : Format Email Valide

**Catégorie** : Validation technique

**Description** : Email doit respecter format RFC 5322 (simplifié).

**Règle** : Regex basique validation.

**Validation** :
```
Regex: ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$
Exemples valides:
  - user@example.com
  - user.name+tag@example.co.uk

Exemples invalides:
  - user@example (pas de TLD)
  - @example.com (pas de local part)
  - user @example.com (espace)
```

**Normalisation** : Conversion minuscules, trim espaces.

### PU-003 : Rôle Par Défaut

**Catégorie** : Règle métier

**Description** : Nouvel utilisateur créé avec rôle user par défaut.

**Règle** :
```
role = 'user' (sauf si explicitement spécifié 'admin')
```

**Changement rôle** : Seul admin peut promouvoir user → admin.

**Permissions** :
- user : Lecture seule contenus publiés
- admin : Toutes permissions (CRUD albums, projets, utilisateurs)

**Référence** : ADR 021 - Role-Based Access Control

### PU-004 : Statut Par Défaut

**Catégorie** : Règle métier

**Description** : Nouvel utilisateur créé avec statut active.

**Règle** :
```
statut = 'active'
```

**Changement statut** : Seul admin peut suspendre utilisateur.

**États** :
- active : Peut se connecter et utiliser système
- suspended : Connexion bloquée, sessions révoquées

### PU-005 : Suspension Révoque Sessions

**Catégorie** : Règle sécurité

**Description** : Changement statut active → suspended déclenche révocation sessions.

**Processus** :
1. UPDATE utilisateurs SET statut = 'suspended'
2. Émission event UtilisateurSuspendu
3. Auth Context écoute event
4. DELETE FROM sessions WHERE utilisateur_id = ?

**Conséquence** : Déconnexion immédiate, impossible se reconnecter.

**Cas usage** : Suspension administrative, compromission compte.

### PU-006 : Admin Unique

**Catégorie** : Règle protection

**Description** : Au moins un admin doit exister dans le système.

**Règle** : Impossible de supprimer ou rétrograder dernier admin.

**Validation avant suppression** :
```
SELECT COUNT(*) FROM utilisateurs WHERE role = 'admin'
Si count = 1 ET utilisateur.role = 'admin' 
  → Exception "Impossible de supprimer dernier admin"
```

**Bootstrap** : Admin par défaut créé lors initialisation système.

**Message erreur** : "Impossible de supprimer le dernier administrateur du système."

---

## Workflows Composites

### Workflow : Authentification Complète

**Description** : Processus complet connexion utilisateur.

**Étapes** :
1. Utilisateur saisit email
2. Validation PA-001 (rate limiting)
3. Validation PU-002 (format email)
4. Génération MagicLink (PA-004 token unique)
5. Calcul expiration +15min (PA-002)
6. Envoi email lien (Communication Context)
7. Utilisateur clique lien
8. Validation token existe
9. Validation PA-002 (expiration)
10. Validation PA-003 (usage unique)
11. Récupération utilisateur par email (PU-001)
12. Validation PU-004 (statut active)
13. Création session (PA-006 token unique)
14. Calcul expiration +30j (PA-005)
15. UPDATE magic_link SET used = true
16. Redirection dashboard authentifié

**Points échec** :
- Email invalide (PU-002) → Erreur formulaire
- Rate limit (PA-001) → Attente X minutes
- Token expiré (PA-002) → Demander nouveau lien
- Token utilisé (PA-003) → Demander nouveau lien
- Utilisateur suspendu (PU-004) → Erreur "Compte suspendu"

### Workflow : Suspension Utilisateur

**Description** : Processus complet suspension compte.

**Étapes** :
1. Admin demande suspension utilisateur
2. Validation demandeur = admin (PU-003)
3. Validation utilisateur cible ≠ dernier admin (PU-006)
4. UPDATE utilisateurs SET statut = 'suspended'
5. Émission event UtilisateurSuspendu (PU-005)
6. Auth Context écoute event
7. Révocation sessions (PA-007)
8. Confirmation succès

**Conséquences** :
- Sessions révoquées immédiatement
- Impossible se reconnecter
- MagicLinks existants invalidés (validation statut lors usage)

## PA-008 : Cleanup MagicLinks Expirés

**Catégorie** : Règle maintenance

**Description** : Suppression automatique MagicLinks expirés pour éviter accumulation données.

**Règle** : Job quotidien supprime MagicLinks WHERE expires_at < NOW().

**Processus** :
```
# Job CleanExpiredMagicLinksWorker (cron: daily, 2h)
DELETE FROM magic_links WHERE expires_at < NOW()
```

**Justification** :
- Éviter accumulation données inutiles
- Conformité minimisation données (RGPD)
- Libérer espace base de données

**Timing** : Exécution 2h du matin (faible charge système).

## PA-009 : Metadata Session

**Catégorie** : Règle sécurité

**Description** : Capture metadata lors création session pour audit et détection activité suspecte.

**Données capturées** :
- ip_address : Adresse IP utilisateur
- user_agent : Navigateur et système exploitation

**Stockage** : Colonne metadata (JSONB).

**Exemple** :
```json
{
  "ip_address": "192.168.1.100",
  "user_agent": "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)..."
}
```

**Utilisation** :
- Audit : Traçabilité connexions
- Sécurité : Détection connexions depuis IP/appareil inhabituel
- Support : Diagnostic problèmes utilisateur

**Règle** : Metadata obligatoire lors création session.

**Validation** : ip_address et user_agent doivent être présents.

## PA-010 : Validation Email Existence Utilisateur

**Catégorie** : Règle sécurité/UX

**Description** : MagicLink ne peut être créé pour email sans compte associé.

**Règle** : Vérification EXISTS(utilisateurs WHERE email = ?) avant création MagicLink.

**Processus** :
1. Utilisateur saisit email formulaire connexion
2. Validation format email (PU-002)
3. Recherche utilisateur par email
4. Si utilisateur trouvé → Création MagicLink + envoi email
5. Si utilisateur inexistant → Erreur "Aucun compte associé à cet email"

**Message erreur** : "Aucun compte n'existe avec cet email."

**Sécurité** : Révèle existence compte (enumeration attack possible).

**Alternative sécurisée** : Message générique "Si compte existe, email envoyé" (masque existence compte).

**Choix actuel** : Message explicite pour meilleure UX (portfolio personnel, risque enumeration acceptable).

## PA-011 : Limite Session Par Device

**Catégorie** : Règle sécurité

**Description** : Un utilisateur ne peut avoir qu'une seule session active par device/browser.

**Règle** : Création nouvelle session révoque sessions existantes même device.

**Identification device** :
```
device_fingerprint = hash(user_agent + ip_address_prefix)
# IP prefix: 192.168.1.xxx → 192.168.1.0 (ignorer derniers octets)
```

**Processus création session** :
```
1. Validation MagicLink (PA-003)
2. Calcul device_fingerprint depuis metadata (PA-009)
3. Recherche sessions actives utilisateur avec même fingerprint
4. Révocation sessions existantes même device
   DELETE FROM sessions 
   WHERE utilisateur_id = ? 
   AND metadata->>'device_fingerprint' = ?
   AND expires_at > NOW()
5. Création nouvelle session avec metadata enrichie
```

**Métadata session** :
```json
{
  "ip_address": "192.168.1.100",
  "user_agent": "Mozilla/5.0...",
  "device_fingerprint": "a3f5c9..."
}
```

**Comportement multi-device** :
- Laptop + Mobile = 2 sessions actives autorisées (devices différents)
- Chrome + Firefox même machine = 2 sessions (user-agents différents)
- Reconnexion Chrome laptop = révoque ancienne session Chrome laptop

**Justification** :
- Sécurité : Limite sessions compromises
- Détection vol session : Connexion nouvelle localisation révoque ancienne
- Balance sécurité/UX : Multi-device OK, pas sessions infinies

**Exemption** : Pas d'exemption admin (même règle tous utilisateurs).

---

## PU-007 : Bootstrap Admin Initial

**Catégorie** : Règle initialisation

**Description** : Création admin par défaut lors initialisation système.

**Règle** : Mix task Portfolio.Bootstrap.create_admin crée premier admin.

**Configuration** : Email défini dans config.exs
```elixir
config :portfolio, :admin_email, "admin@example.com"
```

**Processus** :
```
mix portfolio.bootstrap.create_admin
  1. Vérifier COUNT(utilisateurs WHERE role = 'admin')
  2. Si count = 0 → Créer admin
     - email: config :admin_email
     - nom: "Admin"
     - role: admin
     - statut: active
  3. Si count > 0 → Message "Admin déjà existant"
```

**Idempotence** : Task peut être exécutée plusieurs fois sans erreur.

**Première connexion** : Admin reçoit MagicLink par email pour première connexion.

## PU-008 : Validation Nom Utilisateur

**Catégorie** : Validation Value Object

**Description** : Contraintes sur le nom utilisateur (nom complet ou pseudo).

**Règle** :
- Longueur : 2-255 caractères
- Trimmed (espaces début/fin supprimés)
- Non vide après trim

**Validation** :
```
nom_trimmed = String.trim(nom)
length(nom_trimmed) >= 2 AND length(nom_trimmed) <= 255
```

**Erreurs** :
- < 2 caractères → "Nom trop court (minimum 2 caractères)"
- > 255 caractères → "Nom trop long (maximum 255 caractères)"
- Vide après trim → "Nom requis"

**Format** : Texte libre (accepte caractères spéciaux, accents, espaces).

**Exemples valides** :
- "Jean Dupont"
- "Marie-Claire"
- "山田太郎" (caractères japonais)
- "Admin"

## PU-009 : Validation URL Photo Profil

**Catégorie** : Validation Value Object

**Description** : Validation format URL photo profil utilisateur.

**Règle** :
- Format : URL valide (HTTP/HTTPS)
- Nullable : Champ optionnel
- Taille recommandée : 256x256 px minimum

**Validation** :
```
Si photo_url présent:
  Vérifier format URL valide (regex ou URI.parse)
  Vérifier protocole HTTP ou HTTPS
Sinon:
  NULL accepté (pas de photo profil)
```

**Regex validation** :
```
^https?://[^\\s/$.?#].[^\\s]*$
```

**Erreurs** :
- Format invalide → "URL photo profil invalide"
- Protocole non HTTP/HTTPS → "Seuls HTTP et HTTPS acceptés"

**Exemple valide** :
- "https://example.com/avatars/user123.jpg"
- NULL (pas de photo)

**Stockage** : URL externe (pas d'upload photo profil dans système actuel).

## PU-010 : Modification Rôles Admin Uniquement

**Catégorie** : Règle sécurité

**Description** : Seul un administrateur peut modifier les rôles des utilisateurs.

**Règle** : Changement rôle (user ↔ admin) nécessite rôle admin de l'utilisateur effectuant l'action.

**Validation** :
```elixir
def change_role(current_scope, target_user_id, new_role) do
  # Vérification permissions
  if current_scope.user.role != :admin do
    {:error, "Permissions insuffisantes. Seul admin peut modifier rôles."}
  else
    # Vérification admin unique (PU-006)
    case {get_user(target_user_id).role, new_role} do
      {:admin, :user} ->
        if count_admins() == 1 do
          {:error, "Impossible de rétrograder dernier admin"}
        else
          update_role(target_user_id, new_role)
        end
      
      _ ->
        update_role(target_user_id, new_role)
    end
  end
end
```

**Cas protégés** :
- User ne peut pas s'auto-promouvoir admin
- User ne peut pas rétrograder admin
- Admin ne peut pas rétrograder dernier admin (PU-006)

**Audit** : Changement rôle loggé (utilisateur effectuant action, utilisateur cible, ancien rôle, nouveau rôle).

**Interface** : Route `/admin/users/:id/change_role` protégée par plug require_admin (RT-004).

## Documents Liés

- Auth Context : docs/ddd/003_auth_context.md
- User Context : docs/ddd/004_user_context.md
- Vue d'ensemble : docs/ddd/001_vue_ensemble.md
- ADR 020 : Magic Link Passwordless Auth
- ADR 021 : Role-Based Access Control
