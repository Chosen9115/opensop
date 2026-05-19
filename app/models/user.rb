class User < ApplicationRecord
  ROLES = %w[admin].freeze

  has_many :passkey_credentials, dependent: :destroy
  has_many :auth_sessions, class_name: "AuthSession", dependent: :destroy
  has_many :magic_link_tokens, dependent: :destroy

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :display_name, length: { maximum: 100 }, allow_blank: true
  validates :role, inclusion: { in: ROLES }

  before_validation :normalize_email

  def admin?
    role == "admin"
  end

  private

  def normalize_email
    self.email = email.to_s.strip.downcase if email.present?
  end
end
