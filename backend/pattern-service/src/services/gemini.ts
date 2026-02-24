import type { ServiceConfig } from "../config";
import type { PatternAnalysisRequest } from "../schema/request";
import { fallbackResponse, patternAnalysisResponseSchema, type PatternAnalysisResponse } from "../schema/response";
import { buildPatternPrompt, outputSchemaForGemini } from "./prompt";

interface GeminiGenerateResponse {
  candidates?: Array<{
    content?: {
      parts?: Array<{ text?: string }>;
    };
  }>;
}

export async function generatePatternInsights(payload: PatternAnalysisRequest, config: ServiceConfig): Promise<PatternAnalysisResponse> {
  const prompt = buildPatternPrompt(payload);
  const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${config.geminiModel}:generateContent?key=${config.geminiApiKey}`;

  const response = await fetch(endpoint, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      contents: [
        {
          role: "user",
          parts: [{ text: prompt }]
        }
      ],
      generationConfig: {
        responseMimeType: "application/json",
        responseSchema: outputSchemaForGemini(),
        temperature: 0.2
      }
    })
  });

  if (!response.ok) {
    const bodyText = await response.text();
    return fallbackResponse(`Gemini API call failed (${response.status}): ${bodyText.slice(0, 200)}`);
  }

  const json = (await response.json()) as GeminiGenerateResponse;
  const rawText = json.candidates?.[0]?.content?.parts?.find((part) => typeof part.text === "string")?.text;

  if (!rawText) {
    return fallbackResponse("Gemini response did not include parseable text output.");
  }

  try {
    const parsed = JSON.parse(rawText);
    const validated = patternAnalysisResponseSchema.safeParse(parsed);
    if (!validated.success) {
      return fallbackResponse("Gemini output schema validation failed.");
    }
    return validated.data;
  } catch {
    return fallbackResponse("Gemini output was not valid JSON.");
  }
}
