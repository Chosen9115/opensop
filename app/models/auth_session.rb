class AuthSession < ApplicationRecord
  self.table_name = "auth_sessions"

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  # Returns the active session matching the raw token, or nil. Raw token is
  # SHA-256 hashed before lookup; raw tokens are never persisted.
  def self.from_token(raw_token)
    return nil if raw_token.blank?
    digest = Digest::SHA256.hexdigest(raw_token)
    active.find_by(token_digest: digest)
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def usable?
    !revoked? && !expired?
  end

  # Sliding expiry: bump expires_at if we're within 24h of expiration.
  def touch_usage!(expires_in: 30.days)
    updates = { last_used_at: Time.current }
    updates[:expires_at] = expires_in.from_now if expires_at - Time.current < 24.hours
    update_columns(updates)
  end
end
