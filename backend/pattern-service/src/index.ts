import { z } from "zod";
import { createChallengeToken, verifyChallengeToken } from "./auth/challenge";
import { epochToIso, issueSignedToken, verifySignedToken } from "./auth/jwt";
import { verifyEd25519Signature } from "./auth/signature";
import { readConfig, type Env } from "./config";
import { handleAnalyze } from "./routes/analyze";
import { errorResponse, jsonResponse, optionsResponse, parseJSON } from "./util/http";

const challengeRequestSchema = z.object({
  installId: z.string().uuid().optional(),
  publicKey: z.string().min(1)
});

const exchangeRequestSchema = z.object({
  installId: z.string().uuid(),
  publicKey: z.string().min(1),
  challengeToken: z.string().min(1),
  signature: z.string().min(1)
});

const ACCESS_TTL_SECONDS = 15 * 60;

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    if (request.method === "OPTIONS") {
      return optionsResponse();
    }

    const url = new URL(request.url);

    let config;
    try {
      config = readConfig(env);
    } catch (error) {
      return errorResponse(500, "Server misconfiguration", String(error));
    }

    if (request.method === "POST" && url.pathname === "/v1/auth/challenge") {
      return handleChallenge(request, env, config.challengeSigningSecret);
    }

    if (request.method === "POST" && url.pathname === "/v1/auth/exchange") {
      return handleExchange(request, env, config.challengeSigningSecret, config.jwtSigningSecret);
    }

    if (request.method === "POST" && url.pathname === "/v1/patterns/analyze") {
      const bearer = request.headers.get("Authorization");
      if (!bearer?.startsWith("Bearer ")) {
        return errorResponse(401, "Missing bearer token");
      }

      const token = bearer.replace("Bearer ", "").trim();
      try {
        const claims = await verifySignedToken(config.jwtSigningSecret, token);
        if (claims.typ !== "access") {
          return errorResponse(401, "Invalid token type");
        }
      } catch (error) {
        return errorResponse(401, "Invalid token", String(error));
      }

      return handleAnalyze(request, env, config);
    }

    return errorResponse(404, "Not found");
  }
};

async function handleChallenge(request: Request, env: Env, challengeSigningSecret: string): Promise<Response> {
  let body: unknown;
  try {
    body = await parseJSON(request);
  } catch (error) {
    return errorResponse(400, "Invalid request body", String(error));
  }

  const parsed = challengeRequestSchema.safeParse(body);
  if (!parsed.success) {
    return errorResponse(400, "Invalid challenge payload", parsed.error.flatten());
  }

  const installId = parsed.data.installId ?? crypto.randomUUID();
  const { publicKey } = parsed.data;

  await env.INSTALL_KEYS.put(installId, publicKey);

  const challenge = await createChallengeToken(challengeSigningSecret, installId, publicKey);

  return jsonResponse(200, {
    installId,
    challengeToken: challenge.token,
    expiresAt: epochToIso(challenge.expiresAtEpoch)
  });
}

async function handleExchange(
  request: Request,
  env: Env,
  challengeSigningSecret: string,
  jwtSigningSecret: string
): Promise<Response> {
  let body: unknown;
  try {
    body = await parseJSON(request);
  } catch (error) {
    return errorResponse(400, "Invalid request body", String(error));
  }

  const parsed = exchangeRequestSchema.safeParse(body);
  if (!parsed.success) {
    return errorResponse(400, "Invalid exchange payload", parsed.error.flatten());
  }

  const payload = parsed.data;

  let challengeClaims;
  try {
    challengeClaims = await verifyChallengeToken(challengeSigningSecret, payload.challengeToken);
  } catch (error) {
    return errorResponse(401, "Invalid challenge token", String(error));
  }

  if (challengeClaims.installId !== payload.installId || challengeClaims.publicKey !== payload.publicKey) {
    return errorResponse(401, "Challenge payload mismatch");
  }

  const storedKey = await env.INSTALL_KEYS.get(payload.installId);
  if (!storedKey || storedKey !== payload.publicKey) {
    return errorResponse(401, "Unrecognized install key");
  }

  const validSignature = await verifyEd25519Signature(payload.publicKey, payload.challengeToken, payload.signature);
  if (!validSignature) {
    return errorResponse(401, "Invalid signature");
  }

  const access = await issueSignedToken(jwtSigningSecret, {
    subject: payload.installId,
    type: "access",
    ttlSeconds: ACCESS_TTL_SECONDS,
    additionalClaims: {
      scope: "patterns:analyze"
    }
  });

  return jsonResponse(200, {
    accessToken: access.token,
    expiresAt: epochToIso(access.expiresAtEpoch)
  });
}
