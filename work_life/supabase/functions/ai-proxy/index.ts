const jsonHeaders = {
  "content-type": "application/json; charset=utf-8",
  "cache-control": "no-store",
};

const allowedOperations = new Set([
  "suggest",
  "structured_completion",
  "schedule_image",
]);
const maxBodyBytes = 7 * 1024 * 1024;

function safeError(status: number, message: string): Response {
  return new Response(JSON.stringify({ error: { message } }), {
    status,
    headers: jsonHeaders,
  });
}

Deno.serve(async (request) => {
  if (request.method !== "POST") {
    return safeError(405, "Method not allowed.");
  }
  const length = Number(request.headers.get("content-length") ?? "0");
  if (length > maxBodyBytes) return safeError(413, "Request is too large.");

  const auth = request.headers.get("authorization");
  if (!auth?.startsWith("Bearer ")) {
    return safeError(401, "Sign in is required.");
  }
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY");
  const providerKey = Deno.env.get("AIMLAPI_KEY");
  const providerUrl =
    Deno.env.get("AIMLAPI_BASE_URL") ?? "https://api.aimlapi.com/v1";
  if (!supabaseUrl || !publishableKey || !providerKey) {
    return safeError(503, "AI service is not configured.");
  }

  const userResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
    headers: { authorization: auth, apikey: publishableKey },
  });
  if (!userResponse.ok) return safeError(401, "Your session is not valid.");

  let text: string;
  try {
    text = await request.text();
  } catch {
    return safeError(400, "Could not read the request.");
  }
  if (new TextEncoder().encode(text).length > maxBodyBytes) {
    return safeError(413, "Request is too large.");
  }

  let body: { operation?: unknown; request?: unknown };
  try {
    body = JSON.parse(text);
  } catch {
    return safeError(400, "Request must be valid JSON.");
  }
  if (
    typeof body.operation !== "string" ||
    !allowedOperations.has(body.operation) ||
    typeof body.request !== "object" ||
    body.request === null ||
    Array.isArray(body.request)
  ) {
    return safeError(400, "Invalid AI request.");
  }
  const providerRequest = body.request as Record<string, unknown>;
  if (
    typeof providerRequest.model !== "string" ||
    providerRequest.model.length > 160 ||
    !Array.isArray(providerRequest.messages) ||
    providerRequest.messages.length < 1 ||
    providerRequest.messages.length > 16
  ) {
    return safeError(400, "Invalid AI request fields.");
  }

  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 30_000);
  try {
    const upstream = await fetch(`${providerUrl}/chat/completions`, {
      method: "POST",
      signal: controller.signal,
      headers: {
        authorization: `Bearer ${providerKey}`,
        "content-type": "application/json",
      },
      body: JSON.stringify(providerRequest),
    });
    if (!upstream.ok) {
      const status = upstream.status === 429 ? 429 : upstream.status >= 500
        ? 503
        : 502;
      return safeError(status, "AI provider could not complete the request.");
    }
    return new Response(await upstream.text(), {
      status: 200,
      headers: jsonHeaders,
    });
  } catch (error) {
    if (error instanceof DOMException && error.name === "AbortError") {
      return safeError(504, "AI request timed out.");
    }
    return safeError(503, "AI service is temporarily unavailable.");
  } finally {
    clearTimeout(timeout);
  }
});
