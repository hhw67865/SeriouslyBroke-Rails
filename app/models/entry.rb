class Entry < ApplicationRecord
  belongs_to :item

  validates :amount, :date, presence: true

  delegate :category, to: :item
  delegate :user, to: :item

  scope :expenses, -> { joins(item: :category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(item: :category).where(categories: { category_type: :income }) }
  scope :savings, -> { joins(item: :category).where(categories: { category_type: :savings }) }
end
