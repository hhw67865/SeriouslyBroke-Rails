# frozen_string_literal: true

class Item < ApplicationRecord
  include ModelSearchable

  RULE_NEEDS_AN_EXPENSE = "has a rule, and rules only live on expense categories"
  RULE_ALREADY_THERE = "has a rule, and so does the item it would merge into — delete one of them first"

  belongs_to :category, touch: true
  has_many :entries, dependent: :destroy
  has_one :rule, dependent: :destroy

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, uniqueness: { scope: :category_id, case_sensitive: false }

  delegate :user, to: :category

  searchable :name, label: "Name"

  scope :expenses, -> { joins(:category).where(categories: { category_type: :expense }) }
  scope :incomes, -> { joins(:category).where(categories: { category_type: :income }) }

  # A merged source hands the target its entries and its rule, then dies. Entries landing in an
  # expense category leave their account behind: only income sits anywhere but main. Returns the
  # target, or false when a source's rule would collide with one the target already has.
  def self.merge(target:, sources:)
    sources = Array(sources)
    return false unless sources.all? { |source| free_to_merge_into?(target, source) }

    landed = target.category.income? ? {} : { account_id: nil }
    transaction do
      sources.each do |source|
        source.rule&.update!(category: target.category, item: target)
        source.entries.update_all(landed.merge(item_id: target.id)) # rubocop:disable Rails/SkipsModelValidations
        source.reload.destroy!
      end
    end
    target
  end

  def self.free_to_merge_into?(target, source)
    return true if source.rule.blank? || target.rule.blank?

    source.errors.add(:base, "#{source.name} #{RULE_ALREADY_THERE}")
    false
  end
  private_class_method :free_to_merge_into?

  def move_to_category(target_category)
    return false unless keeps_its_rule_in?(target_category)

    existing = target_category.items.find_by("LOWER(name) = ?", name.downcase)
    return self.class.merge(target: existing, sources: [self]) if existing

    transaction do
      update!(category: target_category)
      rule&.update!(category: target_category)
      entries.update_all(account_id: nil) unless target_category.income? # rubocop:disable Rails/SkipsModelValidations
    end
    true
  end

  private

  def keeps_its_rule_in?(target_category)
    return true if rule.blank? || target_category.expense?

    errors.add(:base, "#{name} #{RULE_NEEDS_AN_EXPENSE}")
    false
  end
end
