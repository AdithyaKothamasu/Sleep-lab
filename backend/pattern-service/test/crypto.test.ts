import { describe, expect, it } from "vitest";
import { generateDEK, wrapDEK, unwrapDEK, encrypt, decrypt, bufferToBase64, base64ToBuffer } from "../src/crypto";

// Test KEK (64 hex chars = 32 bytes = 256 bits)
const TEST_KEK = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef";

describe("crypto", () => {
    it("generates a 256-bit DEK", async () => {
        const dek = await generateDEK();
        expect(dek.byteLength).toBe(32);
    });

    it("wraps and unwraps a DEK with KEK", async () => {
        const dekRaw = await generateDEK();
        const wrapped = await wrapDEK(dekRaw, TEST_KEK);

        expect(typeof wrapped).toBe("string");
        expect(wrapped.length).toBeGreaterThan(0);

        const unwrapped = await unwrapDEK(wrapped, TEST_KEK);
        expect(unwrapped).toBeDefined();
        expect(unwrapped.type).toBe("secret");
    });

    it("encrypt → decrypt roundtrip produces original plaintext", async () => {
        const dekRaw = await generateDEK();
        const wrapped = await wrapDEK(dekRaw, TEST_KEK);
        const dek = await unwrapDEK(wrapped, TEST_KEK);

        const plaintext = JSON.stringify({
            sleep: { totalSleepHours: 7.2, averageHRV: 42.1 },
            stageDurations: [{ stage: "deep", hours: 1.5 }]
        });

        const blob = await encrypt(plaintext, dek);
        expect(blob.ciphertext).not.toBe(plaintext);
        expect(blob.iv.length).toBeGreaterThan(0);
        expect(blob.tag.length).toBeGreaterThan(0);

        const decrypted = await decrypt(blob, dek);
        expect(decrypted).toBe(plaintext);
    });

    it("decryption with wrong key fails", async () => {
        const dek1Raw = await generateDEK();
        const dek1Wrapped = await wrapDEK(dek1Raw, TEST_KEK);
        const dek1 = await unwrapDEK(dek1Wrapped, TEST_KEK);

        const dek2Raw = await generateDEK();
        const dek2Wrapped = await wrapDEK(dek2Raw, TEST_KEK);
        const dek2 = await unwrapDEK(dek2Wrapped, TEST_KEK);

        const blob = await encrypt("secret health data", dek1);

        await expect(decrypt(blob, dek2)).rejects.toThrow();
    });

    it("different IVs produce different ciphertexts", async () => {
        const dekRaw = await generateDEK();
        const wrapped = await wrapDEK(dekRaw, TEST_KEK);
        const dek = await unwrapDEK(wrapped, TEST_KEK);

        const plaintext = "same data";
        const blob1 = await encrypt(plaintext, dek);
        const blob2 = await encrypt(plaintext, dek);

        expect(blob1.ciphertext).not.toBe(blob2.ciphertext);
        expect(blob1.iv).not.toBe(blob2.iv);
    });

    it("base64 roundtrip preserves data", () => {
        const original = new Uint8Array([0, 1, 127, 128, 255]);
        const b64 = bufferToBase64(original.buffer as ArrayBuffer);
        const restored = new Uint8Array(base64ToBuffer(b64));
        expect(restored).toEqual(original);
    });

    it("unwrap with wrong KEK fails", async () => {
        const dekRaw = await generateDEK();
        const wrapped = await wrapDEK(dekRaw, TEST_KEK);

        const wrongKEK = "ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff";
        await expect(unwrapDEK(wrapped, wrongKEK)).rejects.toThrow();
    });
});
