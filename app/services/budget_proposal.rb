# frozen_string_literal: true

# ACCEPTING A SUGGESTION, WRITTEN — the one transaction behind §8's bottom half.
#
# WHAT THIS CLASS USED TO BE, AND WHY ALMOST ALL OF IT IS GONE (two-ledger spec §3/§5). Under the
# pool layer a proposal could not merely write a `budgets` row: the two proposing kinds named an
# ENVELOPE the user did not have, and money only reached an envelope once the CATEGORY pointed at
# it — so accepting was three writes (find-or-create the pool, re-point the category, write the
# rule), and the class was mostly the reuse cascade that decided which envelope. Categories hold
# the money now. There is nothing to mint and nothing to re-point, and the entire find-or-create /
# join-by-name / join-by-pool_id apparatus, the `Envelope` value object it hung on, and the
# `Σ pools` argument its header carried are deleted with the layer.
#
# WHAT IS LEFT IS STILL TWO WRITES, AND THEY ARE STILL ONE ACT. A rule on a category is one of the
# two things that make that category START HOLDING MONEY (§4: `funded_since` is "the date it first
# got a rule or an allocation"), so accepting stamps the date and writes the rule. A half-done
# acceptance is still the worst outcome available: a `funded_since` with no rule silently moves
# every future entry in that category from AVAILABLE onto the category's own holdings — the
# start-date rule's whole subject — for a rule the user never got.
#
# WHY A SERVICE AND NOT THE CONTROLLER: the controller's job is ownership (whose category, whose
# item) and the model's is shape; this is the ORDER of two writes, which is neither.
# `BudgetsController#create` calls #save and renders the same two outcomes it always did.
#
# `Date.current`, NOT the entry's date or the rule's anchor: the category starts holding money the
# moment the user says so, which is now. Earlier spending stays where it physically was — it drains
# available, exactly as it did the day before — which is the same promise the panel's effect clause
# makes before the click, and it is why an accepted rule cannot open a category overdrawn by its own
# lifetime spend. (It could, and did, when the pool era re-pointed a category at a date-less
# envelope; §1 of the main-account spec opens with that shape on real data at $46,739.63.)
#
# `ApplicationController` wraps every request in the owner's zone, so `Date.current` is the user's
# own calendar day — the same day `CategoryLedger::ENTRY_CATEGORY_ID` compares against.
#
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §3 and §4.
class BudgetProposal
  attr_reader :budget

  def initialize(budget:)
    @budget = budget
  end

  # True and both rows are written, or false and NEITHER is — including the owner-less path, which
  # is `budget.save` and has nothing to roll back.
  #
  # `ActiveRecord::Rollback` rather than a bang-and-rescue: a validation failure here is the
  # ORDINARY outcome (an item already claimed, a blank amount), and it has to arrive at the form as
  # errors rather than as an exception. The flag is read after the block because `Rollback` is
  # swallowed by `transaction` and the block's own value is lost with it.
  #
  # `requires_new: true`, AND IT IS NOT DECORATION — it is AllocationCommitter#call's own note, for
  # the same reason. A `transaction` block inside an already-open transaction opens NO savepoint by
  # default, so `ActiveRecord::Rollback` is swallowed and the outer transaction commits anyway: the
  # `funded_since` stamp would land while the rule that justified it did not, which is precisely the
  # half-written state this class exists to make impossible. Under `use_transactional_fixtures`
  # every example already runs inside a transaction, so without this the mutation checks would pass
  # in production and fail in the suite — or worse, the reverse.
  def save
    return budget.save if budget.category.blank?

    written = false

    ActiveRecord::Base.transaction(requires_new: true) do
      written = write_all.present?
      raise ActiveRecord::Rollback unless written
    end

    written
  end

  private

  # The saved rule, or nil if either step refused. Each step answers the record it wrote rather than
  # a boolean, so a caller can never mistake "nothing to do" for "it worked".
  def write_all = start_holding && write_rule

  # THE STAMP, AND IT IS A BIGGER ACT THAN THE RULE BESIDE IT: from this date on, every entry in
  # this category drains the category rather than available, which is why the suggestion panel says
  # so out loud before the user clicks.
  #
  # `Category#start_holding` IS THE WRITE (final fix wave, I-1), and the no-op-when-already-holding
  # arm went with it: §4 names an ALLOCATION as the other event that starts the clock, so
  # `AllocationsController` needed the same rule, and two copies of "when does a category start
  # holding" is exactly the drift the one-reader discipline exists to prevent. What is left here is
  # this class's own contract — answer the RECORD rather than a boolean, so `#write_all`'s `&&` can
  # never read "nothing to do" as "it worked", and carry the refusal onto the form's record.
  def start_holding
    category = budget.category
    return category if category.start_holding

    carry_errors(category, "Category")
    nil
  end

  def write_rule = budget.save && budget

  # Another record's refusal, said on the record the form renders. `:base`, because the failing
  # attribute belongs to the category and `budget.errors[:funded_since]` would print a message
  # under a field this form does not have.
  def carry_errors(record, label)
    record.errors.full_messages.each { |message| budget.errors.add(:base, "#{label}: #{message}") }
  end
end
