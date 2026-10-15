#!/usr/bin/env bash
# Deploys the receiver to Cloud Run in the current gcloud project. Run in Cloud Shell:
#   git clone https://github.com/kant01ne/riot-functions && ./riot-functions/sonar-drive-items-revocation/gcp/deploy.sh
# Optional: REGION (default europe-west1), SERVICE (default riot-sonar-revoker),
# MS_TENANT_ID and MS_CLIENT_ID to enable Microsoft 365 (the client secret is prompted).
set -euo pipefail

FUNCTION_DIR=$(cd "$(dirname "$0")/.." && pwd)

PROJECT=$(gcloud config get-value project 2>/dev/null)
[ -n "$PROJECT" ] || { echo "Set a project first: gcloud config set project <id>" >&2; exit 1; }
REGION=${REGION:-europe-west1}
SERVICE=${SERVICE:-riot-sonar-revoker}
SA_NAME=${SA_NAME:-riot-sonar-revoker}
SA="${SA_NAME}@${PROJECT}.iam.gserviceaccount.com"

echo "Project $PROJECT, region $REGION, service $SERVICE"

gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com \
  iamcredentials.googleapis.com drive.googleapis.com secretmanager.googleapis.com

if ! gcloud iam service-accounts describe "$SA" >/dev/null 2>&1; then
  gcloud iam service-accounts create "$SA_NAME" --display-name "Riot Sonar revoker"
fi
# Lets the service sign its own domain-wide delegation assertions, so no key file ever exists.
gcloud iam service-accounts add-iam-policy-binding "$SA" \
  --member "serviceAccount:$SA" --role roles/iam.serviceAccountTokenCreator >/dev/null

put_secret() {
  local name=$1 value=$2
  if gcloud secrets describe "$name" >/dev/null 2>&1; then
    printf '%s' "$value" | gcloud secrets versions add "$name" --data-file=- >/dev/null
  else
    printf '%s' "$value" | gcloud secrets create "$name" --replication-policy automatic --data-file=- >/dev/null
  fi
  gcloud secrets add-iam-policy-binding "$name" \
    --member "serviceAccount:$SA" --role roles/secretmanager.secretAccessor >/dev/null
}

read -rsp "Riot webhook secret (whsec_...): " RIOT_SECRET; echo
put_secret sonar-revocation-riot-secret "$RIOT_SECRET"
SECRETS="RIOT_WEBHOOK_SECRET=sonar-revocation-riot-secret:latest"
ENV_VARS="GOOGLE_SERVICE_ACCOUNT_EMAIL=$SA"

if [ -n "${MS_CLIENT_ID:-}" ]; then
  : "${MS_TENANT_ID:?set MS_TENANT_ID with MS_CLIENT_ID}"
  read -rsp "Entra client secret: " MS_SECRET; echo
  put_secret sonar-revocation-ms-secret "$MS_SECRET"
  SECRETS="$SECRETS,MS_CLIENT_SECRET=sonar-revocation-ms-secret:latest"
  ENV_VARS="$ENV_VARS,MS_TENANT_ID=$MS_TENANT_ID,MS_CLIENT_ID=$MS_CLIENT_ID"
fi

(cd "$FUNCTION_DIR" && npm ci --silent && node scripts/build.mjs gcp)
STAGE=$(mktemp -d)
cp "$FUNCTION_DIR/gcp/Dockerfile" "$FUNCTION_DIR/dist/gcp/server.mjs" "$STAGE/"

gcloud run deploy "$SERVICE" --source "$STAGE" --region "$REGION" \
  --service-account "$SA" --allow-unauthenticated \
  --memory 256Mi --max-instances 5 --timeout 60 \
  --set-env-vars "$ENV_VARS" --set-secrets "$SECRETS"

URL=$(gcloud run services describe "$SERVICE" --region "$REGION" --format 'value(status.url)')
CLIENT_ID=$(gcloud iam service-accounts describe "$SA" --format 'value(oauth2ClientId)')

cat <<DONE

Deployed.
  Webhook URL (paste in Riot): $URL/api/webhook
  Status:                      $URL/

Google Workspace admin console > Security > API controls > Domain-wide delegation > Add new:
  Client ID:    $CLIENT_ID
  OAuth scope:  https://www.googleapis.com/auth/drive
DONE
