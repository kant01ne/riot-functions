# Deploy on Azure

The receiver runs as a Function App on the Consumption plan (Windows, Node.js 22). The code comes straight from the GitHub release zip, so nothing is built in your subscription.

## Deploy

1. Click **Deploy to Azure** in the [function README](../README.md#deploy).
2. Pick a subscription and a resource group (a new one keeps everything together).
3. Fill the parameters:
   - `Riot Webhook Secret`: the Riot endpoint secret (`whsec_…`).
   - `Ms Tenant Id`, `Ms Client Id`, `Ms Client Secret`: the Entra app, or empty for Google only.
   - `Google Service Account Json`: the service account key (raw JSON or base64), or empty for Microsoft only.
   - Leave `Release Version` as is.
4. Click **Review + create**, then **Create**.
5. When it finishes, open **Outputs**: `webhookUrl` is the URL to paste into Riot.

The deployment creates a storage account, a Consumption plan, the Function App, and Application Insights with 30-day log retention.

## Update

Redeploy the template into the same resource group with a newer `Release Version`. The app setting `WEBSITE_RUN_FROM_PACKAGE` then points at the new zip.

## Logs

Function App > **Monitoring > Logs**, or Application Insights > **Transaction search**. Each delivery logs one line with its `status`.

Then follow [Verify a deployment](../README.md#verify-a-deployment).
