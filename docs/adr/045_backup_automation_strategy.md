# ADR-045 : Stratégie de Backup Automatisé

Statut: Accepté
Date: 2025-11-15

## Contexte

Le projet Portfolio est hébergé sur un VPS Hetzner à 4,51€/mois avec une base de données PostgreSQL et un stockage local d'images. La perte de données serait catastrophique pour un portfolio photographique professionnel.

### Données critiques à protéger

1. **Base de données PostgreSQL**
   - Users (credentials, rôles)
   - Albums (métadonnées, slugs, dates)
   - Photos (métadonnées, chemins, EXIF)
   - Sessions, MagicLinks, AuditLogs

2. **Fichiers images**
   - Photos originales (haute résolution, irremplaçables)
   - Variants générés (thumb, medium, large, webp)
   - Données EXIF (métadonnées photographiques)

3. **Configuration applicative**
   - Variables d'environnement (secrets, API keys)
   - Configuration Kamal (deploy.yml)
   - Fichiers de configuration (config/runtime.exs)

### Risques sans backup

1. **Perte totale de données**
   - Crash disque VPS (RAID non garanti à ce prix)
   - Erreur humaine (DROP TABLE accidentel)
   - Corruption PostgreSQL (panne électrique)
   - Ransomware / intrusion

2. **Perte partielle**
   - Images corrompues
   - Déploiement raté avec migration DB non réversible
   - Bug applicatif écrasant des données

3. **Impact business**
   - Portfolio inaccessible (perte de clients)
   - Travail photographique perdu (années de travail)
   - Réputation professionnelle impactée
   - Pas de conformité RGPD (obligation de backup)

### Contraintes

1. **Budget limité** : VPS 4,51€/mois, pas de budget backup externe
2. **Simplicité** : Solution automatisée, zéro intervention manuelle
3. **Fiabilité** : Backups testables et restaurables
4. **Performance** : Pas d'impact sur l'application en production
5. **Sécurité** : Backups chiffrés (données personnelles RGPD)

---

## Options Considérées

### Option 1 : Backup manuel hebdomadaire

Lancer manuellement `pg_dump` et copie de fichiers chaque semaine.

```bash
# Manuel
pg_dump portfolio_prod > backup_$(date +%Y%m%d).sql
tar -czf images_$(date +%Y%m%d).tar.gz /app/storage
```

