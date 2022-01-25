# frozen_string_literal: true

require 'active_record'

module Royal
  class PointBalance < ActiveRecord::Base
    MAX_RETRIES = 10

    belongs_to :owner, polymorphic: true
    belongs_to :pointable, polymorphic: true, optional: true

    validates :amount, numericality: { other_than: 0 }
    validates :reason, length: { maximum: 1000 }

    before_create do
      previous_balance = PointBalance.where(owner: owner).order(:sequence).last

      self.sequence = (previous_balance&.sequence || 0) + 1
      self.balance  = (previous_balance&.balance  || 0) + amount
    end

    after_create if: -> { balance.negative? } do
      # Rollback the transaction _after_ the operation to ensure amount
      # was applied against the most recent points balance.
      raise InsufficientPointsError.new(amount, original_balance, reason)
    end

    # @return [String]
    def self.sequence_unique_index_name
      'index_point_balances_on_owner_id_and_owner_type_and_sequence'
    end

    # @param amount [Integer]
    # @param attributes [Hash] Additional attributes to set on the new record.
    # @return [Integer] Returns the new points balance.
    def self.apply_change_to_points(amount, **attributes)
      retries ||= 0

      transaction(requires_new: true) do
        create!(amount: amount, **attributes).balance
      rescue ActiveRecord::RecordNotUnique => error
        raise error unless error.message.include?(self.class.sequence_unique_index_name)

        retry if (retries += 1) < MAX_RETRIES

        raise Royal::SequenceError, "Failed to update points: #{error.message}"
      end
    end

    # Returns the balance before this operation.
    #
    # @return [Integer]
    def original_balance
      balance - amount
    end
  end
end