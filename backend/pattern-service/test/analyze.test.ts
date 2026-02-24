import { describe, expect, it } from "vitest";
import { patternAnalysisRequestSchema } from "../src/schema/request";
import { fallbackResponse, patternAnalysisResponseSchema } from "../src/schema/response";

describe("analysis schema", () => {
  it("accepts a complete request payload", () => {
    const sample = {
      selectedDates: [
        {
          dayLabel: "Feb 20",
          dayStartISO: "2026-02-20T00:00:00.000Z",
          sleep: {
            totalSleepHours: 7.8,
            awakeningCount: 3,
            mainSleepStartISO: "2026-02-20T01:00:00.000Z",
            mainSleepEndISO: "2026-02-20T09:00:00.000Z",
            averageHeartRate: 53,
            averageHRV: 61,
            averageRespiratoryRate: 15.8,
            workoutMinutes: 45
          },
          stageDurations: [{ stage: "core", hours: 4.2 }],
          segments: [
            {
              stage: "core",
              startISO: "2026-02-20T01:00:00.000Z",
              endISO: "2026-02-20T02:00:00.000Z",
              durationMinutes: 60
            }
          ],
          events: [
            {
              name: "Dinner",
              timestampISO: "2026-02-19T19:30:00.000Z",
              note: null,
              minutesBeforeMainSleepStart: 330
            }
          ]
        },
        {
          dayLabel: "Feb 21",
          dayStartISO: "2026-02-21T00:00:00.000Z",
          sleep: {
            totalSleepHours: 7.1,
            awakeningCount: 4,
            mainSleepStartISO: "2026-02-21T01:00:00.000Z",
            mainSleepEndISO: "2026-02-21T08:30:00.000Z",
            averageHeartRate: 55,
            averageHRV: 58,
            averageRespiratoryRate: 16.1,
            workoutMinutes: 0
          },
          stageDurations: [{ stage: "core", hours: 3.9 }],
          segments: [
            {
              stage: "core",
              startISO: "2026-02-21T01:00:00.000Z",
              endISO: "2026-02-21T02:00:00.000Z",
              durationMinutes: 60
            }
          ],
          events: []
        }
      ]
    };

    const parsed = patternAnalysisRequestSchema.safeParse(sample);
    expect(parsed.success).toBe(true);
  });

  it("validates and produces fallback response", () => {
    const fallback = fallbackResponse("schema fail");
    const parsed = patternAnalysisResponseSchema.safeParse(fallback);

    expect(parsed.success).toBe(true);
    expect(parsed.data?.noClearPattern).toBe(true);
  });
});
