# Riot Sonar Revoker

Riot Sonar finds risky sharing on Google Drive, OneDrive and SharePoint. Some companies do not want to give Riot write access to their files. In webhook mode, Riot only reads, and sends a signed `revoke_drive_item_permission_request.created` webhook each time a permission must be removed. This app receives that webhook and removes the permission with credentials that stay in your cloud.

[![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Ftryriot%2Friot-sonar-revoker&project-name=riot-sonar-revoker)

After the deployment, open the app URL. The home page walks the admin through the setup and shows which steps are done.

## How it works

1. Riot sends `POST /api/webhook` following [Standard Webhooks](https://www.standardwebhooks.com/).
2. The app checks the signature against `RIOT_WEBHOOK_SECRET`.
3. Google: the service account impersonates the file owner through domain-wide delegation and calls `DELETE /drive/v3/files/{id}/permissions/{permissionId}`.
4. Microsoft: the app gets a client credentials token and calls `DELETE /drives/{driveId}/items/{id}/permissions/{permissionId}`, or the owner's OneDrive when there is no drive id.

| Response | Meaning | Riot behavior |
| --- | --- | --- |
| 200 `revoked` | The permission was removed. | Done. |
| 200 `already_gone` | The permission no longer exists. | Done. |
| 200 `skipped` | The permission is inherited from a parent and cannot be removed on the item. | Done, logged. |
| 200 `test_received` | Test delivery from Riot. Nothing is revoked. | Done. |
| 401 | Bad signature or wrong secret. | Retries. |
| 500 | Missing or wrong Google or Microsoft configuration. | Retries and alerts your admins. |
| 503 | Rate limit or provider outage. | Retries for about three days. |

## Environment variables

| Name | Required | Value |
| --- | --- | --- |
| `RIOT_WEBHOOK_SECRET` | Yes | Endpoint signing secret from Riot, `whsec_…`. Comma-separate two secrets during a rotation. |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | For Google | The service account key file, raw JSON or base64. |
| `MS_TENANT_ID` | For Microsoft | Directory (tenant) ID. |
| `MS_CLIENT_ID` | For Microsoft | Application (client) ID. |
| `MS_CLIENT_SECRET` | For Microsoft | Client secret value. |

## Development

```bash
npm install
npm test
npm run dev
```
