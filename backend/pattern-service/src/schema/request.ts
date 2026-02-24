import { z } from "zod";

const stageSchema = z.enum(["awake", "rem", "core", "deep", "inBed"]);

const eventSchema = z.object({
  name: z.string().min(1),
  timestampISO: z.string().datetime(),
  note: z.string().nullable().optional(),
  minutesBeforeMainSleepStart: z.number().nullable()
});

const stageDurationSchema = z.object({
  stage: stageSchema,
  hours: z.number().min(0)
});

const sleepSegmentSchema = z.object({
  stage: stageSchema,
  startISO: z.string().datetime(),
  endISO: z.string().datetime(),
  durationMinutes: z.number().min(0)
});

const sleepMetricsSchema = z.object({
  totalSleepHours: z.number().min(0),
  awakeningCount: z.number().min(0),
  mainSleepStartISO: z.string().datetime().nullable(),
  mainSleepEndISO: z.string().datetime().nullable(),
  averageHeartRate: z.number().nullable(),
  averageHRV: z.number().nullable(),
  averageRespiratoryRate: z.number().nullable(),
  workoutMinutes: z.number().nullable()
});

const daySchema = z.object({
  dayLabel: z.string(),
  dayStartISO: z.string().datetime(),
  sleep: sleepMetricsSchema,
  stageDurations: z.array(stageDurationSchema),
  segments: z.array(sleepSegmentSchema),
  events: z.array(eventSchema)
});

export const patternAnalysisRequestSchema = z.object({
  selectedDates: z.array(daySchema).min(2).max(5)
});

export type PatternAnalysisRequest = z.infer<typeof patternAnalysisRequestSchema>;
