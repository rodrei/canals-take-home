module Payments
  # Mocked payment charge. A real implementation would call the provider's
  # charge API with the idempotency key. Deterministic: a token beginning with
  # "pm_decline" is declined; otherwise the charge succeeds and the provider id
  # is derived from the idempotency key so retries return the same id.
  class ChargeService
    def self.call(token:, amount_cents:, idempotency_key:, description:)
      new(token: token, amount_cents: amount_cents, idempotency_key: idempotency_key, description: description).call
    end

    def initialize(token:, amount_cents:, idempotency_key:, description:)
      @token = token
      @amount_cents = amount_cents
      @idempotency_key = idempotency_key
      @description = description
    end

    def call
      raise PaymentDeclinedError, "card declined" if @token.to_s.start_with?("pm_decline")

      "ch_#{@idempotency_key}"
    end
  end
end
