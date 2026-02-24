import { z } from "zod";

const confidenceSchema = z.enum(["low", "medium", "high"]);

const insightSchema = z.object({
  title: z.string().min(1),
  summary: z.string().min(1),
  confidence: confidenceSchema,
  evidence: z.array(z.string()).default([])
});

export const patternAnalysisResponseSchema = z.object({
  aiSummary: z.string().min(1),
  insights: z.array(insightSchema),
  caveats: z.array(z.string()).default([]),
  noClearPattern: z.boolean()
});

export type PatternAnalysisResponse = z.infer<typeof patternAnalysisResponseSchema>;

export function fallbackResponse(reason: string): PatternAnalysisResponse {
  return {
    aiSummary: "No strong pattern detected from the selected dates.",
    insights: [],
    caveats: [reason],
    noClearPattern: true
  };
}
