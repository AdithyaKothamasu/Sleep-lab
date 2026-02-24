import { describe, expect, it } from "vitest";
import { createChallengeToken, verifyChallengeToken } from "../src/auth/challenge";
import { issueSignedToken, verifySignedToken } from "../src/auth/jwt";

describe("token signing", () => {
  it("creates and verifies challenge tokens", async () => {
    const created = await createChallengeToken("secret", "0f27647a-6f54-4ca1-a3b8-9ca76a4f5970", "public-key");
    const verified = await verifyChallengeToken("secret", created.token);

    expect(verified.installId).toBe("0f27647a-6f54-4ca1-a3b8-9ca76a4f5970");
    expect(verified.publicKey).toBe("public-key");
    expect(typeof verified.nonce).toBe("string");
  });

  it("rejects invalid token signatures", async () => {
    const token = await issueSignedToken("secret-a", {
      subject: "subject",
      type: "access",
      ttlSeconds: 300
    });

    await expect(verifySignedToken("secret-b", token.token)).rejects.toThrow("Invalid token signature");
  });
});
