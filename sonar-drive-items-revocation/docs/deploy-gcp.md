# Deploy on Google Cloud

The receiver runs on Cloud Run in your project. On Google Cloud it needs no key file: it runs as its own service account and signs domain-wide delegation tokens through the IAM Credentials API.

## Deploy

1. Open [Cloud Shell](https://shell.cloud.google.com) and select the project:

   ```bash
   gcloud config set project <project-id>
   ```

2. Run the deploy script:

   ```bash
   git clone https://github.com/kant01ne/riot-functions && ./riot-functions/sonar-drive-items-revocation/gcp/deploy.sh
   ```

   It asks for the Riot endpoint secret. To also handle Microsoft 365, prefix the command with `MS_TENANT_ID=<tenant> MS_CLIENT_ID=<client>`; it then asks for the client secret. `REGION` defaults to `europe-west1`.

3. The script prints the webhook URL to paste into Riot, and the client ID for the next step.

## Grant domain-wide delegation

In the Google Workspace admin console, open **Security > Access and data control > API controls > Manage domain-wide delegation**, click **Add new** and enter:

- Client ID: the one printed by the script.
- OAuth scope: `https://www.googleapis.com/auth/drive`

## What the script creates

- APIs: Cloud Run, Cloud Build, Artifact Registry, IAM Credentials, Drive, Secret Manager.
- Service account `riot-sonar-revoker`, allowed to sign tokens for itself only.
- Secret Manager secrets for the Riot secret and the Entra client secret.
- Cloud Run service `riot-sonar-revoker`, public, up to 5 instances.

## Update

Pull the repository and run the script again. It reuses the service account and adds a new secret version.

Then follow [Verify a deployment](../README.md#verify-a-deployment).
