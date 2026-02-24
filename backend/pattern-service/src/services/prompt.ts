import type { PatternAnalysisRequest } from "../schema/request";

export function buildPatternPrompt(payload: PatternAnalysisRequest): string {
  return [
    "You are analyzing personal sleep experiments.",
    "Return JSON only matching the schema.",
    "This is not medical advice. Use hypothesis language.",
    "If evidence is weak or conflicting, set noClearPattern=true and explain uncertainty.",
    "Prioritize links between event timing, sleep stages, and physiology metrics (HR, HRV, respiratory rate, workout).",
    "Use the selected dates exactly as provided.",
    "Payload:",
    JSON.stringify(payload)
  ].join("\n");
}

export function outputSchemaForGemini() {
  return {
    type: "OBJECT",
    properties: {
      aiSummary: { type: "STRING" },
      insights: {
        type: "ARRAY",
        items: {
          type: "OBJECT",
          properties: {
            title: { type: "STRING" },
            summary: { type: "STRING" },
            confidence: { type: "STRING", enum: ["low", "medium", "high"] },
            evidence: {
              type: "ARRAY",
              items: { type: "STRING" }
            }
          },
          required: ["title", "summary", "confidence", "evidence"]
        }
      },
      caveats: {
        type: "ARRAY",
        items: { type: "STRING" }
      },
      noClearPattern: { type: "BOOLEAN" }
    },
    required: ["aiSummary", "insights", "caveats", "noClearPattern"]
  };
}
