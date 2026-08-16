# frozen_string_literal: true

# WHAT THE SPLIT DID, said afterwards on the screen the user lands on.
#
# A module of its own rather than another few methods on DistributionsHelper, and the split is
# where the copy is READ rather than where it is about: everything in that module is rendered
# on /distributions/new, while this sentence is rendered in the flash band on Home, after the
# only request in this app that moves money. It is also the only copy here built from what was
# WRITTEN — an AllocationCommitter::Result and a balance read back out of the ledger — rather
# than from a proposal.
module DistributionConfirmationHelper
  # WHAT THE SPLIT ACTUALLY DID, said on the screen the user lands on afterwards. Built from
  # AllocationCommitter::Result — what was WRITTEN — plus the account's balance read back out
  # of the ledger after the write, so nothing in this sentence is a restatement of the proposal
  # the user just left.
  #
  # `replaced` leads, because amendment D forbids this sentence contradicting the banner the
  # user consented to: the screen said confirming REPLACES the previous split rather than adding
  # to it, and "Distributed $2,500.00" afterwards reads as a second $2,500.00 having moved.
  #
  # The buffer clause is the invariant said in words. Money only moved between the user's own
  # pools, so what did not reach an envelope is still in the account — and this is the same
  # figure Home's `buffer now` prints one redirect later, read from the same ledger.
  def distribution_confirmation(result, replaced:, buffer:)
    lead = replaced ? "Replaced this period's split — " : ""
    said = "#{lead}#{distribution_split_clause(result)}#{distribution_swept_clause(result)}."

    "#{said.upcase_first} #{number_to_currency(buffer)} stays in your buffer."
  end

  # THE TWO CLAUSES BELOW ARE INTERNALS OF THE SENTENCE ABOVE, and `private` here is a statement
  # of intent rather than a wall — worth saying so rather than leaving a reader to assume the
  # stronger thing. A helper module is mixed into the view context, so a template calling
  # `distribution_split_clause(...)` with an implicit receiver still reaches it; what this does
  # buy is that `helpers.distribution_split_clause` from a controller, and any explicit receiver,
  # now raise. Half a sentence about a split is not a thing any other screen should be able to
  # render, because it carries no verb, no buffer and no subject.
  private

  # NOT keyed on `movements.empty?`. An account whose overdraft outlives its own sweeps writes
  # sweep rows and funds nothing, so movements are present while no envelope got anything —
  # "distributed $0.00 into 0 envelopes" over a real movement is the wrong half of that story.
  # The count comes from the allocations alone; the sweep says itself in the next clause.
  def distribution_split_clause(result)
    return "nothing could be funded" if result.envelopes_funded.zero?

    "distributed #{number_to_currency(result.allocated)} into " \
      "#{pluralize(result.envelopes_funded, "envelope")}"
  end

  # "first", because the order is the point: the sweep is what made some of the money available
  # to hand out. Silent when nothing was swept, which is the ordinary shape of a period whose
  # envelopes are all still live.
  def distribution_swept_clause(result)
    return "" unless result.swept.positive?

    ", #{number_to_currency(result.swept)} swept back first"
  end
end
