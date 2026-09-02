# frozen_string_literal: true

# WHERE THE MONEY RAN OUT — the one home for a decision two screens draw a line with.
#
# Home's attention band and the distribution screen's waterfall each printed
# `rows.index { funded.zero? && short.positive? } || rows.length` in ERB, under two different
# gates. The predicate agreed, which is the shape this branch has been bitten by in every task:
# two readers of one money-shaped rule, free to drift the moment either is edited. It is not a
# rendering detail — it decides which envelopes the screen says were denied money.
#
# THE GATE STAYS WITH EACH CALLER, and it is now the SAME question asked twice rather than two
# different ones — which is worth stating, because it used to be the paragraph's whole point. This
# read: "a distribution is scoped to one account, so 'is anything short' is the whole question
# there, while Home fills each account's own pot and can only draw one line when there is a single
# account to draw it about." Both halves died with the accounts (two-ledger spec §2, Task 6): there
# is ONE root, both screens fill it in one pass, and `HomePresenter#cutoff`'s `accounts.one?` leg is
# deleted. Each presenter still answers "is anything short" for itself — `#covered?` on Home,
# `#short?` on the distribution — because each reads its own rows, and neither may derive that from
# the other's.
#
# WHAT THIS MODULE IS FOR IS UNCHANGED BY THAT: the RULE below is the shared half, and it was the
# half that could drift.
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
