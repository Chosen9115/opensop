require "rails_helper"
require "webauthn/fake_client"

RSpec.describe Auth::PasskeysController, type: :request do
  let(:user) { create(:user) }

  # Request specs hit the app at http://www.example.com by default. Align the
  # WebAuthn relying-party config so the FakeClient's clientDataJSON.origin
  # matches what `WebAuthn::Credential#verify` expects.
  let(:fake_origin) { "http://www.example.com" }
  let(:fake_client) { WebAuthn::FakeClient.new(fake_origin) }

  let(:original_origin) { WebAuthn.configuration.allowed_origins }
  let(:original_rp_id) { WebAuthn.configuration.rp_id }

  before do
    WebAuthn.configuration.allowed_origins = [fake_origin]
    WebAuthn.configuration.rp_id = "www.example.com"
  end

  after do
    WebAuthn.configuration.allowed_origins = original_origin
    WebAuthn.configuration.rp_id = original_rp_id
  end

  # JSON helper — the controller reads passkey credentials from a JSON body
  # so the Stimulus client can post the raw WebAuthn response object.
  def post_json(path, payload)
    post path,
         params: payload.to_json,
         headers: { "Content-Type" => "application/json" }
  end

  describe "POST /auth/passkey/registration_options" do
    context "when signed in" do
      before { sign_in_via_magic_link(user) }

      it "issues options containing a fresh challenge" do
        post auth_passkey_registration_options_path
        expect(response).to have_http_status(:ok)
        body = response.parsed_body
        expect(body["challenge"]).to be_present
        expect(body["rp"]["id"]).to eq("www.example.com")
        expect(body["user"]["name"]).to eq(user.email)
      end

      it "excludes already-registered credentials" do
        existing = create(:passkey_credential, user: user)
        post auth_passkey_registration_options_path
        excluded_ids = response.parsed_body["excludeCredentials"].map { |c| c["id"] }
        expect(excluded_ids).to include(existing.external_id)
      end
    end

    context "when not signed in" do
      it "rejects unauthenticated callers" do
        # Phase 4 cutover: require_authentication always enforces, so an
        # anonymous caller should be redirected (HTML) or get 401 (JSON).
        post auth_passkey_registration_options_path
        expect(response).to have_http_status(:unauthorized).or have_http_status(:found)
      end
    end
  end

  describe "POST /auth/passkey/registration" do
    before { sign_in_via_magic_link(user) }

    it "verifies attestation and persists a PasskeyCredential" do
      post auth_passkey_registration_options_path
      challenge = response.parsed_body["challenge"]

      attestation = fake_client.create(challenge: challenge)

      expect {
        post_json auth_passkey_registration_path,
                  { nickname: "Test", credential: attestation }
      }.to change { user.passkey_credentials.count }.by(1)

      expect(response).to have_http_status(:created)
      body = response.parsed_body
      expect(body["nickname"]).to eq("Test")
      expect(body["external_id"]).to be_present
    end

    it "falls back to a UA-derived nickname when none is provided" do
      post auth_passkey_registration_options_path
      challenge = response.parsed_body["challenge"]
      attestation = fake_client.create(challenge: challenge)

      post_json auth_passkey_registration_path, { credential: attestation }

      expect(response).to have_http_status(:created)
      # request specs ship a Rack-Test UA → falls through to the default branch.
      expect(response.parsed_body["nickname"]).to eq("New passkey")
    end

    it "records a passkey_registered audit event on success" do
      post auth_passkey_registration_options_path
      challenge = response.parsed_body["challenge"]
      attestation = fake_client.create(challenge: challenge)

      expect {
        post_json auth_passkey_registration_path,
                  { nickname: "AuditDevice", credential: attestation }
      }.to change { AuthEvent.where(kind: "passkey_registered", user: user).count }.by(1)
    end

    it "rejects an attestation built for a different challenge" do
      # First, get a real challenge from the controller and store it in
      # the session — but then build the attestation against a DIFFERENT
      # challenge. The verify call should fail.
      post auth_passkey_registration_options_path
      attestation = fake_client.create(challenge: WebAuthn.generate_user_id)

      post_json auth_passkey_registration_path,
                { nickname: "Bad", credential: attestation }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.parsed_body["error"]).to eq("registration_failed")
    end

    it "rejects when no challenge is in the session" do
      # Skip the options call entirely — the verify endpoint has no
      # session challenge to consume.
      attestation = fake_client.create(challenge: WebAuthn.generate_user_id)

      post_json auth_passkey_registration_path,
                { nickname: "Bad", credential: attestation }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_challenge")
    end

    it "returns 409 when the credential is already registered to the user" do
      # Register once — the FakeClient's authenticator persists its private
      # key across calls, so the SAME external_id will be derived on the
      # second go-round, which is exactly the duplicate path we want to
      # exercise. Use a fresh FakeClient instance with a shared authenticator
      # to make this deterministic.
      shared_client = WebAuthn::FakeClient.new(fake_origin)

      post auth_passkey_registration_options_path
      challenge_1 = response.parsed_body["challenge"]
      attestation_1 = shared_client.create(challenge: challenge_1)
      post_json auth_passkey_registration_path,
                { nickname: "First", credential: attestation_1 }
      expect(response).to have_http_status(:created)

      first_external_id = user.passkey_credentials.last.external_id

      # Build a SECOND attestation whose external_id collides with the
      # first by hand-stamping it. The verify step will still pass (the
      # signature matches the new keypair) but the controller's
      # duplicate-detection should kick in before persistence.
      post auth_passkey_registration_options_path
      challenge_2 = response.parsed_body["challenge"]
      attestation_2 = shared_client.create(challenge: challenge_2)

      # Hand-stamp the id so the controller treats it as a duplicate.
      duplicate = attestation_2.deep_dup
      duplicate["id"] = first_external_id
      duplicate["rawId"] = first_external_id

      # Stub from_create so the verify step succeeds AND the .id matches
      # the existing row. This isolates the duplicate-detection branch
      # from FakeClient's signature math (which would otherwise fail
      # because we tampered with the id).
      stub_credential = instance_double(WebAuthn::PublicKeyCredentialWithAttestation,
                                        id: first_external_id,
                                        public_key: "stub-pk",
                                        sign_count: 0,
                                        response: double(transports: []),
                                        verify: true)
      allow(WebAuthn::Credential).to receive(:from_create).and_return(stub_credential)

      expect {
        post_json auth_passkey_registration_path,
                  { nickname: "Second", credential: duplicate }
      }.not_to change { user.passkey_credentials.count }

      expect(response).to have_http_status(:conflict)
      expect(response.parsed_body["error"]).to eq("duplicate_credential")
    end
  end

  describe "POST /auth/passkey/options" do
    it "returns options for a known email" do
      post auth_passkey_options_path, params: { email: user.email }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["challenge"]).to be_present
    end

    it "returns options for an unknown email — no enumeration" do
      post auth_passkey_options_path, params: { email: "nobody@example.com" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["challenge"]).to be_present
    end

    it "returns options when no email is provided" do
      post auth_passkey_options_path
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["challenge"]).to be_present
    end

    it "lists allowed credentials for a known user with passkeys" do
      credential = create(:passkey_credential, user: user)
      post auth_passkey_options_path, params: { email: user.email }
      ids = (response.parsed_body["allowCredentials"] || []).map { |c| c["id"] }
      expect(ids).to include(credential.external_id)
    end
  end

  describe "POST /auth/passkey/verify" do
    # Helper: register a passkey for `user` and return the FakeClient that
    # owns the keypair so we can use it later to issue assertions.
    def register_passkey_for(user)
      sign_in_via_magic_link(user)
      client = WebAuthn::FakeClient.new(fake_origin)

      post auth_passkey_registration_options_path
      challenge = response.parsed_body["challenge"]
      attestation = client.create(challenge: challenge)
      post_json auth_passkey_registration_path,
                { nickname: "device", credential: attestation }
      expect(response).to have_http_status(:created)

      # Sign out so the verify ceremony starts from a clean slate.
      delete auth_sign_out_path

      [client, user.passkey_credentials.last]
    end

    it "verifies an assertion and creates a session" do
      client, _credential = register_passkey_for(user)

      post auth_passkey_options_path, params: { email: user.email }
      challenge = response.parsed_body["challenge"]
      assertion = client.get(challenge: challenge)

      post_json auth_passkey_verify_path, { credential: assertion }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["redirect_to"]).to eq("/dashboard")

      # The signed cookie is set by Authenticatable#sign_in.
      expect(response.cookies[Authenticatable::COOKIE_NAME.to_s]).to be_present
      expect(AuthSession.where(user: user).active.count).to be >= 1
    end

    it "respects a safe return_to" do
      client, _credential = register_passkey_for(user)

      post auth_passkey_options_path, params: { email: user.email }
      challenge = response.parsed_body["challenge"]
      assertion = client.get(challenge: challenge)

      post_json auth_passkey_verify_path,
                { credential: assertion, return_to: "/instances" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["redirect_to"]).to eq("/instances")
    end

    it "ignores an unsafe (protocol-relative) return_to" do
      client, _credential = register_passkey_for(user)

      post auth_passkey_options_path, params: { email: user.email }
      challenge = response.parsed_body["challenge"]
      assertion = client.get(challenge: challenge)

      post_json auth_passkey_verify_path,
                { credential: assertion, return_to: "//evil.example.com/x" }

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["redirect_to"]).to eq("/dashboard")
    end

    it "rejects an unknown credential" do
      _client, _credential = register_passkey_for(user)

      post auth_passkey_options_path, params: { email: user.email }
      challenge = response.parsed_body["challenge"]

      # Build an assertion from a fresh FakeClient — its credential id
      # has never been registered, so the lookup returns nil.
      other_client = WebAuthn::FakeClient.new(fake_origin)
      # FakeClient.get without a prior .create still emits an assertion
      # (the FakeAuthenticator persists its own state), so its id is
      # different from the registered one.
      other_client.create(challenge: WebAuthn.generate_user_id)
      assertion = other_client.get(challenge: challenge)

      post_json auth_passkey_verify_path, { credential: assertion }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unknown_credential")
    end

    it "rejects sign_count regression as a cloned credential" do
      client, credential = register_passkey_for(user)

      # Bump the stored counter past whatever the FakeClient will emit
      # next so verify() raises SignCountVerificationError.
      credential.update!(sign_count: 999_999)

      post auth_passkey_options_path, params: { email: user.email }
      challenge = response.parsed_body["challenge"]
      assertion = client.get(challenge: challenge)

      expect {
        post_json auth_passkey_verify_path, { credential: assertion }
      }.to change { AuthEvent.where(kind: "cloned_credential_detected", user: user).count }.by(1)

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("cloned_credential")
    end

    it "records a signed_in audit event with via=passkey on successful verify" do
      client, _credential = register_passkey_for(user)

      post auth_passkey_options_path, params: { email: user.email }
      challenge = response.parsed_body["challenge"]
      assertion = client.get(challenge: challenge)

      expect {
        post_json auth_passkey_verify_path, { credential: assertion }
      }.to change { AuthEvent.where(kind: "signed_in", user: user).count }.by(1)

      event = AuthEvent.where(kind: "signed_in", user: user).order(:created_at).last
      expect(event.metadata["via"]).to eq("passkey")
    end

    it "rejects when no challenge is in the session" do
      client, _credential = register_passkey_for(user)

      # Skip the options call so the session has no authentication challenge.
      assertion = client.get(challenge: WebAuthn.generate_user_id)

      post_json auth_passkey_verify_path, { credential: assertion }

      expect(response).to have_http_status(:bad_request)
      expect(response.parsed_body["error"]).to eq("invalid_challenge")
    end

    it "rejects when the assertion challenge does not match the session challenge" do
      client, _credential = register_passkey_for(user)

      post auth_passkey_options_path, params: { email: user.email }
      # Build the assertion against an UNRELATED challenge.
      assertion = client.get(challenge: WebAuthn.generate_user_id)

      post_json auth_passkey_verify_path, { credential: assertion }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("verification_failed")
    end

    it "increments sign_count and updates last_used_at on success" do
      client, credential = register_passkey_for(user)
      original_count = credential.sign_count

      post auth_passkey_options_path, params: { email: user.email }
      challenge = response.parsed_body["challenge"]
      assertion = client.get(challenge: challenge)

      post_json auth_passkey_verify_path, { credential: assertion }
      expect(response).to have_http_status(:ok)

      credential.reload
      expect(credential.sign_count).to be > original_count
      expect(credential.last_used_at).to be_present
    end
  end
end
