export interface Env {
  INSTALL_KEYS: KVNamespace;
  AGENT_KEYS: KVNamespace;
  SLEEP_DATA: D1Database;
  GEMINI_API_KEY: string;
  JWT_SIGNING_SECRET: string;
  CHALLENGE_SIGNING_SECRET: string;
  ENCRYPTION_KEK: string;
  GEMINI_MODEL?: string;
}

export interface ServiceConfig {
  geminiApiKey: string;
  geminiModel: string;
  jwtSigningSecret: string;
  challengeSigningSecret: string;
  encryptionKek: string;
}

const DEFAULT_GEMINI_MODEL = "gemini-2.5-flash";

export function readConfig(env: Env): ServiceConfig {
  return {
    geminiApiKey: required(env.GEMINI_API_KEY, "GEMINI_API_KEY"),
    geminiModel: env.GEMINI_MODEL || DEFAULT_GEMINI_MODEL,
    jwtSigningSecret: required(env.JWT_SIGNING_SECRET, "JWT_SIGNING_SECRET"),
    challengeSigningSecret: required(env.CHALLENGE_SIGNING_SECRET, "CHALLENGE_SIGNING_SECRET"),
    encryptionKek: required(env.ENCRYPTION_KEK, "ENCRYPTION_KEK")
  };
}

function required(value: string | undefined, name: string): string {
  if (!value || !value.trim()) {
    throw new Error(`Missing required environment variable: ${name}`);
  }
  return value;
}
