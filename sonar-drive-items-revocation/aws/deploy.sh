#!/usr/bin/env bash
# Deploys the receiver as a Lambda function in the current AWS account and region. Run in AWS CloudShell,
# or on macOS or Linux (on Windows, in CloudShell or WSL):
#   git clone https://github.com/kant01ne/riot-functions && ./riot-functions/sonar-drive-items-revocation/aws/deploy.sh
# Credentials are stored in one Secrets Manager secret, never in the template or environment variables.
# Optional: STACK (default riot-sonar-revoker), AWS_REGION (CloudShell sets it to the console's region).
set -Eeuo pipefail

FUNCTION_DIR=$(cd "$(dirname "$0")/.." && pwd)

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[31m' GREEN=$'\033[32m' YELLOW=$'\033[33m' CYAN=$'\033[36m' RESET=$'\033[0m'
else
  BOLD="" DIM="" RED="" GREEN="" YELLOW="" CYAN="" RESET=""
fi
step() { printf '\n%s%s━━ %s %s%s\n\n' "$BOLD" "$CYAN" "$1" "${DIM}$2" "$RESET"; }
ok() { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*" >&2; }
# The marker stops the ERR trap from repeating a failure already explained in a subshell.
die() {
  printf '\n  %s✗ %s%s\n' "$RED$BOLD" "$*" "$RESET" >&2
  [ -d "${WORK:-}" ] && touch "$WORK/failed"
  exit 1
}
field() { printf '      %s%-16s%s %s\n' "$DIM" "$1" "$RESET" "$BOLD$2$RESET"; }
# Never stop without saying why: set -e alone exits silently.
trap '[ -e "${WORK:-}/failed" ] && exit 1; die "Failed at line $LINENO: $BASH_COMMAND. Fix it and rerun the script."' ERR
trap 'printf "\n"; die "Stopped. Rerun the script to continue."' INT
ask() { read -r "$@" || { echo; die "No input. Rerun the script to continue."; }; }
# Runs a command silently and only shows its output if it fails.
quietly() {
  local out
  if ! out=$(trap - ERR; "$@" 2>&1); then
    printf '%s\n' "$out" | sed 's/^/  /' >&2
    die "$1 $2 failed. Fix it and rerun the script."
  fi
}
# Like quietly, but prints the command's output for the caller to capture.
capture() {
  local out
  if ! out=$(trap - ERR; "$@" 2>"$WORK/stderr"); then
    sed 's/^/  /' "$WORK/stderr" >&2
    die "$1 $2 failed. Fix it and rerun the script."
  fi
  printf '%s' "$out"
}
# Lists the options and sets CHOICE to the number picked.
choose() {
  local question=$1 i=1 option
  shift
  printf '  %s\n\n' "$question"
  for option in "$@"; do printf '    %s%d%s %s\n' "$BOLD" "$i" "$RESET" "$option"; i=$((i + 1)); done
  echo
  while true; do
    ask -p "  ${BOLD}?${RESET} Choice [1-$#]: " CHOICE
    [[ "$CHOICE" =~ ^[0-9]+$ ]] && [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le $# ] && return 0
    warn "Type a number from 1 to $#."
  done
}
yes_or_no() {
  local answer
  ask -p "  ${BOLD}?${RESET} $1 [Y/n]: " answer
  [[ ! "$answer" =~ ^[nN] ]]
}
# CloudShell starts without the Azure and Google CLIs and lets the user install them in their home directory.
ensure_cli() {
  command -v "$1" >/dev/null && return 0
  if [ "${AWS_EXECUTION_ENV:-}" != CloudShell ]; then
    warn "$2 isn't installed. Install it from $3 and rerun this script, or pick the manual setup."
    return 1
  fi
  printf '  %sInstalling %s in CloudShell, this takes 2 to 3 minutes…%s\n' "$DIM" "$2" "$RESET"
  quietly bash -c "$4"
  export PATH="$HOME/.local/bin:$HOME/google-cloud-sdk/bin:$PATH"
  command -v "$1" >/dev/null
}

STACK=${STACK:-riot-sonar-revoker}
EVENT_TYPE=revoke_drive_item_permission_request.created
GUIDE=https://github.com/kant01ne/riot-functions/blob/main/sonar-drive-items-revocation/docs/deploy-aws.md
APP_NAME="Riot Sonar revoker"
GRAPH_APP_ID=00000003-0000-0000-c000-000000000000
GRAPH_ROLE=Files.ReadWrite.All
# Secrets go through files only readable by this user, never through command arguments.
WORK=$(mktemp -d)
chmod 700 "$WORK"
trap 'rm -rf "$WORK"' EXIT

printf '\n%sRiot Sonar revoker · AWS Lambda%s\n' "$BOLD" "$RESET"
printf '%sYou can stop and rerun this script at any time: it picks up where it left off.%s\n' "$DIM" "$RESET"

step "1/4" "Account, region and provider"
for tool in aws sam node npm curl; do
  command -v "$tool" >/dev/null || die "$tool is missing. Run this script in AWS CloudShell, or install $tool."
done
ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) \
  || die "Not signed in. Run: aws login"
REGION=${AWS_REGION:-${AWS_DEFAULT_REGION:-$(aws configure get region 2>/dev/null || true)}}
if [ -z "$REGION" ]; then
  ask -p "  ${BOLD}?${RESET} Region [eu-west-3]: " REGION
  REGION=${REGION:-eu-west-3}
fi
export AWS_REGION=$REGION
ok "Account $BOLD$ACCOUNT$RESET, region $BOLD$REGION$RESET, stack $STACK"

echo
choose "Which provider does Sonar revoke sharing on?" "Google Workspace" "Microsoft 365"
if [ "$CHOICE" = 1 ]; then PROVIDER=google PROVIDER_NAME="Google Workspace"; else PROVIDER=microsoft PROVIDER_NAME="Microsoft 365"; fi
ok "$PROVIDER_NAME"

stack_status() { aws cloudformation describe-stacks --stack-name "$STACK" --query 'Stacks[0].StackStatus' --output text 2>/dev/null || true; }
# A first deploy that failed leaves a stack CloudFormation can't update: it holds nothing, so start over.
if [ "$(stack_status)" = ROLLBACK_COMPLETE ]; then
  warn "The previous first deploy failed. Removing the empty stack it left…"
  quietly aws cloudformation delete-stack --stack-name "$STACK"
  quietly aws cloudformation wait stack-delete-complete --stack-name "$STACK"
fi

step "2/4" "Build and deploy"
(cd "$FUNCTION_DIR" && quietly npm ci && quietly node scripts/build.mjs aws)
ok "Bundle built"
printf '  %sDeploying the stack, this takes 1 to 3 minutes…%s\n' "$DIM" "$RESET"
(cd "$FUNCTION_DIR" && quietly sam deploy --template-file aws/template.yaml --stack-name "$STACK" --region "$REGION" \
  --resolve-s3 --capabilities CAPABILITY_IAM --no-confirm-changeset --no-fail-on-empty-changeset)
output() {
  aws cloudformation describe-stacks --stack-name "$STACK" --query "Stacks[0].Outputs[?OutputKey=='$1'].OutputValue" --output text
}
STATUS_URL=$(output StatusUrl)
URL=${STATUS_URL%/}
SECRET_ARN=$(output SecretArn)
FUNCTION=$(output FunctionName)
ok "Deployed at $BOLD$URL$RESET"

# The secret is one JSON object; each step edits a copy and saves it only when something changed.
aws secretsmanager get-secret-value --secret-id "$SECRET_ARN" --query SecretString --output text > "$WORK/secret.json"
chmod 600 "$WORK/secret.json"
secret_get() {
  node -e 'const s = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8") || "{}"); process.stdout.write(s[process.argv[2]] ?? "")' \
    "$WORK/secret.json" "$1"
}
# The value comes from the environment so it never shows in the process list.
secret_set() {
  KEY=$1 VALUE=$2 node -e 'const fs = require("fs"), f = process.argv[1];
    const s = JSON.parse(fs.readFileSync(f, "utf8") || "{}"); s[process.env.KEY] = process.env.VALUE;
    fs.writeFileSync(f, JSON.stringify(s), { mode: 0o600 });' "$WORK/secret.json"
  SECRET_CHANGED=1
}
SECRET_CHANGED=""
save_secret() {
  [ -n "$SECRET_CHANGED" ] || return 0
  quietly aws secretsmanager put-secret-value --secret-id "$SECRET_ARN" --secret-string "file://$WORK/secret.json"
  SECRET_CHANGED=""
}

step "3/4" "$PROVIDER_NAME"
# Creates or reuses the Entra app and sets MS_TENANT, MS_CLIENT and MS_SECRET (empty to keep the stored secret).
create_entra_app() {
  local user="" principal graph role assignments granted="" expires
  if user=$(az account show --query user.name -o tsv 2>/dev/null); then
    yes_or_no "Signed in to Azure as $BOLD$user$RESET (tenant $(az account show --query tenantId -o tsv)). Use this tenant?" || user=""
  fi
  if [ -z "$user" ]; then
    printf '  %sSign in with an account that can grant admin consent (Global Administrator or Privileged Role Administrator).%s\n' "$DIM" "$RESET"
    az login --use-device-code --allow-no-subscriptions --output none || die "Azure sign-in failed. Rerun the script."
  fi
  MS_TENANT=$(capture az account show --query tenantId -o tsv)

  MS_CLIENT=$(capture az ad app list --display-name "$APP_NAME" --query '[0].appId' -o tsv)
  if [ -n "$MS_CLIENT" ]; then
    ok "Found the Entra app $BOLD$APP_NAME$RESET ($MS_CLIENT)"
  else
    MS_CLIENT=$(capture az ad app create --display-name "$APP_NAME" --sign-in-audience AzureADMyOrg --query appId -o tsv)
    ok "Created the Entra app $BOLD$APP_NAME$RESET ($MS_CLIENT)"
  fi
  principal=$(az ad sp show --id "$MS_CLIENT" --query id -o tsv 2>/dev/null || true)
  [ -n "$principal" ] || principal=$(capture az ad sp create --id "$MS_CLIENT" --query id -o tsv)

  # Declares the permission on the app, then grants it, which is what admin consent does.
  graph=$(capture az ad sp show --id "$GRAPH_APP_ID" --query id -o tsv)
  role=$(capture az ad sp show --id "$GRAPH_APP_ID" --query "appRoles[?value=='$GRAPH_ROLE'].id | [0]" -o tsv)
  quietly az ad app permission add --id "$MS_CLIENT" --api "$GRAPH_APP_ID" --api-permissions "$role=Role"
  assignments="https://graph.microsoft.com/v1.0/servicePrincipals/$principal/appRoleAssignments"
  if [ "$(capture az rest --url "$assignments" --query "value[?appRoleId=='$role'] | length(@)" -o tsv)" != 0 ]; then
    ok "The app already has $GRAPH_ROLE"
  else
    printf '{"principalId":"%s","resourceId":"%s","appRoleId":"%s"}' "$principal" "$graph" "$role" > "$WORK/grant.json"
    # A new app takes a few seconds to show up in Microsoft Graph.
    for _ in 1 2 3 4 5 6; do
      if az rest --method POST --url "$assignments" --headers Content-Type=application/json --body "@$WORK/grant.json" \
        >/dev/null 2>"$WORK/stderr"; then
        granted=1
        break
      fi
      grep -qiE 'Authorization_RequestDenied|privileges' "$WORK/stderr" && break
      sleep 10
    done
    if [ -n "$granted" ]; then
      ok "Granted $GRAPH_ROLE with admin consent"
    else
      warn "Only a Global Administrator or a Privileged Role Administrator can grant $GRAPH_ROLE. Send them this link:"
      printf '  %shttps://login.microsoftonline.com/%s/adminconsent?client_id=%s%s\n\n' "$CYAN" "$MS_TENANT" "$MS_CLIENT" "$RESET"
      ask -p "  ${BOLD}?${RESET} Press Enter once they have accepted. "
    fi
  fi

  MS_SECRET=""
  if [ "$(secret_get MS_CLIENT_ID)" = "$MS_CLIENT" ] && [ -n "$(secret_get MS_CLIENT_SECRET)" ]; then
    ok "Kept the current client secret"
    return 0
  fi
  # Each new secret is added next to the previous ones, which keep working until they expire.
  MS_SECRET=$(capture az ad app credential reset --id "$MS_CLIENT" --display-name "$STACK" --years 2 --append --query password -o tsv)
  expires=$(node -e 'const d = new Date(); d.setFullYear(d.getFullYear() + 2); console.log(d.toISOString().slice(0, 10))')
  ok "Created a client secret. It expires on $BOLD$expires$RESET: rerun this script before then."
}

# Creates or reuses the service account and sets KEY_FILE to a new key, or leaves it empty if the organization forbids keys.
create_google_key() {
  local account project default_project email
  account=$(gcloud config get-value account 2>/dev/null || true)
  if [ -n "$account" ]; then
    yes_or_no "Signed in to Google Cloud as $BOLD$account$RESET. Use this account?" || account=""
  fi
  if [ -z "$account" ]; then
    if [ "${AWS_EXECUTION_ENV:-}" = CloudShell ]; then
      gcloud auth login --no-launch-browser || die "Google Cloud sign-in failed. Rerun the script."
    else
      gcloud auth login || die "Google Cloud sign-in failed. Rerun the script."
    fi
  fi
  default_project=$(gcloud config get-value project 2>/dev/null || true)
  ask -p "  ${BOLD}?${RESET} Google Cloud project ID to hold the service account${default_project:+ [$default_project]}: " project
  project=${project:-$default_project}
  [ -n "$project" ] || die "A Google Cloud project is needed. Create one at https://console.cloud.google.com/projectcreate and rerun."

  printf '  %sTurning on the Google Drive API…%s\n' "$DIM" "$RESET"
  quietly gcloud services enable drive.googleapis.com --project "$project"
  email="$STACK@$project.iam.gserviceaccount.com"
  if gcloud iam service-accounts describe "$email" --project "$project" >/dev/null 2>&1; then
    ok "Found the service account $BOLD$email$RESET"
  else
    quietly gcloud iam service-accounts create "$STACK" --display-name "$APP_NAME" --project "$project"
    ok "Created the service account $BOLD$email$RESET"
  fi
  if gcloud iam service-accounts keys create "$WORK/key.json" --iam-account "$email" --project "$project" >/dev/null 2>"$WORK/stderr"; then
    KEY_FILE=$WORK/key.json
    ok "Created a key"
  elif grep -q disableServiceAccountKeyCreation "$WORK/stderr"; then
    warn "Your organization forbids service account keys (policy iam.disableServiceAccountKeyCreation)."
    printf '  An organization admin can allow them for this project: %s%s#allow-service-account-keys%s\n' "$CYAN" "$GUIDE" "$RESET"
  else
    sed 's/^/  /' "$WORK/stderr" >&2
    warn "Couldn't create the key."
  fi
}

if [ "$PROVIDER" = google ]; then
  printf '  The receiver acts on Google Drive with a service account key that has domain-wide delegation.\n\n'
  GOOGLE_EMAIL=$(secret_get GOOGLE_SERVICE_ACCOUNT_JSON | node -e 'try { console.log(JSON.parse(require("fs").readFileSync(0, "utf8")).client_email) } catch {}')
  OPTIONS=("Automatically, signed in with the Google Cloud CLI (gcloud)" "By hand, following the guide")
  [ -n "$GOOGLE_EMAIL" ] && OPTIONS+=("Keep the current service account ($GOOGLE_EMAIL)")
  choose "How do you want to set up the service account?" "${OPTIONS[@]}"
  KEY_FILE=""
  if [ "$CHOICE" = 1 ] && ensure_cli gcloud "the Google Cloud CLI" https://cloud.google.com/sdk/docs/install \
    "curl -fsSL https://dl.google.com/dl/cloudsdk/channels/rapid/google-cloud-cli-linux-x86_64.tar.gz | tar -xz -C ~"; then
    create_google_key
  fi
  if [ "$CHOICE" = 3 ]; then
    ok "Kept the current service account"
  else
    if [ -z "$KEY_FILE" ]; then
      printf '\n  Create the service account and its key with the guide, then come back here:\n'
      printf '  %s%s#google-workspace-by-hand%s\n' "$CYAN" "$GUIDE" "$RESET"
      [ "${AWS_EXECUTION_ENV:-}" = CloudShell ] && printf '  Upload the key file with %sActions > Upload file%s first.\n' "$BOLD" "$RESET"
      echo
      while true; do
        ask -ep "  ${BOLD}?${RESET} Path to the key file: " KEY_FILE
        KEY_FILE=${KEY_FILE/#\~/$HOME}
        node -e 'const k = JSON.parse(require("fs").readFileSync(process.argv[1], "utf8"));
          if (!k.client_email || !k.private_key || !k.client_id) process.exit(1)' "$KEY_FILE" 2>/dev/null && break
        warn "$KEY_FILE isn't a service account key (JSON with client_email, client_id and private_key). Try again."
      done
    fi
    secret_set GOOGLE_SERVICE_ACCOUNT_JSON "$(cat "$KEY_FILE")"
    save_secret
    ok "Service account key saved"
    printf '\n  Ask a Google Workspace super admin to allow it:\n\n'
    printf '  1. Open %shttps://admin.google.com/ac/owl/domainwidedelegation%s.\n' "$CYAN" "$RESET"
    printf '  2. Click %sAdd new%s and fill in:\n\n' "$BOLD" "$RESET"
    field "Client ID" "$(node -e 'console.log(JSON.parse(require("fs").readFileSync(process.argv[1], "utf8")).client_id)' "$KEY_FILE")"
    field "OAuth scopes" "https://www.googleapis.com/auth/drive"
    printf '\n  3. Click %sAuthorize%s.\n\n' "$BOLD" "$RESET"
    ask -p "  ${BOLD}?${RESET} Press Enter once it's done. "
  fi
else
  printf '  The receiver acts on OneDrive and SharePoint as an Entra app with the application permission\n'
  printf '  %s%s%s and admin consent.\n\n' "$BOLD" "$GRAPH_ROLE" "$RESET"
  MS_CLIENT_ID_NOW=$(secret_get MS_CLIENT_ID)
  OPTIONS=("Automatically, signed in to the Azure CLI (az) as an Entra admin" "By hand, following the guide")
  [ -n "$MS_CLIENT_ID_NOW" ] && OPTIONS+=("Keep the current app ($MS_CLIENT_ID_NOW)")
  choose "How do you want to set up the Entra app?" "${OPTIONS[@]}"
  MS_TENANT=""
  if [ "$CHOICE" = 1 ] && ensure_cli az "the Azure CLI" https://learn.microsoft.com/cli/azure/install-azure-cli \
    "pip3 install --user --quiet azure-cli"; then
    create_entra_app
  fi
  if [ "$CHOICE" = 3 ]; then
    ok "Kept the current Entra app"
  else
    if [ -z "$MS_TENANT" ]; then
      printf '\n  Create the app with the guide, then copy its IDs from its %sOverview%s page:\n' "$BOLD" "$RESET"
      printf '  %s%s#microsoft-365-by-hand%s\n\n' "$CYAN" "$GUIDE" "$RESET"
      ask -p "  ${BOLD}?${RESET} Directory (tenant) ID: " MS_TENANT
      ask -p "  ${BOLD}?${RESET} Application (client) ID: " MS_CLIENT
      ask -sp "  ${BOLD}?${RESET} Client secret value: " MS_SECRET; echo
      [ -n "$MS_TENANT" ] && [ -n "$MS_CLIENT" ] && [ -n "$MS_SECRET" ] \
        || die "The tenant ID, the client ID and the client secret are all needed. Rerun the script."
    fi
    secret_set MS_TENANT_ID "$MS_TENANT"
    secret_set MS_CLIENT_ID "$MS_CLIENT"
    [ -n "$MS_SECRET" ] && secret_set MS_CLIENT_SECRET "$MS_SECRET"
    save_secret
    ok "Entra app saved"
  fi
fi

step "4/4" "Connect Riot"
printf '  1. Open %shttps://hub.tryriot.com/settings/about%s and click the %sAPI%s tab.\n' "$CYAN" "$RESET" "$BOLD" "$RESET"
printf '  2. Click %sCreate endpoint%s and fill in:\n\n' "$BOLD" "$RESET"
field "Name" "Sonar revoker"
field "Endpoint URL" "$URL/api/webhook"
field "Events to send" "$EVENT_TYPE (only this one)"
printf '\n  3. Click %sCreate endpoint%s. Riot shows the signing secret once: copy it.\n\n' "$BOLD" "$RESET"
HAS_RIOT_SECRET=$(secret_get RIOT_WEBHOOK_SECRET)
if [ -n "$HAS_RIOT_SECRET" ]; then
  printf '  %sAlready connected? Press Enter to keep the current secret.%s\n' "$DIM" "$RESET"
fi
while true; do
  ask -sp "  ${BOLD}?${RESET} Paste the signing secret (whsec_…): " RIOT_SECRET; echo
  if [ -z "$RIOT_SECRET" ] || [[ "$RIOT_SECRET" == whsec_* ]]; then break; fi
  warn "The signing secret starts with whsec_. Try again."
done
if [ -n "$RIOT_SECRET" ]; then
  secret_set RIOT_WEBHOOK_SECRET "$RIOT_SECRET"
  save_secret
  ok "Signing secret saved"
elif [ -n "$HAS_RIOT_SECRET" ]; then
  ok "Kept the current signing secret"
else
  warn "No signing secret yet: Riot's webhooks are rejected until you rerun this script and paste it."
fi

printf '\n%s━━ Check%s\n\n' "$BOLD$CYAN" "$RESET"
# A warm function rereads the secret every minute, so wait for it to see the values just saved.
HEALTH=""
for _ in 1 2 3 4 5 6 7 8 9 10 11 12; do
  HEALTH=$(curl -fsS --max-time 20 "$URL/" 2>/dev/null || true)
  if [ -n "$HEALTH" ]; then
    [ -z "$RIOT_SECRET$HAS_RIOT_SECRET" ] || [[ "$HEALTH" == *'"riotSecret":"ok"'* ]] || { sleep 10; continue; }
    [[ "$HEALTH" == *"\"$PROVIDER\":\"ok\""* ]] && break
  fi
  sleep 10
done
message() { node -e 'try { console.log(JSON.parse(require("fs").readFileSync(0, "utf8")).message) } catch { console.log("no answer from /api/check") }'; }
provider_check() { curl -fsS --max-time 30 -X POST "$URL/api/check" -H 'content-type: application/json' -d "$1" 2>/dev/null || true; }
if [ -z "$HEALTH" ]; then
  warn "The function doesn't answer at $URL/ yet. Wait a minute and run: curl $URL/"
else
  case "$HEALTH" in
    *'"riotSecret":"ok"'*) ok "Riot signing secret" ;;
    *) warn "Riot signing secret: missing, rerun this script and paste it" ;;
  esac
  if [ "$PROVIDER" = google ]; then
    case "$HEALTH" in
      *'"google":"ok"'*)
        ask -p "  ${BOLD}?${RESET} Email of a Google Workspace user, to test Drive access (Enter to skip): " TEST_EMAIL
        if [ -n "$TEST_EMAIL" ]; then
          GOOGLE_CHECK=$(provider_check "$(EMAIL=$TEST_EMAIL node -e 'console.log(JSON.stringify({ provider: "google", email: process.env.EMAIL }))')")
          case "$GOOGLE_CHECK" in
            *'"ok":true'*) ok "Google Workspace" ;;
            *) warn "Google Workspace: $(printf '%s' "$GOOGLE_CHECK" | message)" ;;
          esac
        else
          ok "Google Workspace key"
        fi ;;
      *'"google":"missing"'*) warn "Google Workspace: no key yet, rerun this script" ;;
      *) warn "Google Workspace: the key is invalid, rerun this script with another key file" ;;
    esac
  else
    case "$HEALTH" in
      *'"microsoft":"ok"'*)
        MS_CHECK=$(provider_check '{"provider":"microsoft"}')
        case "$MS_CHECK" in
          *'"ok":true'*) ok "Microsoft 365" ;;
          *) warn "Microsoft 365: $(printf '%s' "$MS_CHECK" | message)" ;;
        esac ;;
      *) warn "Microsoft 365: no Entra app yet, rerun this script" ;;
    esac
  fi
fi

cat <<DONE

  Send a test from Riot: in the ${BOLD}API${RESET} tab, click ${BOLD}⋯${RESET} on the endpoint, then ${BOLD}Send test${RESET},
  pick ${BOLD}$EVENT_TYPE${RESET} and send it.
  Riot must show ${GREEN}"Your endpoint accepted the test"${RESET}. Nothing is revoked.

${BOLD}${GREEN}━━ Last step${RESET}

  Ask your Riot account manager to switch Sonar revocations to webhook mode.
  Each revocation then shows up in the logs as revoked, already_gone or skipped:
  ${CYAN}https://$REGION.console.aws.amazon.com/cloudwatch/home?region=$REGION#logsV2:log-groups/log-group/\$252Faws\$252Flambda\$252F$FUNCTION${RESET}

DONE
