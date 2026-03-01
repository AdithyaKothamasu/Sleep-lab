import { z } from "zod";

// ── Sync request (iOS app → Worker) ───────────────────────────

const syncEventSchema = z.object({
    name: z.string().min(1),
    timestampISO: z.string().datetime(),
    note: z.string().nullable().optional(),
    minutesBeforeMainSleepStart: z.number().nullable().optional()
});

const syncStageDurationSchema = z.object({
    stage: z.string().min(1),
    hours: z.number().min(0)
});

const syncSegmentSchema = z.object({
    stage: z.string().min(1),
    startISO: z.string().datetime(),
    endISO: z.string().datetime(),
    durationMinutes: z.number().min(0)
});

const syncSleepMetricsSchema = z.object({
    totalSleepHours: z.number().min(0),
    awakeningCount: z.number().min(0),
    mainSleepStartISO: z.string().datetime().nullable(),
    mainSleepEndISO: z.string().datetime().nullable(),
    averageHeartRate: z.number().nullable(),
    averageHRV: z.number().nullable(),
    averageRespiratoryRate: z.number().nullable(),
    workoutMinutes: z.number().nullable(),
    averageSpO2: z.number().nullable().optional(),
    restingHeartRate: z.number().nullable().optional()
});

const syncDaySchema = z.object({
    dayLabel: z.string(),
    dayStartISO: z.string().datetime(),
    sleep: syncSleepMetricsSchema,
    stageDurations: z.array(syncStageDurationSchema),
    segments: z.array(syncSegmentSchema),
    events: z.array(syncEventSchema)
});

export const dataSyncRequestSchema = z.object({
    days: z.array(syncDaySchema).min(1).max(30)
});

export type DataSyncRequest = z.infer<typeof dataSyncRequestSchema>;
export type SyncDay = z.infer<typeof syncDaySchema>;

// ── Agent key registration (iOS app → Worker) ─────────────────

export const agentRegisterResponseSchema = z.object({
    apiKey: z.string(),
    connectionCode: z.string()
});

// ── Agent data query params ───────────────────────────────────

export const sleepQuerySchema = z.object({
    days: z.coerce.number().int().min(1).max(30).optional()
});

export const sleepRangeQuerySchema = z.object({
    from: z.string().regex(/^\d{4}-\d{2}-\d{2}$/),
    to: z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
});

export const sleepDateParamSchema = z.object({
    date: z.string().regex(/^\d{4}-\d{2}-\d{2}$/)
});
