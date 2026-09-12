# frozen_string_literal: true

# One savings account's row on the Savings page: its balance, what it is owed, and the words for
# its targets. Every figure comes off one SavingsCalculator from one ClaimLedger.
SavingsLine = Data.define(:account, :balance, :claim, :accrued, :countable_span, :targets, :moved_words, :adjustments) do
  delegate :name, to: :account

  def targeted? = targets.any?
  def transferable? = claim.positive?
  def skippable? = accrued.positive?
  def target_words = targets.map(&:words).join(", plus ")
  def mode_words = account.keeps_extra? ? "keeps extra" : "asks every period"
  def since = targets.map(&:starts_on).min
end
