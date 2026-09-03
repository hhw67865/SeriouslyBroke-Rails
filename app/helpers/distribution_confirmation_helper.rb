# frozen_string_literal: true

# WHAT THE SPLIT DID, said afterwards on the screen the user lands on.
#
# A module of its own rather than another few methods on DistributionsHelper, and the split is
# where the copy is READ rather than where it is about: everything in that module is rendered
# on /distributions/new, while this sentence is rendered in the flash band on Home, after the
# only request in this app that moves money on the purpose ledger. It is also the only copy here
# built from what was WRITTEN — an AllocationCommitter::Result and an available read back out of
# the ledger — rather than from a proposal.
module DistributionConfirmationHelper
  # WHAT THE SPLIT ACTUALLY DID, said on the screen the user lands on afterwards. Built from
  # AllocationCommitter::Result — what was WRITTEN — plus `CategoryLedger#available` read back out
  # of the ledger after the write, so nothing in this sentence is a restatement of the proposal
  # the user just left.
  #
  # `available:` IS `CategoryLedger#available` (two-ledger spec §2) and the sentence says the word
  # the ledger uses. It was `buffer:` and "stays in your buffer" until the answers-first Home spec
  # §3 retired that word app-wide: §7.1's buffer was the money no envelope had claimed, which is
  # exactly the purpose ledger's root, so the two names were always one thing.
  #
  # `replaced` leads, because amendment D forbids this sentence contradicting the banner the
  # user consented to: the screen said confirming REPLACES the previous split rather than adding
  # to it, and "Distributed $2,500.00" afterwards reads as a second $2,500.00 having moved.
  #
  # The last clause is the invariant said in words. Money only moved between the user's own root
  # and their own categories, so what did not reach an envelope is still available — and this is the
  # same figure Home prints one redirect later, read from the same ledger.
  def distribution_confirmation(result, replaced:, available:)
    lead = replaced ? "Replaced this period's split — " : ""
    said = "#{lead}#{distribution_split_clause(result)}#{distribution_swept_clause(result)}."

    "#{said.upcase_first} #{number_to_currency(available)} stays available."
  end

  # THE TWO CLAUSES BELOW ARE INTERNALS OF THE SENTENCE ABOVE, and `private` here is a statement
  # of intent rather than a wall — worth saying so rather than leaving a reader to assume the
  # stronger thing. A helper module is mixed into the view context, so a template calling
  # `distribution_split_clause(...)` with an implicit receiver still reaches it; what this does
  # buy is that `helpers.distribution_split_clause` from a controller, and any explicit receiver,
  # now raise. Half a sentence about a split is not a thing any other screen should be able to
  # render, because it carries no verb, no figure and no subject.
  private

  # NOT keyed on `allocations.empty?`. A root whose overdraft outlives its own sweeps writes sweep
  # rows and funds nothing, so rows are present while no envelope got anything — "distributed $0.00
  # into 0 envelopes" over a real row is the wrong half of that story. The count comes from the
  # allocation rows alone; the sweep says itself in the next clause.
  #
  # THE COUNT IS OF CATEGORIES AND THE WORD ON SCREEN IS "envelope", deliberately: a category with a
  # rule IS the envelope now (two-ledger spec §3), and re-wording every screen is Task 7's.
  def distribution_split_clause(result)
    return "nothing could be funded" if result.categories_funded.zero?

    "distributed #{number_to_currency(result.allocated)} into " \
      "#{pluralize(result.categories_funded, "envelope")}"
  end

  # "first", because the order is the point: the sweep is what made some of the money available
  # to hand out. Silent when nothing was swept, which is the ordinary shape of a period whose
  # envelopes are all still live.
  def distribution_swept_clause(result)
    return "" unless result.swept.positive?

    ", #{number_to_currency(result.swept)} swept back first"
  end
end
