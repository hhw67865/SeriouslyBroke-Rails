class Paycheck < ApplicationRecord
  belongs_to :income_source
  accepts_nested_attributes_for :income_source

  validates_presence_of :date, :amount
  validates :amount, numericality: { greater_than: 0 }

end
