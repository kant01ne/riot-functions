import { createSign } from "node:crypto";
import type { GoogleServiceAccount } from "./config";
import { classifyHttpError, ConfigurationError, type RevokeOutcome } from "./errors";

const DRIVE_SCOPE = "https://www.googleapis.com/auth/drive";
const TOKEN_URL = "https://oauth2.googleapis.com/token";

const base64url = (input: string | Buffer) => Buffer.from(input).toString("base64url");

export function buildAssertion(sa: GoogleServiceAccount, subject: string, nowSeconds = Math.floor(Date.now() / 1000)) {
  const header = base64url(JSON.stringify({ alg: "RS256", typ: "JWT" }));
  const claims = base64url(
    JSON.stringify({ iss: sa.client_email, sub: subject, scope: DRIVE_SCOPE, aud: TOKEN_URL, iat: nowSeconds, exp: nowSeconds + 3600 }),
  );
  const signature = createSign("RSA-SHA256").update(`${header}.${claims}`).sign(sa.private_key);
  return `${header}.${claims}.${base64url(signature)}`;
}

export async function googleAccessToken(sa: GoogleServiceAccount, subject: string): Promise<string> {
  const res = await fetch(TOKEN_URL, {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: buildAssertion(sa, subject),
    }),
  });
  const body = await res.text();
  if (res.ok) return JSON.parse(body).access_token;
  // unauthorized_client means domain-wide delegation is not granted for this client ID and scope.
  if (res.status === 400 || res.status === 401) throw new ConfigurationError(`Google token exchange failed: ${body}`);
  throw classifyHttpError("Google token", res.status, body);
}

export type GoogleRevocation = { owner_id: string; drive_item_id: string; permission_id: string };

export async function revokeGooglePermission(sa: GoogleServiceAccount, data: GoogleRevocation): Promise<RevokeOutcome> {
  const token = await googleAccessToken(sa, data.owner_id);
  const url =
    `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(data.drive_item_id)}` +
    `/permissions/${encodeURIComponent(data.permission_id)}?supportsAllDrives=true`;
  const res = await fetch(url, { method: "DELETE", headers: { authorization: `Bearer ${token}` } });
  if (res.ok) return { status: "revoked" };

  const body = await res.text();
  if (res.status === 404) return { status: "already_gone" };
  if (res.status === 403 && /inherit/i.test(body)) {
    return { status: "skipped", reason: "permission is inherited from a parent folder or shared drive" };
  }
  throw classifyHttpError("Google Drive", res.status, body);
}

export async function checkGoogle(sa: GoogleServiceAccount, adminEmail: string) {
  const token = await googleAccessToken(sa, adminEmail);
  const res = await fetch("https://www.googleapis.com/drive/v3/about?fields=user", {
    headers: { authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw classifyHttpError("Google Drive", res.status, await res.text());
}
