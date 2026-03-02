import type { Env, ServiceConfig } from "../config";
import { validateApiKey } from "../auth/agent-auth";
import { errorResponse, jsonResponse } from "../util/http";

/**
 * GET /v1/agent/instructions
 *
 * Returns the agent skill instructions as structured JSON.
 * Auth: API key (same as agent data queries).
 */
export async function handleGetInstructions(request: Request, env: Env, _config: ServiceConfig): Promise<Response> {
    const bearer = request.headers.get("Authorization");
    if (!bearer?.startsWith("Bearer ")) {
        return errorResponse(401, "Missing bearer token");
    }

    const apiKey = bearer.replace("Bearer ", "").trim();
    const record = await validateApiKey(apiKey, env);
    if (!record) {
        return errorResponse(401, "Invalid API key");
    }

    return jsonResponse(200, {
        name: "SleepLab Agent",
        version: "1.0",
        description: "Query your SleepLab sleep tracking data securely.",
        setup: {
            connectionCodeFormat: "sleeplab://connect/<API_KEY>@<BASE_URL>",
            instructions: [
                "Extract the API key (between /connect/ and @)",
                "Extract the base URL (after @)",
                "Use the API key as a Bearer token in the Authorization header for all requests"
            ]
        },
        endpoints: [
            {
                name: "Get Recent Sleep Data",
                method: "GET",
                path: "/v1/data/sleep?days=N",
                description: "Returns the last N days (1-30) of sleep summaries including total sleep hours, sleep stages, heart rate, HRV, respiratory rate, and workout minutes."
            },
            {
                name: "Get Sleep Data for a Specific Date",
                method: "GET",
                path: "/v1/data/sleep/:date",
                description: "Returns full details for a specific day (YYYY-MM-DD) including all sleep segments with timestamps, plus behavior events."
            },
            {
                name: "Get Sleep Data for a Date Range",
                method: "GET",
                path: "/v1/data/sleep/range?from=YYYY-MM-DD&to=YYYY-MM-DD",
                description: "Returns full details for all days between the start and end date (inclusive)."
            },
            {
                name: "Get Aggregated Stats",
                method: "GET",
                path: "/v1/data/sleep/stats?days=N",
                description: "Returns computed averages over the last N days: average sleep duration, HRV, heart rate, respiratory rate, stage durations, etc."
            },
            {
                name: "Get Behavior Events",
                method: "GET",
                path: "/v1/data/events?days=N",
                description: "Returns behavior logs (caffeine intake, workouts, dinner timing, etc.) for the last N days."
            },
            {
                name: "Get Agent Instructions",
                method: "GET",
                path: "/v1/agent/instructions",
                description: "Returns these instructions (this endpoint)."
            }
        ],
        dataFormat: {
            description: "All responses are JSON. Key fields in sleep data:",
            fields: {
                totalSleepHours: "Total time asleep (excluding awake periods)",
                awakeningCount: "Number of times woken up",
                mainSleepStartISO: "When the main sleep window started (ISO 8601 UTC)",
                mainSleepEndISO: "When the main sleep window ended (ISO 8601 UTC)",
                averageHeartRate: "Average heart rate during sleep (bpm)",
                averageHRV: "Heart rate variability SDNN (ms) — higher is generally better",
                averageRespiratoryRate: "Breathing rate (breaths/min)",
                workoutMinutes: "Total exercise duration that day",
                stageDurations: "Time spent in each sleep stage (deep, core, REM, awake) in hours",
                segments: "Individual sleep stage segments with start/end timestamps",
                events: "Behavior logs like caffeine, dinner, workouts with timestamps and minutesBeforeMainSleepStart"
            }
        },
        timezoneHandling: {
            important: true,
            description: "All timestamps (dayStartISO, timestampISO, mainSleepStartISO, etc.) are in UTC. The 'date' key on each day is derived from the UTC representation of the user's local midnight, which may be one calendar day behind the user's actual local date. When presenting dates to the user, always convert UTC timestamps to local time. For example, date '2026-02-28' with dayStartISO '2026-02-28T18:30:00.000Z' means the actual local date is 2026-03-01 (UTC+5:30)."
        },
        responseGuidelines: [
            "Use plain language, not technical jargon",
            "Highlight notable patterns (e.g., 'You got more deep sleep on days you worked out')",
            "Compare to general healthy ranges when relevant (e.g., 7-9 hours total, 1-2 hours deep sleep)",
            "If HRV data is available, note that higher HRV generally indicates better recovery",
            "Always mention if data seems incomplete or missing for requested dates"
        ]
    });
}
