export async function verifyEd25519Signature(publicKeyBase64: string, message: string, signatureBase64: string): Promise<boolean> {
  const publicKeyRaw = base64Decode(publicKeyBase64);
  const signatureRaw = base64Decode(signatureBase64);

  if (publicKeyRaw.byteLength !== 32 || signatureRaw.byteLength !== 64) {
    return false;
  }

  const key = await crypto.subtle.importKey(
    "raw",
    toArrayBuffer(publicKeyRaw),
    { name: "Ed25519" },
    false,
    ["verify"]
  );

  return crypto.subtle.verify(
    "Ed25519",
    key,
    toArrayBuffer(signatureRaw),
    toArrayBuffer(new TextEncoder().encode(message))
  );
}

function base64Decode(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
}

function toArrayBuffer(value: Uint8Array): ArrayBuffer {
  return value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength) as ArrayBuffer;
}
