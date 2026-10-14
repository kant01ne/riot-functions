export type GoogleServiceAccount = { client_email: string; private_key: string };
export type MicrosoftApp = { tenantId: string; clientId: string; clientSecret: string };

export function riotSecrets(): string[] {
  return (process.env.RIOT_WEBHOOK_SECRET ?? "")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
}

export function googleServiceAccount(): GoogleServiceAccount | null {
  const raw = process.env.GOOGLE_SERVICE_ACCOUNT_JSON?.trim();
  if (!raw) return null;
  try {
    const json = raw.startsWith("{") ? raw : Buffer.from(raw, "base64").toString("utf8");
    const parsed = JSON.parse(json);
    if (typeof parsed.client_email !== "string" || typeof parsed.private_key !== "string") return null;
    return { client_email: parsed.client_email, private_key: parsed.private_key };
  } catch {
    return null;
  }
}

export function microsoftApp(): MicrosoftApp | null {
  const tenantId = process.env.MS_TENANT_ID?.trim();
  const clientId = process.env.MS_CLIENT_ID?.trim();
  const clientSecret = process.env.MS_CLIENT_SECRET?.trim();
  if (!tenantId || !clientId || !clientSecret) return null;
  return { tenantId, clientId, clientSecret };
}

export type ConfigStatus = {
  riotSecret: "missing" | "invalid" | "ok";
  google: "missing" | "invalid" | "ok";
  microsoft: "missing" | "partial" | "ok";
};

export function configStatus(): ConfigStatus {
  const secrets = riotSecrets();
  const anyGoogle = Boolean(process.env.GOOGLE_SERVICE_ACCOUNT_JSON?.trim());
  const anyMicrosoft = ["MS_TENANT_ID", "MS_CLIENT_ID", "MS_CLIENT_SECRET"].some((k) => process.env[k]?.trim());
  return {
    riotSecret: secrets.length === 0 ? "missing" : secrets.every((s) => s.startsWith("whsec_")) ? "ok" : "invalid",
    google: !anyGoogle ? "missing" : googleServiceAccount() ? "ok" : "invalid",
    microsoft: !anyMicrosoft ? "missing" : microsoftApp() ? "ok" : "partial",
  };
}
