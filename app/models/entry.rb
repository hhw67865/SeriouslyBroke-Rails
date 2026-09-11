# frozen_string_literal: true

class Entry < ApplicationRecord
  include ModelSearchable

  belongs_to :item, touch: true

  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :date, presence: true

  delegate :user, :category, to: :item

  scope :expenses, -> { joins(item: :category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(item: :category).where(categories: { category_type: :income }) }
  scope :tracked, -> { where(categories: { tracked: true }) }
  scope :on_unruled_items, -> { where.not(item_id: Rule.where.not(item_id: nil).select(:item_id)) }
  # A rule's lane: its item's entries, or the whole category's entries on items with no rule of their own.
  scope :in_lane_of,
        lambda { |rule|
          next where(item_id: rule.item_id) if rule.item_id.present?

          expenses.where(items: { category_id: rule.category_id }).on_unruled_items
        }
  scope :since, ->(day) { where(date: day..) }
  # The newest entry of each item, in one query.
  scope :latest_per_item,
        lambda { |item_ids|
          where(item_id: item_ids).select("DISTINCT ON (entries.item_id) entries.*").order("entries.item_id, entries.date DESC, entries.created_at DESC")
        }

  searchable :description, label: "Description"
  searchable :date, type: :date, label: "Date"
  searchable :item, through: :item, column: :name, label: "Item"
  searchable :category, through: [:item, :category], column: :name, label: "Category"
end
