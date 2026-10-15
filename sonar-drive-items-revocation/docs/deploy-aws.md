# Deploy on AWS

The receiver runs as one Lambda function (Node.js 22, arm64) behind an HTTP API. It stays within the free tier for normal revocation volumes.

## From the Serverless Application Repository

1. In the AWS console, open **Lambda > Applications > Create application > Serverless application**.
2. Under **Public applications**, search `riot-sonar-drive-items-revocation`.
3. Fill the parameters:
   - `RiotWebhookSecret`: the Riot endpoint secret (`whsec_…`).
   - `GoogleServiceAccountJson`: the service account key (raw JSON or base64), or empty for Microsoft only.
   - `MsTenantId`, `MsClientId`, `MsClientSecret`: the Entra app, or empty for Google only.
4. Click **Deploy**.
5. Open the stack outputs: `WebhookUrl` is the URL to paste into Riot.

Secrets are stored as Lambda environment variables, encrypted at rest with the account's default KMS key.

## With the SAM CLI

```bash
git clone https://github.com/kant01ne/riot-functions && cd riot-functions/sonar-drive-items-revocation
npm ci && node scripts/build.mjs aws
sam deploy --guided --template-file aws/template.yaml
```

## Update

Redeploy the application with the newer version from the same page, or run `sam deploy` again on a newer checkout. Parameters are kept.

Then follow [Verify a deployment](../README.md#verify-a-deployment).
