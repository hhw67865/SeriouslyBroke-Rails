# frozen_string_literal: true

# ACCEPTING A SUGGESTION, WRITTEN — the one transaction behind §8's bottom half.
#
# `SuggestionEngine` proposes a rule that does not merely need a `budgets` row: the two PROPOSING
# kinds (`:dated_bill`, `:rate`) name an envelope the user does not have yet, and an envelope is
# only reachable by the money once the CATEGORY points at it. So accepting one is three writes —
# find-or-create the pool, re-point the category, create the rule — and they are one act. A
# half-done acceptance is the worst outcome available here: a pool with no rule is an envelope
# nothing ever fills, and a re-pointed category with neither is every entry in that category
# silently landing in an envelope the user never agreed to.
#
# WHY A SERVICE AND NOT THE CONTROLLER: the controller's job is ownership (whose category, whose
# account, whose item) and the model's is shape; this is the ORDER of three writes, which is
# neither. `BudgetsController#create` calls #save and renders the same two outcomes it always did.
#
# WHAT THIS DOES TO `Σ pools == your bank balance`, MEASURED RATHER THAN REASONED. This header used
# to claim the invariant was untouched, on the grounds that a new pool has no movements and so adds
# zero. The first half is true and the conclusion is not, because the re-point does not move FUTURE
# spending — it moves the category's WHOLE ENTRY HISTORY, in one click.
#
# `PoolBalanceLedger::ENTRY_POOL_ID` is `COALESCE(entries.pool_id, categories.pool_id)` with NO date
# bound, and `PoolCalculator#balance` is deliberately start-date-agnostic (an envelope's balance is
# every dollar that ever reached it, minus every dollar that ever left). So the instant
# `category.pool_id` is written, every entry that category has ever carried — years of it — is
# inside the new envelope's lane. The envelope has no movements in, so it opens at exactly
# `-lifetime spend`, and `Σ pools` falls by that same figure. Nothing was written to `pool_movements`
# and no money moved.
#
# THE DIRECTION IS TOWARD TRUTH, which is why the code is right and the old sentence was wrong. A
# pool-less expense category's spending was outside the pool tree entirely: it left the bank and no
# pool's balance recorded it, so `Σ pools` was OVERSTATING the bank by exactly that lifetime total.
# The re-point does not break the invariant — it closes a gap the invariant had, moving Σ to the
# bank-true figure in one step.
#
# MEASURED ON THE DEMO, TWICE. Task 7's browser pass opened an envelope at `overdrawn $754.00`;
# this fix round re-measured on Entertainment, whose panel row proposes `$84.00 a period` and
# reports `$251.00 spent in 3 of the last 6 periods`. Accepting it opened the envelope at
# `overdrawn $496.00` — the category's LIFETIME spend, half of it older than any window the page
# measures — and `Σ pools` fell from $6,063.00 to $5,567.00, by exactly $496.00, with
# `PoolMovement.count` unchanged at 6. The panel's own figures cannot predict that balance, which
# is why the row has to say so in words.
#
# THE USER IS TOLD BEFORE THE CLICK. `_suggestion.html.erb`'s re-point paragraph carries the clause;
# an envelope that opens deep in the red on a screen whose other rows all read `$0.00 left` is the
# app looking broken, and it is not broken.
#
# Pinned by spec/system/budget_page/suggestions_spec.rb ("an envelope that opens carrying the
# category's past spending"), against planted literals on both sides.
#
# See docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §8 and
# .superpowers/sdd/2026-08-16-budget-page/task-7-brief.md amendment A.
class BudgetProposal
  # THE OPTIONAL ENVELOPE HALF of the budget form. `category` is the category to be re-pointed —
  # never the rule's owner, which is why it does not travel as the form's `category_id` — `name`
  # is what the new envelope would be called, and `account` is the account it would sit inside.
  #
  # Every one of the three is already ownership-scoped by the time it arrives: the controller
  # looks each up through `current_user`, so this class never asks whose anything is.
  Envelope = Data.define(:name, :account, :category) do
    # THE ENVELOPE THIS HALF WOULD JOIN RATHER THAN CREATE, or nil.
    #
    # ONE READER, and that is the point of it living on the value rather than inside #save: the
    # FORM asks it to decide what it says ("Joining your Utilities envelope" against "A new
    # Utilities envelope", an account picker against the account the envelope already sits in) and
    # `BudgetProposal` asks it to decide what it writes. Two spellings of "is this name taken"
    # would be a heading that promises one thing and a save that does another — which is exactly
    # the defect the panel's own three sentences were split to avoid, one screen earlier.
    #
    # TWO WAYS TO JOIN. The category's own pool, unless it is an ACCOUNT
    # (`Budget#pool_must_not_be_an_account` refuses a rule on one, so an account is not reusable
    # and the category is re-pointed off it); or a budget pool the user already has by this name.
    #
    # NOT MEMOISED — `Data` instances are frozen. The controller resolves it once per request and
    # hands the result to the view; nothing here calls it in a loop.
    def existing
      reusable = category.pool
      return reusable if reusable && !reusable.pool_type_account?

      category.user.pools.budget_pools.find_by(name_matches)
    end

    # Case-insensitively, because `Pool`'s own uniqueness validation is case-insensitive: matching
    # exactly here would find nothing and then create a pool the database refuses.
    def name_matches = Pool.sanitize_sql_array(["LOWER(name) = LOWER(?)", name.to_s])
  end

  attr_reader :budget, :envelope

  def initialize(budget:, envelope: nil)
    @budget = budget
    @envelope = envelope
  end

  # True and the three rows are written, or false and NOTHING is — including the ordinary path,
  # which is `budget.save` and has nothing to roll back.
  #
  # `ActiveRecord::Rollback` rather than a bang-and-rescue: a validation failure here is the
  # ORDINARY outcome (a name already taken, an item already claimed, a user with no account
  # nominated), and it has to arrive at the form as errors rather than as an exception. The flag
  # is read after the block because `Rollback` is swallowed by `transaction` and the block's own
  # value is lost with it.
  #
  # `requires_new: true`, AND IT IS NOT DECORATION — it is AllocationCommitter#call's own note,
  # for the same reason. A `transaction` block inside an already-open transaction opens NO
  # savepoint by default, so `ActiveRecord::Rollback` is swallowed and the outer transaction
  # commits anyway: the pool and the re-point would land while the rule that justified them did
  # not, which is precisely the half-written state this class exists to make impossible. Under
  # `use_transactional_fixtures` every example already runs inside a transaction, so without this
  # the mutation checks below would pass in production and fail in the suite — or worse, the
  # reverse.
  def save
    return budget.save if envelope.blank?

    written = false

    ActiveRecord::Base.transaction(requires_new: true) do
      written = write_all.present?
      raise ActiveRecord::Rollback unless written
    end

    written
  end

  private

  # The saved rule, or nil if any of the three steps refused. Each step answers the record it
  # wrote rather than a boolean, so a caller can never mistake "nothing to do" for "it worked".
  def write_all
    pool = find_or_create_envelope

    pool && re_point(pool) && write_rule(pool)
  end

  # REUSE BEFORE CREATE, AND THE REUSE IS THE MOST LOAD-BEARING LINE IN THIS CLASS.
  #
  # Several bills in one category share one envelope — Phone, Internet and Streaming Services are
  # three item-backed rules inside one Utilities envelope, which is what `item_must_belong_to_pool`
  # forces (a rule's item must sit in a category pointing at the rule's pool) and what
  # `PoolCalculator#sweepable_amount` already models. The engine's payload switches to `pool_id`
  # reuse on its own once the category is pool-covered, so the SECOND suggestion normally arrives
  # here without an envelope half at all.
  #
  # It does not always. A page loaded BEFORE the first acceptance still carries the creation half
  # on every one of that category's suggestions, and a second creation would either collide on
  # `Pool`'s name uniqueness or — after a rename — quietly re-point the category away from the
  # envelope the first acceptance filled, orphaning it. So the reuse decision is made here too,
  # against the database as it stands.
  #
  # THE SECOND REUSE IS BY NAME, and it is the demo seeds' own case rather than a hypothetical.
  # The engine names a proposed envelope after the CATEGORY, and the demo already holds a
  # "Utilities" envelope (funding an Electric Bill in a "Utility Bills" category) beside a
  # "Utilities" category that points at nothing — so every one of Phone, Internet and Streaming
  # Services proposed creating a pool whose name was already taken, and `Pool`'s uniqueness
  # validation refused all three. Measured in the browser; see the task report.
  #
  # An envelope already called this IS this envelope, so the rule joins it and the category is
  # re-pointed at it. Narrowed to `budget_pools` deliberately: an ACCOUNT cannot carry a rule at
  # all, and a SAVINGS GOAL by the same name is a different kind of thing — quietly hanging a
  # monthly bill on someone's holiday fund is worse than the uniqueness error, which the user can
  # answer by renaming in the form the name field is right there in.
  #
  # THE NARROWING IS ASYMMETRIC ON PURPOSE, and it is stated rather than tidied: the CATEGORY-pool
  # branch above accepts any non-account pool, savings goals included, while the NAME branch takes
  # envelopes only. A category already pointing at a savings goal is a link the user made
  # deliberately and a rule there is a claim they can see; a name collision is a coincidence, and
  # guessing from one that a holiday fund is the right home for a phone bill is not the same act.
  # `SuggestionEngine` cannot reach the first case anyway — its rate population is pool-less and
  # its bill population reuses `pool_id` — so matching the two would be a behaviour change with no
  # reachable case to pin it.
  #
  # `Envelope#existing` is the ONE reader for "would this join something", shared with the form.
  def find_or_create_envelope = envelope.existing || create_envelope

  # `pool_type: :budget` is set here and is NOT a wire parameter — an envelope is a budget pool by
  # definition, and taking the type from the form would let this path attach a funding rule to a
  # brand-new savings goal or, worse, to something calling itself an account.
  def create_envelope
    pool = envelope.category.user.pools.new(name: envelope.name, pool_type: :budget, account: envelope.account)
    return pool if pool.save

    carry_errors(pool, "Envelope")
    nil
  end

  # THE RE-POINT, and it is a bigger act than the rule beside it: every entry in this category
  # reaches the new envelope from now on, which is why the suggestion panel says so out loud
  # before the user clicks. A no-op when the category already points at the reused pool.
  #
  # `Category#destroy_budget_if_pool_linked` fires here: a category cap is destroyed by the
  # re-point, because a category cannot hold both a cap and a pool. That is the model's existing
  # rule and it is the honest trade — the cap reserved nothing (`Budget.steady_need` counts
  # pool-mode rules only) and the rule replacing it does — but it is a DELETION, so the panel
  # names the cap and its amount before the click.
  def re_point(pool)
    category = envelope.category
    return category if category.pool_id == pool.id
    return category if category.update(pool: pool)

    carry_errors(category, "Category")
    nil
  end

  def write_rule(pool)
    budget.pool = pool
    return budget if budget.save

    # The pool row is about to roll back. Left attached, the re-rendered form would name an
    # envelope that no longer exists and offer to submit its id.
    budget.pool = nil
    nil
  end

  # Another record's refusal, said on the record the form renders. `:base`, because the failing
  # attribute belongs to the pool or the category and `budget.errors[:name]` would print
  # "Name has already been taken" under the rule's own amount field.
  def carry_errors(record, label)
    record.errors.full_messages.each { |message| budget.errors.add(:base, "#{label}: #{message}") }
  end
end
