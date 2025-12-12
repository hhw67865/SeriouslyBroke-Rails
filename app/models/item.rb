# frozen_string_literal: true

class Item < ApplicationRecord
  belongs_to :category
  has_many :entries, dependent: :destroy

  enum :frequency, { one_time: 0, monthly: 1, yearly: 2 }

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true
  validates :name, uniqueness: { scope: :category_id, case_sensitive: false }

  delegate :user, to: :category

  scope :expenses, -> { joins(:category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(:category).where(categories: { category_type: :income }) }
  scope :savings, -> { joins(:category).where(categories: { category_type: :savings }) }
end
