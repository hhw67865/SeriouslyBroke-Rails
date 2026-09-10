# frozen_string_literal: true

class Item < ApplicationRecord
  include ModelSearchable

  RULE_NEEDS_AN_EXPENSE = "has a rule, and rules only live on expense categories"
  RULE_ALREADY_THERE = "has a rule, and so does the item it would merge into — delete one of them first"
  RULES_COLLIDE = "only one rule can survive a merge"

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
  # target, or false when more than one rule would end up on the survivor.
  def self.merge(target:, sources:)
    sources = Array(sources)
    return false unless one_rule_between_them?(target, sources)

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

  # The survivor carries one rule at most, so the target's rule and the ruled sources together
  # may amount to one.
  def self.one_rule_between_them?(target, sources)
    ruled = sources.select(&:rule)
    return true if ruled.size + (target.rule ? 1 : 0) <= 1

    ruled.first.errors.add(:base, refusal_for(ruled))
    false
  end
  private_class_method :one_rule_between_them?

  # Which sentence is true depends on where the rule the merge collides with sits: on the target,
  # or on a second source. The names are sorted so the sentence does not depend on row order.
  def self.refusal_for(ruled)
    return "#{ruled.first.name} #{RULE_ALREADY_THERE}" if ruled.one?

    names = ruled.map(&:name).sort
    "#{RULES_COLLIDE} — #{names.to_sentence} #{names.size == 2 ? "both" : "each"} carry one"
  end
  private_class_method :refusal_for

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
