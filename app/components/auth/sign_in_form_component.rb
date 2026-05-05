# frozen_string_literal: true

module Auth
  # Sign-in form rendered on /auth/sign_in.
  #
  # Wires up the `passkey-signin` Stimulus controller so the user can sign in
  # with a passkey (preferred) or fall back to a magic-link email. A small
  # recovery `<details>` block at the bottom lets users who lost their
  # passkey request a recovery link via email.
  class SignInFormComponent < ViewComponent::Base
    def initialize(return_to: nil)
      @return_to = return_to
    end

    attr_reader :return_to
  end
end
