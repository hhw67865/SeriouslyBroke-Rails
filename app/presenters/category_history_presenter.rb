# frozen_string_literal: true

# A category's spending, shaped for the rule form's item picker: one row per item, and one row
# for everything else — what each one last cost, how often it comes round, and what that is a
# period.
class CategoryHistoryPresenter
  PERIODS = 3

  Row = Data.define(:item, :pattern, :ruled_by)
  PickerRow = Data.define(:kind, :dom_id, :value, :name, :caption, :disabled, :last_paid_words, :usually_words, :per_period, :checked)

  attr_reader :category, :today, :rule

  def initialize(category, today:, rule: nil)
    @category = category
    @today = today
    @rule = rule
  end

  # Kept only for everything_else's honest per-period figure — an item's own figure comes from its
  # PaymentPattern instead.
  def periods
    @periods ||= category.user.complete_periods(PERIODS, today: today)
  end

  def rows
    @rows ||= category.items.includes(:rule).order(:name).map { |item| row_for(item) }
  end

  # Every item with no rule of its own (besides the one being edited): the lane a whole-category
  # rule pays for, its history read as one combined item.
  def everything_else
    @everything_else ||= begin
      unruled = rows.reject(&:ruled_by)
      payments = unruled.flat_map { |row| payments_by_item[row.item.id] }.sort_by { |(date, _amount)| date }.reverse
      Row.new(item: nil, pattern: pattern_for(payments), ruled_by: catch_all_rule)
    end
  end

  def everything_else_per_period
    return nil if periods.empty?

    (unruled_period_amounts.sum / periods.size).round(2)
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
    pattern = everything_else.pattern
    PickerRow.new(
      kind: :everything,
      dom_id: "rule_item_everything",
      value: "",
      name: "Everything else in #{category.name}",
      caption: taken ? "already has a rule" : "the items below that have no rule of their own",
      disabled: taken,
      last_paid_words: last_paid_words(pattern),
      usually_words: pattern.usually_words,
      per_period: everything_else_per_period,
      checked: picked.blank? && !taken
    )
  end

  def item_row(row, picked)
    item = row.item
    pattern = row.pattern
    PickerRow.new(
      kind: :item,
      dom_id: "rule_item_#{item.id}",
      value: item.id,
      name: item.name,
      caption: ruled_caption(row),
      disabled: row.ruled_by.present?,
      last_paid_words: last_paid_words(pattern),
      usually_words: pattern.usually_words,
      per_period: pattern.per_period,
      checked: picked.to_s == item.id.to_s
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
      last_paid_words: nil,
      usually_words: nil,
      per_period: nil,
      checked: picked == "new"
    )
  end

  def ruled_caption(row) = row.ruled_by && "has its own rule · #{row.ruled_by.rule_type.capitalize}"

  def last_paid_words(pattern)
    paid = pattern.last_paid
    return "—" if paid.nil?

    date, amount = paid
    when_words = date.year == today.year ? date.strftime("%b %-d") : date.strftime("%b %-d, %Y")
    "#{when_words} · $#{format("%.2f", amount)}"
  end

  def row_for(item)
    Row.new(item: item, pattern: pattern_for(payments_by_item[item.id]), ruled_by: item.rule == rule ? nil : item.rule)
  end

  def pattern_for(payments) = PaymentPattern.new(payments, today: today, periods_per_year: category.user.periods_per_year)

  def catch_all_rule
    catch_all = category.rules.detect { |candidate| candidate.item_id.nil? }
    catch_all == rule ? nil : catch_all
  end

  # One query for every item's payments, newest first — grouped in Ruby rather than fetched per item.
  def payments_by_item
    @payments_by_item ||= entry_rows.each_with_object(Hash.new { |h, k| h[k] = [] }) do |(item_id, date, amount), grouped|
      grouped[item_id] << [date, amount]
    end
  end

  def entry_rows
    @entry_rows ||= Entry.joins(:item).where(items: { category_id: category.id }).order(date: :desc).pluck(:item_id, :date, :amount)
  end

  def unruled_period_amounts
    unruled_ids = rows.reject(&:ruled_by).to_set { |row| row.item.id }
    amounts = Array.new(periods.size, 0.to_d)
    entry_rows.each do |item_id, date, amount|
      next unless unruled_ids.include?(item_id)

      index = periods.index { |range| range.cover?(date) }
      amounts[index] += amount if index
    end
    amounts
  end
end
