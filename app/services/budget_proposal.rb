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
# THE INVARIANT (`Σ pools == the bank balance`) IS UNTOUCHED. A pool created here has no movements,
# so its balance is zero and it adds zero to the sum. The re-point moves future *spending* into the
# envelope's lane, which changes what the envelope is measured against, not how much money exists.
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
  Envelope = Data.define(:name, :account, :category)

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
  # against the database as it stands, on the same test the engine uses: the category's own pool,
  # unless that pool is an ACCOUNT (`Budget#pool_must_not_be_an_account` refuses a rule on one, so
  # an account is not reusable and the category is re-pointed off it).
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
  def find_or_create_envelope
    reusable = envelope.category.pool
    return reusable if reusable && !reusable.pool_type_account?

    envelope.category.user.pools.budget_pools.find_by(name_matches) || create_envelope
  end

  # Case-insensitively, because `Pool`'s own uniqueness validation is case-insensitive: matching
  # exactly here would look up nothing and then create a pool the database refuses.
  def name_matches = Pool.sanitize_sql_array(["LOWER(name) = LOWER(?)", envelope.name.to_s])

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
