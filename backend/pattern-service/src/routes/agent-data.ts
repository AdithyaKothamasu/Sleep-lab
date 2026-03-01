import type { Env, ServiceConfig } from "../config";
import { decrypt, unwrapDEK } from "../crypto";
import { validateApiKey, type AgentKeyRecord } from "../auth/agent-auth";
import { errorResponse, jsonResponse } from "../util/http";

interface SleepDayRow {
    id: string;
    install_id: string;
    day_date: string;
    data_enc: string;
    iv: string;
    tag: string;
    synced_at: string;
}

interface EventRow {
    id: string;
    install_id: string;
    day_date: string;
    data_enc: string;
    iv: string;
    tag: string;
    synced_at: string;
}

/**
 * Extract and validate the API key from the Authorization header.
 * Returns the key record or an error Response.
 */
async function authenticateAgent(
    request: Request,
    env: Env
): Promise<{ record: AgentKeyRecord } | { error: Response }> {
    const bearer = request.headers.get("Authorization");
    if (!bearer?.startsWith("Bearer ")) {
        return { error: errorResponse(401, "Missing bearer token") };
    }

    const apiKey = bearer.replace("Bearer ", "").trim();
    const record = await validateApiKey(apiKey, env);
    if (!record) {
        return { error: errorResponse(401, "Invalid API key") };
    }

    return { record };
}

/**
 * Decrypt a D1 row's encrypted data using the user's DEK.
 */
async function decryptRow(row: SleepDayRow | EventRow, dek: CryptoKey): Promise<unknown> {
    const plaintext = await decrypt(
        { ciphertext: row.data_enc, iv: row.iv, tag: row.tag },
        dek
    );
    return JSON.parse(plaintext);
}

// ── GET /v1/data/sleep?days=N ─────────────────────────────────

export async function handleGetSleep(request: Request, env: Env, config: ServiceConfig): Promise<Response> {
    const auth = await authenticateAgent(request, env);
    if ("error" in auth) return auth.error;

    const url = new URL(request.url);
    const days = Math.min(Math.max(parseInt(url.searchParams.get("days") || "7", 10), 1), 30);

    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString().substring(0, 10);
    const dek = await unwrapDEK(auth.record.wrappedDek, config.encryptionKek);

    const result = await env.SLEEP_DATA.prepare(
        "SELECT * FROM sleep_days WHERE install_id = ? AND day_date >= ? ORDER BY day_date DESC"
    ).bind(auth.record.installId, cutoff).all<SleepDayRow>();

    const decryptedDays = await Promise.all(
        (result.results || []).map(async (row) => ({
            date: row.day_date,
            syncedAt: row.synced_at,
            ...(await decryptRow(row, dek) as Record<string, unknown>)
        }))
    );

    return jsonResponse(200, {
        days: decryptedDays,
        count: decryptedDays.length
    });
}

// ── GET /v1/data/sleep/:date ──────────────────────────────────

export async function handleGetSleepByDate(
    request: Request,
    env: Env,
    config: ServiceConfig,
    date: string
): Promise<Response> {
    const auth = await authenticateAgent(request, env);
    if ("error" in auth) return auth.error;

    if (!/^\d{4}-\d{2}-\d{2}$/.test(date)) {
        return errorResponse(400, "Invalid date format. Use YYYY-MM-DD.");
    }

    const dek = await unwrapDEK(auth.record.wrappedDek, config.encryptionKek);

    const sleepRow = await env.SLEEP_DATA.prepare(
        "SELECT * FROM sleep_days WHERE install_id = ? AND day_date = ?"
    ).bind(auth.record.installId, date).first<SleepDayRow>();

    if (!sleepRow) {
        return errorResponse(404, "No sleep data found for this date");
    }

    const eventRow = await env.SLEEP_DATA.prepare(
        "SELECT * FROM behavior_events WHERE install_id = ? AND day_date = ?"
    ).bind(auth.record.installId, date).first<EventRow>();

    const sleepData = await decryptRow(sleepRow, dek) as Record<string, unknown>;
    const events = eventRow ? await decryptRow(eventRow, dek) : [];

    return jsonResponse(200, {
        date,
        syncedAt: sleepRow.synced_at,
        ...sleepData,
        events
    });
}

// ── GET /v1/data/sleep/range?from=&to= ───────────────────────

