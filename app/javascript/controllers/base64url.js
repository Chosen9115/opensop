// Tiny base64url <-> ArrayBuffer helpers used by both passkey controllers.
// WebAuthn options/responses use base64url strings on the wire (per the
// server's WebAuthn.configuration.encoding = :base64url setting).

export function base64UrlToBuffer(base64url) {
  const padded = base64url.replace(/-/g, "+").replace(/_/g, "/");
  const padding = padded.length % 4 === 0 ? "" : "=".repeat(4 - (padded.length % 4));
  const binary = atob(padded + padding);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes.buffer;
}

export function bufferToBase64Url(buffer) {
  const bytes = new Uint8Array(buffer);
  let str = "";
  for (let i = 0; i < bytes.length; i++) str += String.fromCharCode(bytes[i]);
  return btoa(str).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

// Recursively convert all base64url string fields the server sends into
// ArrayBuffers, per the WebAuthn JSON-serializable shape.
export function decodeOptionsForCreate(options) {
  options.challenge = base64UrlToBuffer(options.challenge);
  options.user.id = base64UrlToBuffer(options.user.id);
  if (Array.isArray(options.excludeCredentials)) {
    options.excludeCredentials = options.excludeCredentials.map(c => ({
      ...c,
      id: base64UrlToBuffer(c.id)
    }));
  }
  return options;
}

export function decodeOptionsForGet(options) {
  options.challenge = base64UrlToBuffer(options.challenge);
  if (Array.isArray(options.allowCredentials)) {
    options.allowCredentials = options.allowCredentials.map(c => ({
      ...c,
      id: base64UrlToBuffer(c.id)
    }));
  }
  return options;
}

// Convert the PublicKeyCredential the browser returns into the
// JSON-serializable shape webauthn-ruby's `from_create` / `from_get` expect.
export function credentialToJSON(credential) {
  const json = {
    id: credential.id,
    rawId: bufferToBase64Url(credential.rawId),
    type: credential.type,
    response: {}
  };
  if (credential.response.attestationObject) {
    json.response.attestationObject = bufferToBase64Url(credential.response.attestationObject);
    json.response.clientDataJSON = bufferToBase64Url(credential.response.clientDataJSON);
    if (credential.response.getTransports) {
      json.response.transports = credential.response.getTransports();
    }
  } else {
    json.response.clientDataJSON = bufferToBase64Url(credential.response.clientDataJSON);
    json.response.authenticatorData = bufferToBase64Url(credential.response.authenticatorData);
    json.response.signature = bufferToBase64Url(credential.response.signature);
    if (credential.response.userHandle) {
      json.response.userHandle = bufferToBase64Url(credential.response.userHandle);
    }
  }
  return json;
}

export function csrfToken() {
  const meta = document.querySelector('meta[name="csrf-token"]');
  return meta ? meta.getAttribute("content") : "";
}
