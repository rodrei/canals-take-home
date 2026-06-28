module Payments
  # Mocked payment tokenization. A real implementation would call the payment
  # provider's vault API. Validates the card with the Luhn algorithm so the
  # synchronous "billing validation" is real, then returns an opaque token.
  # The card number is never returned or persisted.
  class TokenizeService
    DECLINE_CARD = "4000000000000002"

    def self.call(card_number)
      new(card_number).call
    end

    def initialize(card_number)
      @card_number = card_number.to_s.gsub(/\s+/, "")
    end

    def call
      raise InvalidCardError, "card failed validation" unless luhn_valid?

      prefix = (@card_number == DECLINE_CARD) ? "pm_decline_" : "pm_ok_"
      "#{prefix}#{Digest::SHA256.hexdigest(@card_number)[0, 16]}"
    end

    private

    def luhn_valid?
      return false unless @card_number.match?(/\A\d{13,19}\z/)

      digits = @card_number.chars.map(&:to_i).reverse
      sum = digits.each_with_index.sum do |digit, index|
        if index.odd?
          doubled = digit * 2
          doubled > 9 ? doubled - 9 : doubled
        else
          digit
        end
      end
      (sum % 10).zero?
    end
  end
end
