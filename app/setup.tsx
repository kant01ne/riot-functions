"use client";

import { useEffect, useState } from "react";
import type { ConfigStatus } from "@/lib/config";
import { EntraPermissionsShot, EntraSecretShot, GcpKeyShot, RiotEndpointShot, RiotTestShot, VercelEnvShot } from "./illustrations";

type State = "done" | "todo" | "error" | "skipped";
type Check = { ok: boolean; message: string } | null;

const STORAGE_KEY = "riot-sonar-revoker:manual";
const EVENT_TYPE = "revoke_drive_item_permission_request.created";

function useManual() {
  const [manual, setManual] = useState<Record<string, boolean>>({});
  useEffect(() => {
    try {
      setManual(JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "{}"));
    } catch {}
  }, []);
  const toggle = (key: string) =>
    setManual((prev) => {
      const next = { ...prev, [key]: !prev[key] };
      try {
        localStorage.setItem(STORAGE_KEY, JSON.stringify(next));
      } catch {}
      return next;
    });
  return { manual, toggle };
}

function Copy({ value }: { value: string }) {
  const [copied, setCopied] = useState(false);
  return (
    <span className="copy">
      <code>{value}</code>
      <button
        type="button"
        onClick={() => navigator.clipboard.writeText(value).then(() => (setCopied(true), setTimeout(() => setCopied(false), 1500)))}
      >
        {copied ? "Copied" : "Copy"}
      </button>
    </span>
  );
}

const LABEL: Record<State, string> = { done: "Done", todo: "To do", error: "Needs attention", skipped: "Not used" };

function Step(props: { n: number; title: string; state: State; summary?: string; children: React.ReactNode }) {
  const [open, setOpen] = useState(props.state !== "done" && props.state !== "skipped");
  useEffect(() => setOpen(props.state !== "done" && props.state !== "skipped"), [props.state]);
  return (
    <section className={`step ${props.state}`}>
      <button type="button" className="step-head" onClick={() => setOpen(!open)} aria-expanded={open}>
        <span className="dot">{props.state === "done" ? "✓" : props.state === "error" ? "!" : props.n}</span>
        <span className="step-title">{props.title}</span>
        <span className={`badge ${props.state}`}>{LABEL[props.state]}</span>
      </button>
      {props.summary && <p className="summary">{props.summary}</p>}
      {open && <div className="step-body">{props.children}</div>}
    </section>
  );
}

function Tick({ id, manual, toggle, children }: { id: string; manual: Record<string, boolean>; toggle: (k: string) => void; children: React.ReactNode }) {
  return (
    <label className="tick">
      <input type="checkbox" checked={Boolean(manual[id])} onChange={() => toggle(id)} />
      <span>{children}</span>
    </label>
  );
}

async function runCheck(provider: string, email?: string): Promise<Check> {
  const res = await fetch("/api/check", { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ provider, email }) });
  return res.json();
}

