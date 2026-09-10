# frozen_string_literal: true

# One rule's counted entries, opened out into rows. It reads Rule#counted_entries and the rule's
# own calculator; it never recomputes what counts.
class RuleSpendingPresenter
  Row = Struct.new(:name, :amount, :count, :date, keyword_init: true) # rubocop:disable Lint/StructNewOverride

  attr_reader :rule, :today

  def initialize(rule, today: rule.today)
    @rule = rule
    @today = today
  end

  def range = calculator.countable_span
  def total = entries.sum(&:amount)
  def grouped? = rule.item_id.nil?
  delegate :over?, to: :calculator
  def rows = grouped? ? grouped_rows : entry_rows

  private

  def calculator = @calculator ||= rule.claim_calculator(today: today)
  def entries = @entries ||= rule.counted_entries(today: today).to_a

  def grouped_rows
    rows = entries.group_by(&:item).map do |item, group|
      Row.new(name: item.name, amount: group.sum(&:amount), count: group.size, date: nil)
    end
    rows.sort_by { |row| -row.amount }
  end

  # Already newest first, off `counted_entries`' own order.
  def entry_rows
    entries.map do |entry|
      Row.new(name: entry.description.presence || entry.item.name, amount: entry.amount, count: 1, date: entry.date)
    end
  end
end
