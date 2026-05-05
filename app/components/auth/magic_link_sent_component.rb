# frozen_string_literal: true

module Auth
  # Confirmation page rendered after the user requests a magic-link email.
  # Keeps the wording and layout in one place so we can iterate on copy
  # and visual design without scattering view fragments.
  class MagicLinkSentComponent < ViewComponent::Base
    def initialize(email: nil, dev_url: nil)
      @email = email
      @dev_url = dev_url
    end

    attr_reader :email, :dev_url
  end
end
