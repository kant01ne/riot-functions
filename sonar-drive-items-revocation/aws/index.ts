import { route } from "../lib/router";

// API Gateway HTTP API payload format 2.0. SAR does not accept Lambda function URLs, so the template uses an HTTP API.
export type HttpApiEvent = {
  rawPath: string;
  rawQueryString?: string;
  headers?: Record<string, string | undefined>;
  cookies?: string[];
  body?: string;
  isBase64Encoded?: boolean;
  requestContext: { domainName: string; http: { method: string } };
};

export type HttpApiResult = { statusCode: number; headers: Record<string, string>; body: string };

export function toRequest(event: HttpApiEvent): Request {
  const { domainName, http } = event.requestContext;
  const query = event.rawQueryString ? `?${event.rawQueryString}` : "";
  const headers = new Headers();
  for (const [name, value] of Object.entries(event.headers ?? {})) if (value !== undefined) headers.set(name, value);
  // The signature covers the exact bytes Riot sent, so decode before anything reads the body.
  const body = event.body === undefined ? undefined : event.isBase64Encoded ? Buffer.from(event.body, "base64") : event.body;
  const hasBody = http.method !== "GET" && http.method !== "HEAD";
  return new Request(`https://${domainName}${event.rawPath}${query}`, { method: http.method, headers, body: hasBody ? body : undefined });
}

export async function handler(event: HttpApiEvent): Promise<HttpApiResult> {
  const response = await route(toRequest(event));
  return { statusCode: response.status, headers: Object.fromEntries(response.headers), body: await response.text() };
}
