class Expense < ApplicationRecord
  belongs_to :category

  enum frequency: { daily: 0, monthly: 1, annual: 2 }, _default: 0

  validates :name, :amount, :frequency, :date, presence: true
  validates :frequency, inclusion: { in: frequencies.keys }

  scope :daily, -> { where(frequency: 0) }
  scope :monthly, -> { where(frequency: 1) }
  scope :annual, -> { where(frequency: 2) }
end
