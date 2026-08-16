# frozen_string_literal: true

# WHERE THE MONEY RAN OUT — the one home for a decision two screens draw a line with.
#
# Home's attention band and the distribution screen's waterfall each printed
# `rows.index { funded.zero? && short.positive? } || rows.length` in ERB, under two different
# gates. The predicate agreed, which is the shape this branch has been bitten by in every task:
# two readers of one money-shaped rule, free to drift the moment either is edited. It is not a
# rendering detail — it decides which envelopes the screen says were denied money.
#
# The GATE stays with each caller, because it is genuinely different: a distribution is scoped to
# one account, so "is anything short" is the whole question there, while Home fills each account's
# own pot and can only draw one line when there is a single account to draw it about. Each
# presenter answers that for itself and asks this for the index.
module Waterfall
  module_function

  # The index the "ran out here" line is drawn AT: before the first row that received nothing
  # while asking for something, or `rows.length` when the money ran out INSIDE the last row and
  # there is no row below it to draw the line above.
  #
  # The block yields one row and returns `[funded, short]`, because the two callers hold different
  # row shapes (a Hash and a Data) and neither should have to become the other to be measured.
  def cutoff(rows)
    rows.index { |row| starved?(*yield(row)) } || rows.length
  end

  # A row that got NOTHING while asking for something — money DENIED, which is not the same as a
  # row that was short. A pool funded $355 of $400 did get money and belongs above the line; the
  # spec's §4.2 waterfall draws it beneath the last row that received any.
  def starved?(funded, short) = funded.zero? && short.positive?
end
