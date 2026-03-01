/**
 * AES-256-GCM encryption at rest for health data.
 *
 * Key hierarchy:
 *   KEK (Worker secret) → wraps per-user DEKs
 *   DEK (per install)   → encrypts/decrypts sleep data in D1
 *
 * All functions use the Web Crypto API (native in Cloudflare Workers).
 */

const AES_GCM_IV_BYTES = 12;
const AES_KEY_BITS = 256;

// ── DEK lifecycle ──────────────────────────────────────────────

/** Generate a random 256-bit Data Encryption Key and return raw bytes. */
export async function generateDEK(): Promise<ArrayBuffer> {
    const key = await crypto.subtle.generateKey(
        { name: "AES-GCM", length: AES_KEY_BITS },
        true,
        ["encrypt", "decrypt"]
    );
    return crypto.subtle.exportKey("raw", key);
}

/** Wrap (encrypt) a DEK with the KEK using AES-KW. */
export async function wrapDEK(dekRaw: ArrayBuffer, kekHex: string): Promise<string> {
    const kekKey = await importKEK(kekHex);
    const dekKey = await crypto.subtle.importKey("raw", dekRaw, "AES-GCM", true, ["encrypt", "decrypt"]);
    const wrapped = await crypto.subtle.wrapKey("raw", dekKey, kekKey, "AES-KW");
    return bufferToBase64(wrapped);
}

/** Unwrap (decrypt) a DEK using the KEK. Returns the raw CryptoKey for data operations. */
export async function unwrapDEK(wrappedBase64: string, kekHex: string): Promise<CryptoKey> {
    const kekKey = await importKEK(kekHex);
    const wrappedBuf = base64ToBuffer(wrappedBase64);
    return crypto.subtle.unwrapKey(
        "raw",
        wrappedBuf,
        kekKey,
        "AES-KW",
        "AES-GCM",
        false,
        ["encrypt", "decrypt"]
    );
}

// ── Data encryption ────────────────────────────────────────────

export interface EncryptedBlob {
    ciphertext: string; // base64
    iv: string;         // base64
    tag: string;        // base64 (appended by AES-GCM, last 16 bytes of ciphertext)
}

/** Encrypt a plaintext string with AES-256-GCM. Returns base64-encoded pieces. */
export async function encrypt(plaintext: string, dek: CryptoKey): Promise<EncryptedBlob> {
    const iv = crypto.getRandomValues(new Uint8Array(AES_GCM_IV_BYTES));
    const encoded = new TextEncoder().encode(plaintext);

    const ciphertextWithTag = await crypto.subtle.encrypt(
        { name: "AES-GCM", iv, tagLength: 128 },
        dek,
        encoded
    );

    // AES-GCM appends the 16-byte auth tag to the ciphertext
    const fullBytes = new Uint8Array(ciphertextWithTag);
    const ciphertextBytes = fullBytes.slice(0, fullBytes.length - 16);
    const tagBytes = fullBytes.slice(fullBytes.length - 16);

    return {
        ciphertext: bufferToBase64(ciphertextBytes.buffer as ArrayBuffer),
        iv: bufferToBase64(iv.buffer as ArrayBuffer),
        tag: bufferToBase64(tagBytes.buffer as ArrayBuffer)
    };
}

/** Decrypt an AES-256-GCM encrypted blob back to plaintext. */
export async function decrypt(blob: EncryptedBlob, dek: CryptoKey): Promise<string> {
    const iv = base64ToBuffer(blob.iv);
    const ciphertextBytes = base64ToBuffer(blob.ciphertext);
    const tagBytes = base64ToBuffer(blob.tag);

    // Re-assemble ciphertext + tag for Web Crypto
    const combined = new Uint8Array(ciphertextBytes.byteLength + tagBytes.byteLength);
    combined.set(new Uint8Array(ciphertextBytes), 0);
    combined.set(new Uint8Array(tagBytes), ciphertextBytes.byteLength);

    const decrypted = await crypto.subtle.decrypt(
        { name: "AES-GCM", iv: new Uint8Array(iv), tagLength: 128 },
        dek,
        combined
    );

    return new TextDecoder().decode(decrypted);
}

// ── Helpers ────────────────────────────────────────────────────

async function importKEK(hexSecret: string): Promise<CryptoKey> {
    const raw = hexToBuffer(hexSecret);
    return crypto.subtle.importKey("raw", raw, "AES-KW", false, ["wrapKey", "unwrapKey"]);
}

function hexToBuffer(hex: string): ArrayBuffer {
    const bytes = new Uint8Array(hex.length / 2);
    for (let i = 0; i < hex.length; i += 2) {
        bytes[i / 2] = parseInt(hex.substring(i, i + 2), 16);
    }
    return bytes.buffer;
}

export function bufferToBase64(buffer: ArrayBuffer): string {
    const bytes = new Uint8Array(buffer);
    let binary = "";
    for (const byte of bytes) {
        binary += String.fromCharCode(byte);
    }
    return btoa(binary);
}

export function base64ToBuffer(base64: string): ArrayBuffer {
    const binary = atob(base64);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) {
        bytes[i] = binary.charCodeAt(i);
    }
    return bytes.buffer;
}
