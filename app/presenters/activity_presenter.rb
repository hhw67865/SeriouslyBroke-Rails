# frozen_string_literal: true

# Everything that happened, newest first: entries, transfers and adjustments as one list of rows,
# each saying what it was, what it moved, and where to edit or undo it.
class ActivityPresenter
  PER_PAGE = 50
  Row = Data.define(:kind, :date, :created_at, :words, :amount, :color, :edit_path, :remove_path, :remove_confirm) do
    def entry? = kind == :entry
    def transfer? = kind == :transfer
    def adjustment? = kind == :adjustment
  end

  include Rails.application.routes.url_helpers

  attr_reader :user, :page

  def initialize(user:, page:)
    @user = user
    @page = page
  end

  def rows
    @rows ||= Kaminari.paginate_array(all_rows.sort_by { |row| [row.date, row.created_at] }.reverse).page(page).per(PER_PAGE)
  end

  private

  def all_rows = entry_rows + transfer_rows + adjustment_rows

  def entry_rows
    user.entries.includes(item: :category).map { |entry| entry_row(entry) }
  end

  def entry_row(entry)
    Row.new(
      kind: :entry,
      date: entry.date,
      created_at: entry.created_at,
      words: "#{entry.item.name} · #{entry.category.name}",
      amount: entry_amount(entry),
      color: entry.category.display_color,
      edit_path: edit_entry_path(entry, previous_url: activity_path),
      remove_path: entry_path(entry, return: "activity"),
      remove_confirm: "Remove this entry? Your balances will change."
    )
  end

  def entry_amount(entry) = entry.category.income? ? entry.amount.to_d : -entry.amount.to_d

  def transfer_rows
    ids = user.accounts.select(:id)
    Transfer.where(from_account_id: ids).or(Transfer.where(to_account_id: ids)).includes(:from_account, :to_account).map do |transfer|
      Row.new(
        kind: :transfer,
        date: transfer.date,
        created_at: transfer.created_at,
        words: "#{transfer.from_account.name} → #{transfer.to_account.name}",
        amount: transfer.amount.to_d,
        color: nil,
        edit_path: nil,
        remove_path: transfer_path(transfer, return: "activity"),
        remove_confirm: "Remove this transfer? The money goes back where it came from."
      )
    end
  end

  # Two separate loads, not one polymorphic `or`: a rule-sourced adjustment needs its rule's item
  # and category preloaded, and an account-sourced one only needs the account, so each half
  # preloads its own tree instead of one shared `includes(:source)` that leaves the rule's
  # item/category to N+1.
  def adjustment_rows
    rule_adjustments = Adjustment.on_rules(user.rules.select(:id)).includes(source: [:item, :category])
    account_adjustments = Adjustment.on_accounts(user.accounts.select(:id)).includes(:source)
    (rule_adjustments.to_a + account_adjustments.to_a).map { |change| adjustment_row(change) }
  end

  def adjustment_row(change)
    Row.new(
      kind: :adjustment,
      date: change.date,
      created_at: change.created_at,
      words: "#{adjustment_name(change)} · #{adjustment_verb(change)}",
      amount: change.amount.to_d,
      color: nil,
      edit_path: nil,
      remove_path: adjustment_path(change, return: "activity"),
      remove_confirm: "Remove this adjustment?"
    )
  end

  def adjustment_name(change) = change.rule? ? (change.source.item&.name || change.source.category.name) : change.source.name

  def adjustment_verb(change)
    return change.amount.negative? ? "reduced" : "topped up" if change.account? || change.source.cadence == :per_period

    change.amount.negative? ? "took back" : "set aside"
  end
end
