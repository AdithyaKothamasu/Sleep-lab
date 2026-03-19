import { describe, expect, it } from "vitest";
import { dataSyncRequestSchema } from "../src/schema/agent";

const sampleDay = {
  dayLabel: "Mar 19",
  dayStartISO: "2026-03-19T00:00:00.000Z",
  sleep: {
    totalSleepHours: 7.5,
    awakeningCount: 1,
    mainSleepStartISO: "2026-03-18T17:30:00.000Z",
    mainSleepEndISO: "2026-03-19T01:00:00.000Z",
    averageHeartRate: 58,
    averageHRV: 42,
    averageRespiratoryRate: 14,
    workoutMinutes: 30,
    averageSpO2: 97,
    restingHeartRate: 52
  },
  stageDurations: [
    { stage: "deep", hours: 1.5 },
    { stage: "rem", hours: 1.75 }
  ],
  segments: [
    {
      stage: "core",
      startISO: "2026-03-18T17:30:00.000Z",
      endISO: "2026-03-18T19:00:00.000Z",
      durationMinutes: 90
    }
  ],
  events: [
    {
      name: "Workout",
      timestampISO: "2026-03-18T12:00:00.000Z",
      note: "Moderate intensity",
      minutesBeforeMainSleepStart: 330
    }
  ]
};

describe("dataSyncRequestSchema", () => {
  it("accepts the current sync payload shape", () => {
    const parsed = dataSyncRequestSchema.safeParse({
      days: [sampleDay]
    });

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.days).toHaveLength(1);
    }
  });

  it("accepts legacy selectedDates payloads", () => {
    const parsed = dataSyncRequestSchema.safeParse({
      selectedDates: [sampleDay]
    });

    expect(parsed.success).toBe(true);
    if (parsed.success) {
      expect(parsed.data.days).toEqual([sampleDay]);
    }
  });

  it("still rejects payloads missing both days and selectedDates", () => {
    const parsed = dataSyncRequestSchema.safeParse({});

    expect(parsed.success).toBe(false);
  });

  it("accepts days where optional sleep metrics are omitted", () => {
    const parsed = dataSyncRequestSchema.safeParse({
      days: [
        {
          ...sampleDay,
          sleep: {
            totalSleepHours: 6.5,
            awakeningCount: 2
          }
        }
      ]
    });

    expect(parsed.success).toBe(true);
  });
});
