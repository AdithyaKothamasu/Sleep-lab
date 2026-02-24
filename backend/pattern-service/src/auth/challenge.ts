import { issueSignedToken, verifySignedToken } from "./jwt";

const CHALLENGE_TTL_SECONDS = 5 * 60;

interface ChallengePayload {
  installId: string;
  publicKey: string;
  nonce: string;
}

export async function createChallengeToken(secret: string, installId: string, publicKey: string): Promise<{ token: string; expiresAtEpoch: number }> {
  return issueSignedToken(secret, {
    subject: installId,
    type: "challenge",
    ttlSeconds: CHALLENGE_TTL_SECONDS,
    additionalClaims: {
      publicKey,
      nonce: crypto.randomUUID()
    }
  });
}

export async function verifyChallengeToken(secret: string, token: string): Promise<ChallengePayload> {
  const claims = await verifySignedToken(secret, token);

  if (claims.typ !== "challenge") {
    throw new Error("Unexpected token type");
  }

  if (typeof claims.publicKey !== "string" || typeof claims.nonce !== "string") {
    throw new Error("Malformed challenge token claims");
  }

  return {
    installId: claims.sub,
    publicKey: claims.publicKey,
    nonce: claims.nonce
  };
}
