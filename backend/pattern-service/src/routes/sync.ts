import type { Env, ServiceConfig } from "../config";
import { encrypt, unwrapDEK } from "../crypto";
import { validateApiKey } from "../auth/agent-auth";
import { dataSyncRequestSchema, type SyncDay } from "../schema/agent";
import { errorResponse, jsonResponse, parseJSON } from "../util/http";
import { verifySignedToken } from "../auth/jwt";

/**
 * POST /v1/data/sync
 *
 * Called by the iOS app after HealthKit data load.
 * Auth: existing JWT (same as pattern analysis).
 * Encrypts each day's data with the user's DEK and upserts into D1.
 */
export async function handleSync(request: Request, env: Env, config: ServiceConfig): Promise<Response> {
    // Authenticate via JWT
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

    // Check if agent access is enabled for this install (API key exists)
    const apiKey = await env.AGENT_KEYS.get(`install:${installId}`);
    if (!apiKey) {
        return errorResponse(403, "Agent access not enabled for this install");
    }

    const keyRecord = await env.AGENT_KEYS.get(apiKey);
    if (!keyRecord) {
        return errorResponse(403, "Agent key record not found");
    }

    const { wrappedDek } = JSON.parse(keyRecord) as { wrappedDek: string };

    // Parse request body
    let body: unknown;
    try {
        body = await parseJSON(request);
    } catch (error) {
        return errorResponse(400, "Invalid request body", String(error));
    }

    const parsed = dataSyncRequestSchema.safeParse(body);
    if (!parsed.success) {
        return errorResponse(400, "Invalid sync payload", parsed.error.flatten());
    }

    // Unwrap DEK
    const dek = await unwrapDEK(wrappedDek, config.encryptionKek);

    // Encrypt and upsert each day
    const now = new Date().toISOString();
    const statements: D1PreparedStatement[] = [];

    for (const day of parsed.data.days) {
        const dateStr = day.dayStartISO.substring(0, 10); // YYYY-MM-DD
        const dayId = `${installId}:${dateStr}`;

        // Separate events from sleep data
        const sleepPayload = {
            dayLabel: day.dayLabel,
            dayStartISO: day.dayStartISO,
            sleep: day.sleep,
            stageDurations: day.stageDurations,
            segments: day.segments
        };

        const encrypted = await encrypt(JSON.stringify(sleepPayload), dek);

        statements.push(
            env.SLEEP_DATA.prepare(
                `INSERT OR REPLACE INTO sleep_days (id, install_id, day_date, data_enc, iv, tag, synced_at)
         VALUES (?, ?, ?, ?, ?, ?, ?)`
            ).bind(dayId, installId, dateStr, encrypted.ciphertext, encrypted.iv, encrypted.tag, now)
        );

        // Store events separately
        if (day.events.length > 0) {
            const eventsEncrypted = await encrypt(JSON.stringify(day.events), dek);
            const eventsId = `${installId}:${dateStr}:events`;

            statements.push(
                env.SLEEP_DATA.prepare(
                    `INSERT OR REPLACE INTO behavior_events (id, install_id, day_date, data_enc, iv, tag, synced_at)
           VALUES (?, ?, ?, ?, ?, ?, ?)`
                ).bind(eventsId, installId, dateStr, eventsEncrypted.ciphertext, eventsEncrypted.iv, eventsEncrypted.tag, now)
            );
        }
    }

    // Execute all in a batch
    if (statements.length > 0) {
        await env.SLEEP_DATA.batch(statements);
    }

    // Cleanup old data (older than 30 days)
    const cutoffDate = new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString().substring(0, 10);
    await env.SLEEP_DATA.prepare("DELETE FROM sleep_days WHERE install_id = ? AND day_date < ?")
        .bind(installId, cutoffDate)
        .run();
    await env.SLEEP_DATA.prepare("DELETE FROM behavior_events WHERE install_id = ? AND day_date < ?")
        .bind(installId, cutoffDate)
        .run();

    return jsonResponse(200, {
        synced: parsed.data.days.length,
        syncedAt: now
    });
}
