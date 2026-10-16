import { afterEach, expect, it, vi } from "vitest";

const send = vi.fn();
vi.mock("@aws-sdk/client-secrets-manager", () => ({
  SecretsManagerClient: vi.fn(() => ({ send })),
  GetSecretValueCommand: vi.fn((input: unknown) => input),
}));

const { handler } = await import("@/aws/index");

const status = () =>
  handler({ rawPath: "/", requestContext: { domainName: "abc.example", http: { method: "GET" } } }).then((res) => JSON.parse(res.body));

afterEach(() => {
  vi.unstubAllEnvs();
  vi.useRealTimers();
});

it("reads the credentials from the stack's secret and reloads them after a minute", async () => {
  vi.useFakeTimers();
  vi.stubEnv("SECRET_ARN", "arn:aws:secretsmanager:eu-west-3:123456789012:secret:riot-sonar-revoker");
  vi.stubEnv("RIOT_WEBHOOK_SECRET", "");
  send.mockResolvedValueOnce({ SecretString: "{}" });
  expect(await status()).toMatchObject({ riotSecret: "missing", microsoft: "missing" });

  send.mockResolvedValueOnce({
    SecretString: JSON.stringify({ RIOT_WEBHOOK_SECRET: "whsec_abc", MS_TENANT_ID: "t", MS_CLIENT_ID: "c", MS_CLIENT_SECRET: "s" }),
  });
  expect(await status()).toMatchObject({ riotSecret: "missing" });
  vi.advanceTimersByTime(60_000);
  expect(await status()).toMatchObject({ riotSecret: "ok", microsoft: "ok" });
  expect(send).toHaveBeenCalledTimes(2);
  expect(send).toHaveBeenLastCalledWith({ SecretId: "arn:aws:secretsmanager:eu-west-3:123456789012:secret:riot-sonar-revoker" });
});
