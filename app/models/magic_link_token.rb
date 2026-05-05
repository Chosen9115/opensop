class MagicLinkToken < ApplicationRecord
  PURPOSES = %w[sign_in recovery invitation].freeze

  belongs_to :user

  validates :token_digest, presence: true, uniqueness: true
  validates :purpose, inclusion: { in: PURPOSES }
  validates :expires_at, presence: true

  scope :usable, -> { where(consumed_at: nil).where("expires_at > ?", Time.current) }

  def self.from_token(raw_token)
    return nil if raw_token.blank?
    digest = Digest::SHA256.hexdigest(raw_token)
    usable.find_by(token_digest: digest)
  end

  def consumed?
    consumed_at.present?
  end

  def expired?
    expires_at <= Time.current
  end

  def usable?
    !consumed? && !expired?
  end

  def consume!
    update!(consumed_at: Time.current)
  end
end
