# frozen_string_literal: true

# Audit log row for authentication-related activity. Created from controllers
# and the Authenticatable concern via Opensop::Auth::EventRecorder. Sibling
# top-level model — distinct from Sop::Event which is process-scoped.
#
# `user` is optional because some events (e.g., a magic-link request for an
# unknown email) are recorded without a known user.
class AuthEvent < ApplicationRecord
  KINDS = %w[
    signed_in
    signed_out
    sign_in_failed
    magic_link_requested
    magic_link_consumed
    magic_link_expired
    invitation_sent
    invitation_consumed
    recovery_initiated
    passkey_registered
    passkey_renamed
    passkey_revoked
    passkey_assertion_failed
    cloned_credential_detected
    user_invited
    user_removed
    session_revoked
    sessions_others_revoked
  ].freeze

  belongs_to :user, optional: true

  validates :kind, presence: true, inclusion: { in: KINDS }

  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :of_kind, ->(kind) { where(kind: kind) }
end
