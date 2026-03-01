import type { Env } from "../config";

const API_KEY_PREFIX = "slk_";
const API_KEY_HEX_LENGTH = 32;

export interface AgentKeyRecord {
    installId: string;
    wrappedDek: string;
    createdAt: string;
}

/** Generate a new API key with the `slk_` prefix. */
export function generateApiKey(): string {
    const bytes = crypto.getRandomValues(new Uint8Array(API_KEY_HEX_LENGTH));
    let hex = "";
    for (const b of bytes) {
        hex += b.toString(16).padStart(2, "0");
    }
    return `${API_KEY_PREFIX}${hex}`;
}

/** Register an API key in KV, mapping it to an installId + wrapped DEK. */
export async function registerApiKey(
    apiKey: string,
    installId: string,
    wrappedDek: string,
    env: Env
): Promise<void> {
    const record: AgentKeyRecord = {
        installId,
        wrappedDek,
        createdAt: new Date().toISOString()
    };

    await env.AGENT_KEYS.put(apiKey, JSON.stringify(record));

    // Also store a reverse mapping so we can look up the key by installId
    await env.AGENT_KEYS.put(`install:${installId}`, apiKey);
}

/** Validate an API key and return the associated record, or null if invalid. */
export async function validateApiKey(apiKey: string, env: Env): Promise<AgentKeyRecord | null> {
    if (!apiKey.startsWith(API_KEY_PREFIX)) {
        return null;
    }

    const raw = await env.AGENT_KEYS.get(apiKey);
    if (!raw) {
        return null;
    }

    try {
        return JSON.parse(raw) as AgentKeyRecord;
    } catch {
        return null;
    }
}

/** Revoke an API key and remove the reverse mapping. */
export async function revokeApiKey(apiKey: string, env: Env): Promise<string | null> {
    const record = await validateApiKey(apiKey, env);
    if (!record) {
        return null;
    }

    await env.AGENT_KEYS.delete(apiKey);
    await env.AGENT_KEYS.delete(`install:${record.installId}`);

    return record.installId;
}

/** Find the API key for a given installId (reverse lookup). */
export async function findApiKeyByInstallId(installId: string, env: Env): Promise<string | null> {
    return env.AGENT_KEYS.get(`install:${installId}`);
}
