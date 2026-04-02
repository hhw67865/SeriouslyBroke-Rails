# frozen_string_literal: true

class Item < ApplicationRecord
  include ModelSearchable

  belongs_to :category, touch: true
  has_many :entries, dependent: :destroy

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true
  validates :name, uniqueness: { scope: :category_id, case_sensitive: false }

  delegate :user, to: :category

  searchable :name, label: "Name"

  scope :expenses, -> { joins(:category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(:category).where(categories: { category_type: :income }) }
  scope :savings, -> { joins(:category).where(categories: { category_type: :savings }) }

  def self.merge(target:, sources:)
    transaction do
      sources.each do |source|
        source.entries.update_all(item_id: target.id) # rubocop:disable Rails/SkipsModelValidations
        source.reload.destroy!
      end
    end
  end

  def move_to_category(target_category)
    existing = target_category.items.find_by("LOWER(name) = ?", name.downcase)
    if existing
      self.class.merge(target: existing, sources: [self])
    else
      update!(category: target_category)
    end
  end
end
