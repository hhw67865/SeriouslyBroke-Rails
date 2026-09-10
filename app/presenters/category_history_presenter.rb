# frozen_string_literal: true

# A category's spending, shaped for the rule form's item picker: one row per item, and one row
# for everything else — over the user's last complete periods.
class CategoryHistoryPresenter
  PERIODS = 3

  Row = Data.define(:item, :amounts, :average, :ruled_by)

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

  private

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
