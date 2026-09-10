# frozen_string_literal: true

# A category's spending, shaped for the rule form's item picker: one row per item, and one row
# for everything else — over the user's last complete periods.
class CategoryHistoryPresenter
  PERIODS = 3

  Row = Data.define(:item, :amounts, :average, :ruled_by)
  PickerRow = Data.define(:kind, :dom_id, :value, :name, :caption, :disabled, :amounts, :average, :checked)

  attr_reader :category, :today, :rule

  def initialize(category, today:, rule: nil)
    @category = category
    @today = today
    @rule = rule
  end

  def periods
    @periods ||= category.user.complete_periods(PERIODS, today: today)
  end

  def rows
    @rows ||= category.items.includes(:rule).order(:name).map { |item| row_for(item) }
  end

  # Every item with no rule of its own (besides the one being edited): the lane a whole-category
  # rule pays for, summed the same way as any other row.
  def everything_else
    @everything_else ||= begin
      unruled = rows.select { |row| row.ruled_by.nil? }
      amounts = periods.each_index.map { |i| unruled.sum { |row| row.amounts[i] } }
      Row.new(item: nil, amounts: amounts, average: average(amounts), ruled_by: catch_all_rule)
    end
  end

  # The rows the form draws, in order: everything else, each item, then a new item. `picked` is the
  # form's item_id — blank, an item's id, or "new".
  def picker_rows(picked)
    [everything_row(picked), *rows.map { |row| item_row(row, picked) }, new_row(picked)]
  end

  def selected_name(picked) = picker_rows(picked).find(&:checked)&.name || "what you pick above"

  private

  def everything_row(picked)
    taken = everything_else.ruled_by.present?
    PickerRow.new(
      kind: :everything,
      dom_id: "rule_item_everything",
      value: "",
      name: "Everything else in #{category.name}",
      caption: taken ? "already has a rule" : "the items below that have no rule of their own",
      disabled: taken,
      amounts: everything_else.amounts,
      average: everything_else.average,
      checked: picked.blank? && !taken
    )
  end

  def item_row(row, picked)
    PickerRow.new(
      kind: :item,
      dom_id: "rule_item_#{row.item.id}",
      value: row.item.id,
      name: row.item.name,
      caption: row.ruled_by && "has its own rule · #{row.ruled_by.rule_type.capitalize}",
      disabled: row.ruled_by.present?,
      amounts: row.amounts,
      average: row.average,
      checked: picked.to_s == row.item.id.to_s
    )
  end

  def new_row(picked)
    PickerRow.new(
      kind: :new,
      dom_id: "rule_item_new",
      value: "new",
      name: "the new item",
      caption: nil,
      disabled: false,
      amounts: [],
      average: nil,
      checked: picked == "new"
    )
  end

  def row_for(item)
    amounts = amounts_by_item.fetch(item.id, empty_amounts)
    Row.new(item: item, amounts: amounts, average: average(amounts), ruled_by: item.rule == rule ? nil : item.rule)
  end

  def catch_all_rule
    catch_all = category.rules.detect { |candidate| candidate.item_id.nil? }
    catch_all == rule ? nil : catch_all
  end

  def average(amounts)
    return nil if periods.empty?

    (amounts.sum / periods.size).round(2)
  end

  def empty_amounts = Array.new(periods.size, 0.to_d)

  # One query for every item's amounts, grouped into periods in Ruby rather than in SQL — the
  # window is small and this avoids a GROUP BY that Postgres would refuse to run un-aggregated.
  def amounts_by_item
    @amounts_by_item ||= entry_amounts.each_with_object(Hash.new { |h, k| h[k] = empty_amounts }) do |(item_id, date, amount), grouped|
      index = periods.index { |range| range.cover?(date) }
      grouped[item_id][index] += amount if index
    end
  end

  def entry_amounts
    return [] if periods.empty?

    Entry.expenses
      .where(items: { category_id: category.id }, date: periods.first.first..periods.last.last)
      .pluck(:item_id, :date, :amount)
  end
end
