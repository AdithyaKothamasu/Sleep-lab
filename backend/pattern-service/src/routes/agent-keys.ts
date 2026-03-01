import type { Env, ServiceConfig } from "../config";
import { generateDEK, wrapDEK } from "../crypto";
import { generateApiKey, registerApiKey, revokeApiKey, findApiKeyByInstallId } from "../auth/agent-auth";
import { verifySignedToken } from "../auth/jwt";
import { errorResponse, jsonResponse } from "../util/http";

/**
 * POST /v1/agent/register
 *
 * Called by the iOS app to create or regenerate an API key.
 * Auth: existing JWT (same as pattern analysis).
 * Returns the API key and a connection code for easy agent pairing.
 */
export async function handleAgentRegister(request: Request, env: Env, config: ServiceConfig): Promise<Response> {
    const bearer = request.headers.get("Authorization");
    if (!bearer?.startsWith("Bearer ")) {
        return errorResponse(401, "Missing bearer token");
    }

    const token = bearer.replace("Bearer ", "").trim();
    let installId: string;
    try {
        const claims = await verifySignedToken(config.jwtSigningSecret, token);
        if (claims.typ !== "access") {
            return errorResponse(401, "Invalid token type");
        }
        installId = claims.sub;
    } catch (error) {
        return errorResponse(401, "Invalid token", String(error));
    }

    // Check if there's already an API key for this install — if so, revoke it first
    const existingKey = await findApiKeyByInstallId(installId, env);
    if (existingKey) {
        await revokeApiKey(existingKey, env);
    }

    // Generate DEK and API key
    const dekRaw = await generateDEK();
    const wrappedDek = await wrapDEK(dekRaw, config.encryptionKek);
    const apiKey = generateApiKey();

    // Store in KV
    await registerApiKey(apiKey, installId, wrappedDek, env);

    // Build the connection code for easy paste into agent
    const baseUrl = new URL(request.url).origin;
    const connectionCode = `sleeplab://connect/${apiKey}@${baseUrl}`;

    return jsonResponse(200, {
        apiKey,
        connectionCode
    });
}

/**
 * DELETE /v1/agent/revoke
 *
 * Revokes the API key and deletes ALL synced data for this install.
 * Auth: existing JWT.
 */
export async function handleAgentRevoke(request: Request, env: Env, config: ServiceConfig): Promise<Response> {
    const bearer = request.headers.get("Authorization");
    if (!bearer?.startsWith("Bearer ")) {
        return errorResponse(401, "Missing bearer token");
    }

    const token = bearer.replace("Bearer ", "").trim();
    let installId: string;
    try {
        const claims = await verifySignedToken(config.jwtSigningSecret, token);
        if (claims.typ !== "access") {
            return errorResponse(401, "Invalid token type");
        }
        installId = claims.sub;
    } catch (error) {
        return errorResponse(401, "Invalid token", String(error));
    }

    // Find and revoke the API key
    const existingKey = await findApiKeyByInstallId(installId, env);
    if (existingKey) {
        await revokeApiKey(existingKey, env);
    }

    // Delete all synced data for this install from D1
    await env.SLEEP_DATA.prepare("DELETE FROM sleep_days WHERE install_id = ?")
        .bind(installId)
        .run();
    await env.SLEEP_DATA.prepare("DELETE FROM behavior_events WHERE install_id = ?")
        .bind(installId)
        .run();

    return jsonResponse(200, {
        revoked: true,
        installId
    });
}