export async function handleGetSleepRange(request: Request, env: Env, config: ServiceConfig): Promise<Response> {
    const auth = await authenticateAgent(request, env);
    if ("error" in auth) return auth.error;

    const url = new URL(request.url);
    const from = url.searchParams.get("from");
    const to = url.searchParams.get("to");

    if (!from || !to || !/^\d{4}-\d{2}-\d{2}$/.test(from) || !/^\d{4}-\d{2}-\d{2}$/.test(to)) {
        return errorResponse(400, "Both 'from' and 'to' query params required in YYYY-MM-DD format");
    }

    if (from > to) {
        return errorResponse(400, "'from' date must be before or equal to 'to' date");
    }

    const dek = await unwrapDEK(auth.record.wrappedDek, config.encryptionKek);

    const sleepResult = await env.SLEEP_DATA.prepare(
        "SELECT * FROM sleep_days WHERE install_id = ? AND day_date >= ? AND day_date <= ? ORDER BY day_date ASC"
    ).bind(auth.record.installId, from, to).all<SleepDayRow>();

    const eventResult = await env.SLEEP_DATA.prepare(
        "SELECT * FROM behavior_events WHERE install_id = ? AND day_date >= ? AND day_date <= ? ORDER BY day_date ASC"
    ).bind(auth.record.installId, from, to).all<EventRow>();

    // Index events by date for efficient lookup
    const eventsByDate = new Map<string, EventRow>();
    for (const row of eventResult.results || []) {
        eventsByDate.set(row.day_date, row);
    }

    const decryptedDays = await Promise.all(
        (sleepResult.results || []).map(async (row) => {
            const sleepData = await decryptRow(row, dek) as Record<string, unknown>;
            const eventRow = eventsByDate.get(row.day_date);
            const events = eventRow ? await decryptRow(eventRow, dek) : [];

            return {
                date: row.day_date,
                syncedAt: row.synced_at,
                ...sleepData,
                events
            };
        })
    );

    return jsonResponse(200, {
        from,
        to,
        days: decryptedDays,
        count: decryptedDays.length
    });
}

// ── GET /v1/data/sleep/stats?days=N ──────────────────────────

export async function handleGetSleepStats(request: Request, env: Env, config: ServiceConfig): Promise<Response> {
    const auth = await authenticateAgent(request, env);
    if ("error" in auth) return auth.error;

    const url = new URL(request.url);
    const days = Math.min(Math.max(parseInt(url.searchParams.get("days") || "14", 10), 1), 30);

    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString().substring(0, 10);
    const dek = await unwrapDEK(auth.record.wrappedDek, config.encryptionKek);

    const result = await env.SLEEP_DATA.prepare(
        "SELECT * FROM sleep_days WHERE install_id = ? AND day_date >= ? ORDER BY day_date DESC"
    ).bind(auth.record.installId, cutoff).all<SleepDayRow>();

    if (!result.results || result.results.length === 0) {
        return jsonResponse(200, { days: 0, message: "No data available for the requested period" });
    }

    // Decrypt all and compute aggregates
    const allData: Array<{ sleep: { totalSleepHours: number; awakeningCount: number; averageHeartRate: number | null; averageHRV: number | null; averageRespiratoryRate: number | null; workoutMinutes: number | null }; stageDurations: Array<{ stage: string; hours: number }> }> = [];

    for (const row of result.results) {
        const data = await decryptRow(row, dek) as typeof allData[number];
        allData.push(data);
    }

    const count = allData.length;

    const avg = (values: (number | null)[]): number | null => {
        const valid = values.filter((v): v is number => v !== null && v !== undefined);
        if (valid.length === 0) return null;
        return Math.round((valid.reduce((a, b) => a + b, 0) / valid.length) * 100) / 100;
    };

    const stageAverages: Record<string, number> = {};
    for (const day of allData) {
        for (const sd of day.stageDurations || []) {
            stageAverages[sd.stage] = (stageAverages[sd.stage] || 0) + sd.hours;
        }
    }
    for (const stage of Object.keys(stageAverages)) {
        stageAverages[stage] = Math.round((stageAverages[stage] / count) * 100) / 100;
    }

    return jsonResponse(200, {
        period: { days, dataPoints: count },
        averages: {
            totalSleepHours: avg(allData.map((d) => d.sleep.totalSleepHours)),
            awakeningCount: avg(allData.map((d) => d.sleep.awakeningCount)),
            heartRate: avg(allData.map((d) => d.sleep.averageHeartRate)),
            hrv: avg(allData.map((d) => d.sleep.averageHRV)),
            respiratoryRate: avg(allData.map((d) => d.sleep.averageRespiratoryRate)),
            workoutMinutes: avg(allData.map((d) => d.sleep.workoutMinutes))
        },
        averageStageDurations: stageAverages
    });
}

// ── GET /v1/data/events?days=N ────────────────────────────────

export async function handleGetEvents(request: Request, env: Env, config: ServiceConfig): Promise<Response> {
    const auth = await authenticateAgent(request, env);
    if ("error" in auth) return auth.error;

    const url = new URL(request.url);
    const days = Math.min(Math.max(parseInt(url.searchParams.get("days") || "7", 10), 1), 30);

    const cutoff = new Date(Date.now() - days * 24 * 60 * 60 * 1000).toISOString().substring(0, 10);
    const dek = await unwrapDEK(auth.record.wrappedDek, config.encryptionKek);

    const result = await env.SLEEP_DATA.prepare(
        "SELECT * FROM behavior_events WHERE install_id = ? AND day_date >= ? ORDER BY day_date DESC"
    ).bind(auth.record.installId, cutoff).all<EventRow>();

    const decryptedEvents = await Promise.all(
        (result.results || []).map(async (row) => ({
            date: row.day_date,
            events: await decryptRow(row, dek)
        }))
    );

    return jsonResponse(200, {
        days: decryptedEvents,
        count: decryptedEvents.length
    });
}