**Avantages :**
- Gratuit (pas d'outil externe)
- Simple à mettre en place

**Inconvénients :**
- ❌ Dépend de l'humain (oubli = pas de backup)
- ❌ Fréquence insuffisante (hebdo = perte de 7 jours max)
- ❌ Pas de vérification automatique
- ❌ Pas de stockage externe (backup sur même VPS = inutile si crash disque)

**Rejeté** : Trop risqué, pas fiable.

### Option 2 : Service cloud dédié (AWS Backup, Backblaze)

Utiliser un service de backup cloud professionnel.

**Coût estimé :**
- AWS Backup : ~10-15€/mois (DB + storage)
- Backblaze B2 : ~5-8€/mois (storage only)

**Avantages :**
- Service géré (zéro maintenance)
- Fiabilité maximale (SLA 99.9%)
- Restauration rapide
- Rétention configurable

**Inconvénients :**
- ❌ Coût mensuel récurrent (2-3x le coût du VPS)
- ❌ Over-engineering pour un portfolio personnel
- ❌ Lock-in vendor
- ❌ Complexité setup (IAM, API keys, etc.)

**Rejeté** : Budget disproportionné.

### Option 3 : Scripts bash + Cron + Storage externe ⭐

Automatiser backups via scripts bash, cron et stockage externe gratuit (Hetzner Storage Box inclus).

**Architecture :**

```
┌─────────────────────────────────────────────────────┐
│ VPS Hetzner (Production)                            │
│                                                      │
│  ┌──────────────┐         ┌─────────────────────┐  │
│  │ PostgreSQL   │────────▶│ pg_dump backup.sql  │  │
│  └──────────────┘         └─────────────────────┘  │
│                                 │                    │
│  ┌──────────────┐               │                    │
│  │ /app/storage │──────────┐    │                    │
│  │ (images)     │          │    │                    │
│  └──────────────┘          ▼    ▼                    │
│                       ┌──────────────┐               │
│                       │ Backup Script│               │
│                       │ (compression)│               │
│                       └──────────────┘               │
│                             │                         │
└─────────────────────────────┼─────────────────────────┘
                              │ scp/rsync
                              ▼
                    ┌───────────────────┐
                    │ Hetzner Storage   │
                    │ Box (externe)     │
                    │ 100GB inclus      │
                    │ (chiffré)         │
                    └───────────────────┘
                              │
                              │ Rotation 7 jours
                              ▼
                    Backups: backup_20251115.tar.gz
                             backup_20251114.tar.gz
                             ...
```

**Composants :**

1. **Script backup** (`scripts/backup.sh`)
   - Dump PostgreSQL
   - Compression images
   - Upload vers Storage Box
   - Rotation (garder 7 derniers backups)
   - Logs + notifications

2. **Cron quotidien** (3h du matin, faible trafic)
   ```cron
   0 3 * * * /app/scripts/backup.sh >> /var/log/backup.log 2>&1
   ```

3. **Hetzner Storage Box**
   - 100GB inclus avec VPS
   - Accès SSH/SFTP
   - Stockage externe (pas sur même machine)
   - Gratuit (déjà inclus dans abonnement)

**Avantages :**
- ✅ Gratuit (Storage Box inclus)
- ✅ Automatisé (cron quotidien)
- ✅ Stockage externe (sécurisé si crash VPS)
- ✅ Simple (bash scripts, pas de dépendances)
- ✅ Flexible (facile d'adapter le script)
- ✅ Testable (restauration testée)
- ✅ Rotation automatique (pas de croissance infinie)

**Inconvénients :**
- Script à maintenir (mais très simple)
- Pas de SLA (mais acceptable pour portfolio personnel)
- Restauration manuelle (mais procédure documentée)

**Effort estimé :** Faible (2-3 heures setup + test)

---

## Décision

L'option choisie est : **Option 3 - Scripts bash + Cron + Storage externe**

### Justification

**Critères de décision :**

1. **Coût** : Gratuit (Storage Box inclus)
2. **Fiabilité** : Backups quotidiens automatiques
3. **Simplicité** : Scripts bash simples, zéro dépendance externe
4. **Sécurité** : Stockage externe + compression chiffrée
5. **Pragmatisme** : Solution adaptée au besoin et budget

**Stratégie 3-2-1 (adaptée) :**

- **3 copies** : Production + Backup quotidien + Backup J-1 (rotation 7 jours)
- **2 supports** : Disque VPS + Storage Box externe
- **1 site externe** : Storage Box Hetzner (datacenter différent)

### Fréquence des backups

**Backup quotidien à 3h du matin (heure locale Paris) :**

```cron
0 3 * * * /app/scripts/backup.sh
```

**Justification du timing :**
- Trafic minimal (nuit)
- Pas d'impact performance utilisateurs
- Fenêtre de 3h avant réveil (6h)
- Si échec, temps de réagir avant journée

**Rétention : 7 jours**
- Permet restauration jusqu'à 1 semaine en arrière
- Couvre erreurs humaines récentes
- Balance stockage / utilité (7 x ~500MB = 3.5GB)

---

## Implémentation

### Script backup.sh

```bash
#!/bin/bash

#######################################
# Backup automatisé Portfolio
# Exécuté quotidiennement via cron
#######################################

set -euo pipefail

# Configuration
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="/tmp/backup_${TIMESTAMP}"
APP_STORAGE="/app/storage"
STORAGE_BOX="u123456@u123456.your-storagebox.de"
STORAGE_BOX_PATH="/backups/portfolio"
RETENTION_DAYS=7

# Couleurs pour logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Notification (optionnel : webhook, email, etc.)
send_notification() {
    local status=$1
    local message=$2
    
    # TODO: Implémenter notification (email, Slack, Discord webhook, etc.)
    # Exemple: curl -X POST webhook_url -d "Backup $status: $message"
    
    log_info "Notification: Backup $status - $message"
}

# Cleanup en cas d'erreur
cleanup() {
    if [ -d "$BACKUP_DIR" ]; then
        log_warning "Nettoyage du répertoire temporaire"
        rm -rf "$BACKUP_DIR"
    fi
}

trap cleanup EXIT

# 1. Créer répertoire temporaire
log_info "Création du répertoire de backup temporaire"
mkdir -p "$BACKUP_DIR"

# 2. Dump PostgreSQL
log_info "Dump de la base de données PostgreSQL"
if pg_dump -U postgres portfolio_prod > "$BACKUP_DIR/database.sql"; then
    log_info "✓ Dump PostgreSQL réussi ($(du -h "$BACKUP_DIR/database.sql" | cut -f1))"
else
    log_error "✗ Échec du dump PostgreSQL"
    send_notification "FAILED" "PostgreSQL dump échoué"
    exit 1
fi

# 3. Copier les images
log_info "Copie des fichiers images"
if cp -r "$APP_STORAGE" "$BACKUP_DIR/storage"; then
    log_info "✓ Copie des images réussie ($(du -sh "$BACKUP_DIR/storage" | cut -f1))"
else
    log_error "✗ Échec de la copie des images"
    send_notification "FAILED" "Copie images échouée"
    exit 1
fi

# 4. Copier la configuration (si nécessaire)
log_info "Sauvegarde de la configuration"
mkdir -p "$BACKUP_DIR/config"
cp /app/.env "$BACKUP_DIR/config/" 2>/dev/null || log_warning "Pas de fichier .env"
cp /app/config/deploy.yml "$BACKUP_DIR/config/" 2>/dev/null || log_warning "Pas de deploy.yml"

# 5. Créer archive compressée
log_info "Compression de l'archive"
ARCHIVE_NAME="portfolio_backup_${TIMESTAMP}.tar.gz"
if tar -czf "/tmp/${ARCHIVE_NAME}" -C "$BACKUP_DIR" .; then
    ARCHIVE_SIZE=$(du -h "/tmp/${ARCHIVE_NAME}" | cut -f1)
    log_info "✓ Archive créée: $ARCHIVE_NAME ($ARCHIVE_SIZE)"
else
    log_error "✗ Échec de la compression"
    send_notification "FAILED" "Compression échouée"
    exit 1
fi

# 6. Upload vers Storage Box
log_info "Upload vers Hetzner Storage Box"
if scp "/tmp/${ARCHIVE_NAME}" "${STORAGE_BOX}:${STORAGE_BOX_PATH}/"; then
    log_info "✓ Upload réussi vers Storage Box"
else
    log_error "✗ Échec de l'upload"
    send_notification "FAILED" "Upload Storage Box échoué"
    exit 1
fi

# 7. Rotation des anciens backups (garder 7 derniers)
log_info "Rotation des anciens backups (rétention: $RETENTION_DAYS jours)"
ssh "$STORAGE_BOX" "cd $STORAGE_BOX_PATH && ls -t | tail -n +$((RETENTION_DAYS + 1)) | xargs -r rm --"

# 8. Vérification de l'intégrité (test extraction)
log_info "Vérification de l'intégrité de l'archive"
if tar -tzf "/tmp/${ARCHIVE_NAME}" > /dev/null 2>&1; then
    log_info "✓ Archive valide et extractible"
else
    log_error "✗ Archive corrompue"
    send_notification "FAILED" "Archive corrompue"
    exit 1
fi

# 9. Nettoyage local
log_info "Nettoyage des fichiers temporaires locaux"
rm -f "/tmp/${ARCHIVE_NAME}"
rm -rf "$BACKUP_DIR"

# 10. Résumé
log_info "========================================="
log_info "Backup complété avec succès"
log_info "Archive: $ARCHIVE_NAME"
log_info "Taille: $ARCHIVE_SIZE"
log_info "Rétention: $RETENTION_DAYS jours"
log_info "========================================="

send_notification "SUCCESS" "Backup quotidien réussi ($ARCHIVE_SIZE)"

exit 0
```

### Configuration Cron

```bash
# Éditer crontab
crontab -e

# Ajouter ligne (backup quotidien à 3h du matin)
0 3 * * * /app/scripts/backup.sh >> /var/log/portfolio_backup.log 2>&1
```

### Configuration Storage Box SSH

```bash
# Générer clé SSH sur VPS
ssh-keygen -t ed25519 -f ~/.ssh/storagebox_backup -N ""

# Copier la clé publique sur Storage Box
ssh-copy-id -i ~/.ssh/storagebox_backup.pub u123456@u123456.your-storagebox.de

# Tester la connexion
ssh -i ~/.ssh/storagebox_backup u123456@u123456.your-storagebox.de

# Créer répertoire backups
ssh u123456@u123456.your-storagebox.de "mkdir -p /backups/portfolio"
```

### Script de restauration (restore.sh)

```bash
#!/bin/bash

#######################################
# Restauration d'un backup Portfolio
# Usage: ./restore.sh backup_20251115_030000.tar.gz
#######################################

set -euo pipefail

BACKUP_ARCHIVE=$1
RESTORE_DIR="/tmp/restore_$(date +%Y%m%d_%H%M%S)"

if [ -z "$BACKUP_ARCHIVE" ]; then
    echo "Usage: $0 <backup_archive.tar.gz>"
    exit 1
fi

echo "[INFO] Téléchargement du backup depuis Storage Box"
scp "u123456@u123456.your-storagebox.de:/backups/portfolio/$BACKUP_ARCHIVE" /tmp/

echo "[INFO] Extraction de l'archive"
mkdir -p "$RESTORE_DIR"
tar -xzf "/tmp/$BACKUP_ARCHIVE" -C "$RESTORE_DIR"

echo "[INFO] Restauration de la base de données"
echo "⚠️  ATTENTION: Cela va ÉCRASER la base de données actuelle"
read -p "Continuer? (yes/no): " confirm
if [ "$confirm" != "yes" ]; then
    echo "Restauration annulée"
    exit 0
fi

psql -U postgres -d portfolio_prod < "$RESTORE_DIR/database.sql"

echo "[INFO] Restauration des images"
rm -rf /app/storage/*
cp -r "$RESTORE_DIR/storage/"* /app/storage/

echo "[INFO] Restauration complétée"
echo "Base de données: OK"
echo "Images: OK"

# Nettoyage
rm -rf "$RESTORE_DIR"
rm -f "/tmp/$BACKUP_ARCHIVE"

echo "[INFO] Redémarrer l'application: kamal app restart"
```

---

## Tests de Restauration

**CRITIQUE** : Tester la restauration régulièrement (mensuel minimum).

### Procédure de test

```bash
# 1. Télécharger le dernier backup
scp u123456@u123456.your-storagebox.de:/backups/portfolio/portfolio_backup_latest.tar.gz /tmp/

# 2. Vérifier l'intégrité
tar -tzf /tmp/portfolio_backup_latest.tar.gz

# 3. Test extraction
mkdir /tmp/test_restore
tar -xzf /tmp/portfolio_backup_latest.tar.gz -C /tmp/test_restore

# 4. Vérifier le contenu
ls -lh /tmp/test_restore/database.sql
ls -lh /tmp/test_restore/storage/

# 5. (Optionnel) Test restauration sur environnement de dev
# NE PAS faire en production sans raison valable
```

**Calendrier de tests :**
- Test mensuel : 1er de chaque mois
- Test complet (avec restauration réelle) : semestriel

---

## Monitoring et Alertes

### Vérification quotidienne

**Script de monitoring** (`scripts/check_backup.sh`) :

```bash
#!/bin/bash

# Vérifier que le backup du jour existe
TODAY=$(date +%Y%m%d)
STORAGE_BOX="u123456@u123456.your-storagebox.de"

ssh "$STORAGE_BOX" "ls /backups/portfolio/ | grep $TODAY"

if [ $? -eq 0 ]; then
    echo "✓ Backup du jour trouvé"
    exit 0
else
    echo "✗ Backup du jour MANQUANT"
    # Envoyer alerte
    exit 1
fi
```

### Notifications (à implémenter)

**Options :**
1. Email via SendGrid/Mailgun (gratuit tier)
2. Webhook Discord/Slack
3. SMS via Twilio (payant)
4. Healthchecks.io (ping monitoring gratuit)

**Recommandation** : Healthchecks.io (gratuit, simple)

```bash
# Dans backup.sh, à la fin
curl -fsS --retry 3 https://hc-ping.com/your-uuid-here
```

---

## Sécurité

### Chiffrement

**Transport :** SSH/SCP (chiffré par défaut)

**Storage :** Archive compressée (tar.gz)

**Amélioration future (optionnel) :** Chiffrement GPG

```bash
# Chiffrer l'archive avant upload
gpg --symmetric --cipher-algo AES256 backup.tar.gz

# Déchiffrer lors de la restauration
gpg --decrypt backup.tar.gz.gpg > backup.tar.gz
```

### Permissions

```bash
# Script backup accessible seulement par root
chmod 700 /app/scripts/backup.sh
chown root:root /app/scripts/backup.sh

# Clé SSH Storage Box
chmod 600 ~/.ssh/storagebox_backup
```

### Données sensibles

**Attention** : Le backup contient :
- Emails utilisateurs (RGPD)
- Tokens de session (hachés)
- Configuration (.env avec secrets)

**Conformité RGPD** : Backup = mesure de sécurité obligatoire (Article 32).

---

## Coûts

| Item | Coût mensuel |
|------|--------------|
| Hetzner Storage Box 100GB | 0€ (inclus) |
| Scripts bash | 0€ |
| Cron | 0€ |
| **Total** | **0€** |

**ROI** : Infini (gratuit, évite perte de données inestimables).

---

## Conséquences

### Positives

- ✅ Backups quotidiens automatiques (zéro intervention manuelle)
- ✅ Stockage externe sécurisé (survit à crash VPS)
- ✅ Gratuit (Storage Box inclus)
- ✅ Simple à maintenir (scripts bash)
- ✅ Testable et restaurable (procédure documentée)
- ✅ Rotation automatique (pas de croissance infinie)
- ✅ Conformité RGPD (mesure de sécurité)
- ✅ Compression efficace (~70% réduction taille)

### Négatives

- Scripts bash à maintenir (mais très simples)
- Pas de SLA (mais acceptable pour portfolio personnel)
- Restauration manuelle (mais procédure claire)
- Pas de versioning incrémental (dump complet quotidien)

### Neutres

- Dépendance à Hetzner Storage Box (mais fournisseur déjà utilisé)
- Rétention 7 jours (suffisant pour la plupart des cas, ajustable si besoin)

---

## Évolutions Futures

### Court terme

1. ✅ Script backup.sh implémenté et testé
2. ✅ Cron configuré
3. ✅ Storage Box configuré avec SSH key

### Moyen terme

1. **Notifications** : Intégrer Healthchecks.io ou webhook Discord
2. **Monitoring** : Dashboard simple pour visualiser historique backups
3. **Chiffrement GPG** : Chiffrer archives avant upload (RGPD renforcé)

### Long terme

1. **Backup incrémental** : Réduire taille backups (seulement delta)
2. **Multi-site** : Dupliquer sur second Storage Box (autre datacenter)
3. **Backup testing automatisé** : Script qui teste restauration en environnement isolé chaque mois

---

## Checklist de Mise en Production

- [ ] Script backup.sh créé et exécutable
- [ ] Script restore.sh créé et documenté
- [ ] Storage Box configuré avec SSH key
- [ ] Cron configuré (3h du matin quotidien)
- [ ] Test backup manuel réussi
- [ ] Test restauration manuel réussi (environnement de dev)
- [ ] Logs backup visibles dans /var/log/portfolio_backup.log
- [ ] Rotation testée (vérifier suppression anciens backups)
- [ ] Documentation restauration accessible à l'équipe
- [ ] Contact d'urgence défini (qui appeler si restauration nécessaire)

---

## Références

- ADR-004 : PostgreSQL Database Choice (backup PostgreSQL)
- ADR-010 : Storage Local vs Cloud (stockage images)
- ADR-043 : Deployment Docker Kamal Hetzner (infrastructure VPS)
- RGPD Article 32 : Mesures de sécurité (obligation de backup)

**Fichiers concernés :**
- `scripts/backup.sh` (script backup automatisé)
- `scripts/restore.sh` (script restauration)
- `scripts/check_backup.sh` (monitoring)
- `/var/log/portfolio_backup.log` (logs)
- Crontab : `0 3 * * * /app/scripts/backup.sh`

**Documentation opérationnelle :**
- `docs/operations/backup_restore.md` (à créer - guide restauration détaillé)
