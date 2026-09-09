# frozen_string_literal: true

class Adjustment < ApplicationRecord
  belongs_to :rule, touch: true

  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :date, presence: true

  scope :dated_within, ->(range) { where(date: range) }

  delegate :user, to: :rule
end
