import type { Env, ServiceConfig } from "../config";
import { patternAnalysisRequestSchema } from "../schema/request";
import { errorResponse, jsonResponse, parseJSON } from "../util/http";
import { generatePatternInsights } from "../services/gemini";

export async function handleAnalyze(request: Request, _env: Env, config: ServiceConfig): Promise<Response> {
  let payload: unknown;

  try {
    payload = await parseJSON(request);
  } catch (error) {
    return errorResponse(400, "Invalid request body", String(error));
  }

  const parsed = patternAnalysisRequestSchema.safeParse(payload);
  if (!parsed.success) {
    return errorResponse(400, "Invalid analysis payload", parsed.error.flatten());
  }

  const aiResponse = await generatePatternInsights(parsed.data, config);

  return jsonResponse(200, aiResponse);
}
