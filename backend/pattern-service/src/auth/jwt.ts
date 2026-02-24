export interface TokenClaims {
  sub: string;
  typ: "challenge" | "access";
  iat: number;
  exp: number;
  [key: string]: unknown;
}

interface IssueTokenOptions {
  subject: string;
  type: TokenClaims["typ"];
  ttlSeconds: number;
  additionalClaims?: Record<string, unknown>;
}

export async function issueSignedToken(secret: string, options: IssueTokenOptions): Promise<{ token: string; expiresAtEpoch: number }> {
  const now = Math.floor(Date.now() / 1000);
  const exp = now + options.ttlSeconds;

  const header = {
    alg: "HS256",
    typ: "JWT"
  };

  const payload: TokenClaims = {
    sub: options.subject,
    typ: options.type,
    iat: now,
    exp,
    ...(options.additionalClaims ?? {})
  };

  const encodedHeader = base64urlEncode(JSON.stringify(header));
  const encodedPayload = base64urlEncode(JSON.stringify(payload));
  const signingInput = `${encodedHeader}.${encodedPayload}`;
  const signature = await signHMAC(secret, signingInput);

  return {
    token: `${signingInput}.${base64urlEncodeBytes(signature)}`,
    expiresAtEpoch: exp
  };
}

export async function verifySignedToken(secret: string, token: string): Promise<TokenClaims> {
  const parts = token.split(".");
  if (parts.length !== 3) {
    throw new Error("Malformed token");
  }

  const [encodedHeader, encodedPayload, encodedSignature] = parts;
  const signingInput = `${encodedHeader}.${encodedPayload}`;

  const expectedSignature = await signHMAC(secret, signingInput);
  const incomingSignature = base64urlDecodeToBytes(encodedSignature);

  if (!constantTimeEqual(expectedSignature, incomingSignature)) {
    throw new Error("Invalid token signature");
  }

  const payload = JSON.parse(base64urlDecodeToString(encodedPayload)) as TokenClaims;
  const now = Math.floor(Date.now() / 1000);

  if (typeof payload.exp !== "number" || payload.exp <= now) {
    throw new Error("Token expired");
  }

  if (payload.typ !== "challenge" && payload.typ !== "access") {
    throw new Error("Invalid token type");
  }

  return payload;
}

export function epochToIso(epochSeconds: number): string {
  return new Date(epochSeconds * 1000).toISOString();
}

async function signHMAC(secret: string, message: string): Promise<Uint8Array> {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(message));
  return new Uint8Array(signature);
}

function constantTimeEqual(a: Uint8Array, b: Uint8Array): boolean {
  if (a.length !== b.length) {
    return false;
  }

  let result = 0;
  for (let index = 0; index < a.length; index += 1) {
    result |= a[index] ^ b[index];
  }

  return result === 0;
}

function base64urlEncode(value: string): string {
  return base64urlFromBase64(btoa(value));
}

function base64urlEncodeBytes(bytes: Uint8Array): string {
  const binary = String.fromCharCode(...bytes);
  return base64urlFromBase64(btoa(binary));
}

function base64urlDecodeToString(value: string): string {
  const base64 = base64FromBase64url(value);
  return atob(base64);
}

function base64urlDecodeToBytes(value: string): Uint8Array {
  const base64 = base64FromBase64url(value);
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
}

function base64urlFromBase64(base64: string): string {
  return base64.replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "");
}

function base64FromBase64url(base64url: string): string {
  const base64 = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const padding = base64.length % 4;
  if (padding === 0) {
    return base64;
  }
  return `${base64}${"=".repeat(4 - padding)}`;
}
