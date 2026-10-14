import { googleServiceAccount, microsoftApp } from "@/lib/config";
import { checkGoogle } from "@/lib/google";
import { checkMicrosoft } from "@/lib/microsoft";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const result = (ok: boolean, message: string) => Response.json({ ok, message });

export async function POST(request: Request) {
  const { provider, email } = (await request.json().catch(() => ({}))) as { provider?: string; email?: string };
  try {
    if (provider === "google") {
      const sa = googleServiceAccount();
      if (!sa) return result(false, "GOOGLE_SERVICE_ACCOUNT_JSON is missing or invalid.");
      if (!email || !email.includes("@")) return result(false, "Enter the email of a user in your Google Workspace.");
      await checkGoogle(sa, email.trim());
      return result(true, `Domain-wide delegation works: the service account can act as ${email.trim()}.`);
    }
    if (provider === "microsoft") {
      const app = microsoftApp();
      if (!app) return result(false, "MS_TENANT_ID, MS_CLIENT_ID and MS_CLIENT_SECRET must all be set.");
      await checkMicrosoft(app);
      return result(true, "The app can get a token and has admin consent for Files.ReadWrite.All.");
    }
    return result(false, "Unknown provider.");
  } catch (error) {
    return result(false, error instanceof Error ? error.message : String(error));
  }
}
