require "fileutils"

module Opensop
  module Auth
    # Sends authentication emails via Resend (or logs them in dev/test).
    # Plain Ruby — does NOT use ActionMailer. Templates are composed inline
    # with I18n.t calls so localization is additive later.
    #
    # Modes (controlled by ENV["OPENSOP_MAILER_MODE"]):
    #   "send" — calls Resend::Emails.send. Default in production.
    #   "log"  — writes HTML to tmp/opensop_emails/<timestamp>.html and logs
    #            the URL to Rails.logger.info. Default in dev/test.
    class Mailer
      def self.send_magic_link(user:, raw_token:, purpose:, host:)
        new.send_magic_link(user: user, raw_token: raw_token, purpose: purpose, host: host)
      end

      def self.send_invitation(user:, raw_token:, host:, inviter: nil)
        new.send_invitation(user: user, raw_token: raw_token, host: host, inviter: inviter)
      end

      def send_magic_link(user:, raw_token:, purpose:, host:)
        url = url_for_purpose(purpose, raw_token, host)
        subject = I18n.t("opensop.auth.emails.#{purpose}.subject")
        deliver(
          to: user.email,
          subject: subject,
          html: html_magic_link(user: user, url: url, purpose: purpose),
          text: text_magic_link(user: user, url: url, purpose: purpose)
        )
      end

      def send_invitation(user:, raw_token:, host:, inviter:)
        url = url_for_purpose("invitation", raw_token, host)
        subject = I18n.t("opensop.auth.emails.invitation.subject")
        deliver(
          to: user.email,
          subject: subject,
          html: html_invitation(user: user, url: url, inviter: inviter),
          text: text_invitation(user: user, url: url, inviter: inviter)
        )
      end

      private

      def deliver(to:, subject:, html:, text:)
        case mode
        when "log"
          deliver_log(to: to, subject: subject, html: html, text: text)
        when "send"
          deliver_resend(to: to, subject: subject, html: html, text: text)
        else
          raise ArgumentError, "Unknown OPENSOP_MAILER_MODE: #{mode.inspect}"
        end
      end

      def deliver_log(to:, subject:, html:, text:)
        dir = Rails.root.join("tmp", "opensop_emails")
        FileUtils.mkdir_p(dir)
        file = dir.join("#{Time.current.strftime('%Y%m%d-%H%M%S-%6N')}-#{to.gsub(/[^a-z0-9]/i, '_')}.html")
        File.write(file, html)
        Rails.logger.info("[Opensop::Auth::Mailer] (log mode) to=#{to} subject=#{subject.inspect} file=#{file}")
        # Also log the first link found in the text body so operators reading
        # the log can grab the URL without opening the file.
        if (url_match = text.match(%r{https?://\S+}))
          Rails.logger.info("[Opensop::Auth::Mailer]   url: #{url_match[0]}")
        end
        { id: "log-#{file.basename}" }
      end

      def deliver_resend(to:, subject:, html:, text:)
        from = ENV.fetch("OPENSOP_MAILER_FROM")
        Resend::Emails.send(
          from: from,
          to: [to],
          subject: subject,
          html: html,
          text: text
        )
      end

      def mode
        ENV["OPENSOP_MAILER_MODE"].presence || (Rails.env.production? ? "send" : "log")
      end

      def url_for_purpose(purpose, raw_token, host)
        path = case purpose
               when "sign_in", "recovery" then "/auth/magic_links/#{raw_token}"
               when "invitation"          then "/auth/invitations/#{raw_token}"
               else raise ArgumentError, "Unknown purpose: #{purpose.inspect}"
               end
        "#{host}#{path}"
      end

      def html_magic_link(user:, url:, purpose:)
        heading = I18n.t("opensop.auth.emails.#{purpose}.heading")
        body    = I18n.t("opensop.auth.emails.#{purpose}.body")
        cta     = I18n.t("opensop.auth.emails.#{purpose}.cta")
        expires = I18n.t("opensop.auth.emails.shared.expires_in", duration: "15 minutes")
        <<~HTML
          <!doctype html>
          <html><body style="font-family: -apple-system, system-ui, sans-serif; max-width: 480px; margin: 32px auto; color: #111;">
            <h1 style="font-size: 20px; margin: 0 0 16px;">#{ERB::Util.html_escape(heading)}</h1>
            <p style="font-size: 14px; line-height: 1.5;">#{ERB::Util.html_escape(body)}</p>
            <p style="margin: 24px 0;">
              <a href="#{ERB::Util.html_escape(url)}" style="display: inline-block; background: #111; color: #fff; padding: 10px 18px; border-radius: 6px; text-decoration: none; font-size: 14px;">#{ERB::Util.html_escape(cta)}</a>
            </p>
            <p style="font-size: 12px; color: #666;">#{ERB::Util.html_escape(expires)}</p>
            <p style="font-size: 12px; color: #666; word-break: break-all;">#{ERB::Util.html_escape(url)}</p>
          </body></html>
        HTML
      end

      def text_magic_link(user:, url:, purpose:)
        heading = I18n.t("opensop.auth.emails.#{purpose}.heading")
        body    = I18n.t("opensop.auth.emails.#{purpose}.body")
        cta     = I18n.t("opensop.auth.emails.#{purpose}.cta")
        expires = I18n.t("opensop.auth.emails.shared.expires_in", duration: "15 minutes")
        "#{heading}\n\n#{body}\n\n#{cta}: #{url}\n\n#{expires}\n"
      end

      def html_invitation(user:, url:, inviter:)
        heading = I18n.t("opensop.auth.emails.invitation.heading")
        body    = I18n.t("opensop.auth.emails.invitation.body", inviter: inviter&.email || I18n.t("opensop.auth.emails.shared.an_admin"))
        cta     = I18n.t("opensop.auth.emails.invitation.cta")
        expires = I18n.t("opensop.auth.emails.shared.expires_in", duration: "7 days")
        <<~HTML
          <!doctype html>
          <html><body style="font-family: -apple-system, system-ui, sans-serif; max-width: 480px; margin: 32px auto; color: #111;">
            <h1 style="font-size: 20px; margin: 0 0 16px;">#{ERB::Util.html_escape(heading)}</h1>
            <p style="font-size: 14px; line-height: 1.5;">#{ERB::Util.html_escape(body)}</p>
            <p style="margin: 24px 0;">
              <a href="#{ERB::Util.html_escape(url)}" style="display: inline-block; background: #111; color: #fff; padding: 10px 18px; border-radius: 6px; text-decoration: none; font-size: 14px;">#{ERB::Util.html_escape(cta)}</a>
            </p>
            <p style="font-size: 12px; color: #666;">#{ERB::Util.html_escape(expires)}</p>
            <p style="font-size: 12px; color: #666; word-break: break-all;">#{ERB::Util.html_escape(url)}</p>
          </body></html>
        HTML
      end

      def text_invitation(user:, url:, inviter:)
        heading = I18n.t("opensop.auth.emails.invitation.heading")
        body    = I18n.t("opensop.auth.emails.invitation.body", inviter: inviter&.email || I18n.t("opensop.auth.emails.shared.an_admin"))
        cta     = I18n.t("opensop.auth.emails.invitation.cta")
        expires = I18n.t("opensop.auth.emails.shared.expires_in", duration: "7 days")
        "#{heading}\n\n#{body}\n\n#{cta}: #{url}\n\n#{expires}\n"
      end
    end
  end
end