export function Setup({ status, webhookUrl }: { status: ConfigStatus; webhookUrl: string }) {
  const { manual, toggle } = useManual();
  const [googleEmail, setGoogleEmail] = useState("");
  const [googleCheck, setGoogleCheck] = useState<Check>(null);
  const [msCheck, setMsCheck] = useState<Check>(null);
  const [busy, setBusy] = useState<string | null>(null);

  const check = async (provider: "google" | "microsoft") => {
    setBusy(provider);
    const r = await runCheck(provider, googleEmail).catch((e) => ({ ok: false, message: String(e) }));
    (provider === "google" ? setGoogleCheck : setMsCheck)(r);
    setBusy(null);
  };

  const providerState = (configured: string, checkResult: Check, skippedKey: string): State => {
    if (configured === "missing") return manual[skippedKey] ? "skipped" : "todo";
    if (configured !== "ok" || checkResult?.ok === false) return "error";
    return checkResult?.ok ? "done" : "todo";
  };

  const riotState: State = status.riotSecret === "ok" ? "done" : status.riotSecret === "invalid" ? "error" : "todo";
  const googleState = providerState(status.google, googleCheck, "skip-google");
  const msState = providerState(status.microsoft, msCheck, "skip-microsoft");
  const providerReady = [googleState, msState].includes("done") && ![googleState, msState].includes("todo") && ![googleState, msState].includes("error");
  const testState: State = manual["riot-test"] ? "done" : "todo";
  const activeState: State = manual["riot-enabled"] ? "done" : "todo";

  const states = [riotState, googleState, msState, testState, activeState];
  const doneCount = 1 + states.filter((s) => s === "done" || s === "skipped").length;
  const total = states.length + 1;

  return (
    <main>
      <div className="glow" />
      <header className="hero">
        <p className="eyebrow"><span className="logo-dot" />Riot Sonar</p>
        <h1>Permission revoker setup</h1>
        <p className="lead">
          This app receives revocation requests from Riot Sonar and removes the sharing permission in your Google Workspace or
          Microsoft 365 tenant. Riot only needs read access. The write access stays in your cloud.
        </p>
        <div className="progress" role="progressbar" aria-valuenow={doneCount} aria-valuemin={0} aria-valuemax={total}>
          <div style={{ width: `${(doneCount / total) * 100}%` }} />
        </div>
        <p className="progress-label">
          {doneCount} of {total} steps done{doneCount === total ? ". You are all set." : ""}
        </p>
      </header>

      <Step n={1} title="Deploy this app" state="done" summary="This page is running, so the deployment worked.">
        <p>Your webhook URL is:</p>
        <Copy value={webhookUrl} />
      </Step>

      <Step n={2} title="Create the webhook endpoint in Riot" state={riotState}
        summary={riotState === "done" ? "RIOT_WEBHOOK_SECRET is set." : riotState === "error" ? "RIOT_WEBHOOK_SECRET must start with whsec_." : undefined}>
        <ol>
          <li>In Riot, open <b>Settings → API → Webhooks</b> and click <b>Add endpoint</b>.</li>
          <li>Paste this URL: <Copy value={webhookUrl} /></li>
          <li>Select only the event type <Copy value={EVENT_TYPE} /></li>
          <li>Save, then copy the <b>signing secret</b>. It starts with <code>whsec_</code>.</li>
          <li>
            In your Vercel project, open <b>Settings → Environment Variables</b> and add <code>RIOT_WEBHOOK_SECRET</code> with this
            secret. When you rotate secrets in Riot, put both secrets in the variable, separated by a comma.
          </li>
          <li>Redeploy (<b>Deployments → ⋯ → Redeploy</b>) and reload this page.</li>
        </ol>
        <div className="shots"><RiotEndpointShot url={webhookUrl} /><VercelEnvShot name="RIOT_WEBHOOK_SECRET" value="whsec_••••••••" /></div>
      </Step>

      <Step n={3} title="Connect Google Workspace" state={googleState}
        summary={status.google === "invalid" ? "GOOGLE_SERVICE_ACCOUNT_JSON is set but is not a valid service account key." : googleCheck?.message}>
        <p>Skip this step if your company does not use Google Drive.</p>
        <h3>Create the service account</h3>
        <ol>
          <li>In the <a href="https://console.cloud.google.com/projectcreate" target="_blank" rel="noreferrer">Google Cloud console</a>, create a project, for example <code>riot-sonar-revoker</code>.</li>
          <li>Enable the <a href="https://console.cloud.google.com/apis/library/drive.googleapis.com" target="_blank" rel="noreferrer">Google Drive API</a> in that project.</li>
          <li>Open <b>IAM &amp; Admin → Service Accounts</b> and create a service account. It needs no project role.</li>
          <li>Open it, go to <b>Keys → Add key → Create new key → JSON</b>. A JSON file downloads.</li>
          <li>On the service account details page, copy the <b>Unique ID</b>. This is the OAuth client ID.</li>
        </ol>
        <div className="shots"><figure className="shot"><img src="/tutorial/gcp-enable-drive.jpg" alt="Enable the Google Drive API" loading="lazy" /><figcaption>Enable the Google Drive API</figcaption></figure><figure className="shot"><img src="/tutorial/gcp-create-sa.jpg" alt="Create the service account" loading="lazy" /><figcaption>Create the service account</figcaption></figure></div>
        <GcpKeyShot />
        <h3>Allow it to act on Drive files</h3>
        <ol start={6}>
          <li>As a super admin, open <a href="https://admin.google.com/ac/owl/domainwidedelegation" target="_blank" rel="noreferrer">Admin console → Security → API controls → Domain-wide delegation</a>.</li>
          <li>Click <b>Add new</b>, paste the client ID, and add this scope: <Copy value="https://www.googleapis.com/auth/drive" /></li>
        </ol>
        <figure className="shot narrow"><img src="/tutorial/google-delegation.jpg" alt="Add new client ID with the Drive scope" loading="lazy" /><figcaption>Add new client ID with the Drive scope</figcaption></figure>
        <h3>Give the key to this app</h3>
        <ol start={8}>
          <li>Add the environment variable <code>GOOGLE_SERVICE_ACCOUNT_JSON</code> and paste the full content of the JSON file.</li>
          <li>Redeploy and reload this page. Then run the check below with the email of any user in your domain.</li>
        </ol>
        <div className="check">
          <input type="email" placeholder="someone@yourcompany.com" value={googleEmail} onChange={(e) => setGoogleEmail(e.target.value)} />
          <button type="button" disabled={status.google !== "ok" || busy !== null} onClick={() => check("google")}>
            {busy === "google" ? "Checking…" : "Check Google"}
          </button>
        </div>
        {googleCheck && <p className={googleCheck.ok ? "ok" : "ko"}>{googleCheck.message}</p>}
        {status.google === "missing" && (
          <Tick id="skip-google" manual={manual} toggle={toggle}>We do not use Google Drive</Tick>
        )}
        <p className="note">Delegation can take a few minutes to apply after you save it in the Admin console.</p>
      </Step>

      <Step n={4} title="Connect Microsoft 365" state={msState}
        summary={status.microsoft === "partial" ? "MS_TENANT_ID, MS_CLIENT_ID and MS_CLIENT_SECRET must all be set." : msCheck?.message}>
        <p>Skip this step if your company does not use OneDrive or SharePoint.</p>
        <ol>
          <li>In the <a href="https://entra.microsoft.com/#view/Microsoft_AAD_RegisteredApps/ApplicationsListBlade" target="_blank" rel="noreferrer">Entra admin center</a>, open <b>App registrations → New registration</b>. Name it <code>Riot Sonar Revoker</code>, keep <b>single tenant</b>, and leave the redirect URI empty.</li>
          <li>Open <b>API permissions → Add a permission → Microsoft Graph → Application permissions</b> and add <Copy value="Files.ReadWrite.All" /></li>
          <li>Remove the default <code>User.Read</code> delegated permission, which this app does not need.</li>
          <li>Click <b>Grant admin consent</b>. The status column must show a green check.</li>
          <li className="bare"><EntraPermissionsShot /></li>
          <li>Open <b>Certificates &amp; secrets → New client secret</b> and copy its <b>Value</b> right away. Note its expiry date: the app stops working when it expires.</li>
          <li>From the <b>Overview</b> page, copy the <b>Directory (tenant) ID</b> and the <b>Application (client) ID</b>.</li>
          <li className="bare"><EntraSecretShot /></li>
          <li>Add three environment variables: <code>MS_TENANT_ID</code>, <code>MS_CLIENT_ID</code> and <code>MS_CLIENT_SECRET</code>.</li>
          <li>Redeploy, reload this page, and run the check.</li>
        </ol>
        <div className="check">
          <button type="button" disabled={status.microsoft !== "ok" || busy !== null} onClick={() => check("microsoft")}>
            {busy === "microsoft" ? "Checking…" : "Check Microsoft"}
          </button>
        </div>
        {msCheck && <p className={msCheck.ok ? "ok" : "ko"}>{msCheck.message}</p>}
        {status.microsoft === "missing" && (
          <Tick id="skip-microsoft" manual={manual} toggle={toggle}>We do not use OneDrive or SharePoint</Tick>
        )}
      </Step>

      <Step n={5} title="Send a test event from Riot" state={testState}>
        {!providerReady && <p className="note">Finish steps 3 and 4 first. A test event only checks the signature, not your Google or Microsoft access.</p>}
        <ol>
          <li>In Riot, open the endpoint you created and click <b>Send test event</b>.</li>
          <li>The delivery must show status <b>200</b>. This app recognizes test events and does not revoke anything for them.</li>
          <li>A <b>401</b> means the secret in <code>RIOT_WEBHOOK_SECRET</code> does not match the one in Riot.</li>
        </ol>
        <RiotTestShot />
        <Tick id="riot-test" manual={manual} toggle={toggle}>Riot shows a successful test delivery</Tick>
      </Step>

      <Step n={6} title="Ask Riot to switch your workspace to webhook mode" state={activeState}>
        <p>
          Contact your Riot account manager to switch Sonar revocations to webhook mode. From then on, every revocation made in the
          Riot Hub, in the employee Portal, or by auto-revocation, is sent to this app. Riot will then only ask for read-only scopes.
        </p>
        <p>
          To follow revocations, open your Vercel project logs. Each request logs the drive item, the permission and the outcome:{" "}
          <code>revoked</code>, <code>already_gone</code>, or <code>skipped</code> for permissions inherited from a parent folder.
          Failures return an error to Riot, which retries for about three days.
        </p>
        <Tick id="riot-enabled" manual={manual} toggle={toggle}>Riot confirmed webhook mode is on</Tick>
      </Step>
    </main>
  );
}
