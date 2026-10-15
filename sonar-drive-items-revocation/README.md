# Sonar drive items revocation

Receives Riot Sonar revocation webhooks and removes the Google Drive or Microsoft 365 permission with your own credentials, so Riot never needs write access to your files.

## Deploy

| Platform | How | Guide |
| --- | --- | --- |
| Vercel | [![Deploy with Vercel](https://vercel.com/button)](https://vercel.com/new/clone?repository-url=https%3A%2F%2Fgithub.com%2Fkant01ne%2Friot-functions&root-directory=sonar-drive-items-revocation%2Fvercel&project-name=riot-sonar-revoker) | Open the app URL and follow the setup steps. |
| AWS | Lambda from the Serverless Application Repository | [docs/deploy-aws.md](docs/deploy-aws.md) |
| Azure | [![Deploy to Azure](https://aka.ms/deploytoazurebutton)](https://portal.azure.com/#create/Microsoft.Template/uri/https%3A%2F%2Fraw.githubusercontent.com%2Fkant01ne%2Friot-functions%2Fmain%2Fsonar-drive-items-revocation%2Fazure%2Fazuredeploy.json) | [docs/deploy-azure.md](docs/deploy-azure.md) |
| Google Cloud | Cloud Run, from Cloud Shell, no key file | [docs/deploy-gcp.md](docs/deploy-gcp.md) |

## Environment variables

| Name | Value |
| --- | --- |
| `RIOT_WEBHOOK_SECRET` | Riot endpoint secret (`whsec_…`). Comma-separate two during rotation. |
| `GOOGLE_SERVICE_ACCOUNT_JSON` | Service account key, raw JSON or base64. |
| `GOOGLE_SERVICE_ACCOUNT_EMAIL` | Google Cloud only, instead of a key: the service account the receiver runs as, which signs its own delegation tokens. |
| `MS_TENANT_ID`, `MS_CLIENT_ID`, `MS_CLIENT_SECRET` | Entra app credentials. |

Google needs domain-wide delegation for the service account's client ID with the scope `https://www.googleapis.com/auth/drive`. Microsoft needs the `Files.ReadWrite.All` application permission with admin consent.

## Verify a deployment

The status page lists what is configured:

```bash
curl https://<host>/
```

Check the credentials against a real user or tenant:

```bash
curl -X POST https://<host>/api/check -H 'content-type: application/json' -d '{"provider":"google","email":"someone@yourdomain.com"}'
curl -X POST https://<host>/api/check -H 'content-type: application/json' -d '{"provider":"microsoft"}'
```

Then paste `https://<host>/api/webhook` into Riot as the endpoint URL and click **Send test**.

## Layout

`lib` holds the platform-agnostic receiver (`Request` in, `Response` out). `vercel`, `aws`, `azure` and `gcp` are thin adapters around it.

```bash
npm install && npm test && npm run typecheck && npm run build   # bundles into dist/<platform>
cd vercel && npm install && npm run dev                         # Vercel app
```

Releases are tagged `sonar-drive-items-revocation-v<version>`; bump `SemanticVersion` in `aws/template.yaml` and `releaseVersion` in `azure/azuredeploy.json` first.

A tag runs the `release` environment: it publishes the GitHub release (bundles and `SHA256SUMS`), then publishes and shares the application on the Serverless Application Repository once the repository variables `AWS_SAR_ROLE_ARN` and `AWS_SAR_BUCKET` exist. The role's trust policy must accept the subject `repo:kant01ne/riot-functions:environment:release` and allow `serverlessrepo:CreateApplication`, `CreateApplicationVersion`, `UpdateApplication` and `PutApplicationPolicy`, plus `s3:PutObject` on the bucket.
