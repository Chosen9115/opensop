import { Controller } from "@hotwired/stimulus";
import {
  decodeOptionsForCreate, credentialToJSON, csrfToken
} from "controllers/base64url";

// Drives passkey registration. Used on /account/passkeys (Phase 3) and
// from the post-invitation page (Phase 2 contributes the controller; Phase 3
// uses it). The controller posts to /auth/passkey/registration_options first,
// then /auth/passkey/registration with the attestation.
export default class extends Controller {
  static targets = ["nickname", "submit", "error"];
  static values = {
    optionsUrl: String,
    registerUrl: String,
    successRedirect: String
  };

  async submit(event) {
    event?.preventDefault?.();
    if (!window.PublicKeyCredential) {
      this.showError(this.element.dataset.passkeyRegistrationFallbackText || "This browser doesn't support passkeys.");
      return;
    }
    this.setBusy(true);
    try {
      const optionsResponse = await fetch(this.optionsUrlValue, {
        method: "POST",
        headers: { "X-CSRF-Token": csrfToken(), "Accept": "application/json" },
        credentials: "same-origin"
      });
      if (!optionsResponse.ok) throw new Error("options request failed");
      const options = decodeOptionsForCreate(await optionsResponse.json());

      const credential = await navigator.credentials.create({ publicKey: options });
      if (!credential) throw new Error("no credential returned");

      const registerResponse = await fetch(this.registerUrlValue, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Accept": "application/json",
          "X-CSRF-Token": csrfToken()
        },
        credentials: "same-origin",
        body: JSON.stringify({
          nickname: this.nicknameValue(),
          credential: credentialToJSON(credential)
        })
      });
      const data = await registerResponse.json();
      if (registerResponse.ok) {
        if (this.hasSuccessRedirectValue && this.successRedirectValue) {
          window.location.href = this.successRedirectValue;
        } else {
          window.location.reload();
        }
      } else {
        this.showError(this.errorMessageFor(data.error));
      }
    } catch (e) {
      if (e?.name !== "NotAllowedError") {
        this.showError(this.element.dataset.passkeyRegistrationGenericErrorText || "Could not register a passkey. Please try again.");
      }
    } finally {
      this.setBusy(false);
    }
  }

  nicknameValue() {
    return this.hasNicknameTarget ? (this.nicknameTarget.value || "").trim() : "";
  }

  setBusy(busy) {
    if (this.hasSubmitTarget) {
      this.submitTarget.disabled = busy;
      this.submitTarget.setAttribute("aria-busy", busy ? "true" : "false");
    }
  }

  showError(message) {
    if (this.hasErrorTarget) {
      this.errorTarget.textContent = message;
      this.errorTarget.classList.remove("hidden");
    }
  }

  errorMessageFor(code) {
    const map = {
      duplicate_credential: "This passkey is already registered.",
      registration_failed: "Registration failed. Try again.",
      invalid_challenge: "This registration attempt expired. Please try again."
    };
    return map[code] || (this.element.dataset.passkeyRegistrationGenericErrorText || "Registration failed.");
  }
}
