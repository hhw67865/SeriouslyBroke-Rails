# frozen_string_literal: true

# The Budget page's row copy. See the UI design spec §8.
module BudgetPageHelper
  # WHAT THE ENVELOPE IS HOLDING, and only where the row has not already said it.
  #
  # `pool_status_label` prints PoolStatus#amount, which IS the balance in four of the seven states
  # — the balance itself in three and its negation on :overdrawn. Printed unconditionally this
  # read "$400.00 left · holds $400.00" and "overdrawn $80.00 · holds -$80.00" — one number twice,
  # on ten of the demo's fourteen groups. Measured on the rendered page, not reasoned about.
  #
  # `PoolStatus#amount_is_balance?` rather than a state list of this module's own. Which states
  # print the pool's money is a fact about `PoolStatus#amount`, and a hand copy of its case
  # statement here would be a second reader free to drift from it the day an eighth state lands.
  # (String-testing the label for a `$` would be worse still — an assertion about a string this
  # module does not own.)
  #
  # The balance is therefore on screen for every pool either way; this clause is what puts it
  # there for the three states whose figure is a bill's shortfall instead.
  def budget_group_balance(group)
    return "" if group.status.amount_is_balance?

    "· holds #{number_to_currency(group.balance)}"
  end

  # WHAT A RULE IS CALLED. The item it pays is the truest name — "Rent Bill" says what the money
  # does — and where there is none the rule is named by whatever owns it, because a rule with no
  # item is the pool's or the category's own rate and the owner IS the subject.
  #
  # Deliberately NOT `HomeHelper#pool_rule_label`, which falls back to the rule's SHAPE
  # ("Every 6 months"). That fallback is right on Home, where a row prints a pool's rules
  # underneath the pool's own name and repeating it would say the name twice. Here the shape is
  # already printed beside the amount by #budget_rule_amount, so the name is free to be the one
  # thing the row was otherwise missing — and an orphan row, which has no group heading above it,
  # has no other way to say whose rule it is.
  def budget_rule_name(budget)
    budget.item&.name || budget.pool&.name || budget.category&.name
  end

  # "$400.00 / period", "$600.00 every 6 months" — the amount and what it is an amount PER.
  # A figure with no basis is unreadable on this page: $600 a period and $600 every six months
  # are the same digits and a twelvefold difference in what the user owes.
  def budget_rule_amount(budget)
    "#{number_to_currency(budget.amount)} #{budget_rule_basis(budget)}"
  end

  # A LOOKUP ON `Budget#cadence`, not a predicate cascade of its own. This module and
  # `HomeHelper#pool_rule_label` used to hold the same four-branch classification, in the same
  # order, each with its own copy of the comment saying why that order is a hazard — so the
  # classification moved to the record whose columns it reads and only the WORDS stayed here.
  # Home names a rule ("Every 6 months"); this says what an amount is per ("every 6 months"),
  # and it is the only one of the two ever asked about a category-mode rule.
  #
  # `:every_n` interpolates the interval here rather than carrying it, so the model's answer
  # stays a fixed set of four.
  def budget_rule_basis(budget)
    case budget.cadence
    when :per_period then "/ period"
    when :monthly then "a month"
    when :one_off then "once"
    else "every #{budget.interval_months} months"
    end
  end

  # THE LIST `PATCH /budget/reorder` TAKES, with one pool moved one place. `offset` is -1 for ▲
  # and +1 for ▼, and the whole band goes on the wire rather than "this pool, one place up",
  # because the endpoint's contract is an ORDER and not an instruction — the same shape the drag
  # controller builds out of the DOM, so a reorder means one thing however it was made.
  #
  # A move off either end returns the list unchanged, so the button at an edge is a no-op even if
  # the `disabled` attribute on it is ever bypassed. #reorder_edge? is what hides it.
  def reordered_pool_ids(groups, group, offset)
    ids = groups.map { |candidate| candidate.pool.id }
    index = ids.index(group.pool.id)
    target = index + offset
    return ids unless target.between?(0, ids.size - 1)

    ids.insert(target, ids.delete_at(index))
  end

  # Whether this pool is already as far as `offset` would take it — the top row cannot move up
  # and the bottom row cannot move down.
  def reorder_edge?(groups, group, offset)
    index = groups.index(group)

    offset.negative? ? index.zero? : index == groups.size - 1
  end

  # WHY THIS RULE IS NOT IN THE FILL ORDER, and never merely that it is not.
  #
  # The account-less clause is Home's own row phrasing, verbatim
  # (`HomeHelper#pool_problem_label`): it is the same fact about the same pool, and two wordings
  # for one setup problem would have the two screens disagree about what the user must do next.
  #
  # A CLAUSE RATHER THAN A SENTENCE, and that is a correction made at the browser. Both reasons
  # were first written as full sentences on their own line under the row; on the demo seeds that
  # rendered the identical sentence seven times down one band, which reads as a rendering fault
  # rather than as seven rules with the same problem. Each row still says why — it says it beside
  # its own name, in the length the rest of this app's rows use.
  def budget_rule_reason(rule)
    return "no account — nothing can fund it" if rule.reason == :no_account

    "caps a category — no envelope to fill"
  end

  # WHAT THE AMOUNT FIELD IS AN AMOUNT OF, and the pool-mode clause is restored rather than
  # dropped. "— the schedule itself is set on the pool" is true on the EDIT form, where the shape
  # is not on screen and a user reading "$1,200.00 every 6 months" needs to know where the six
  # months came from. It stops being true the moment the form RENDERS the schedule, which a new
  # pool-mode rule does: the interval is a field three rows below and the anchor is stated beside
  # it, so the clause would point away from a control the user is looking straight at.
  #
  # Keyed on `schedule_shown:` rather than on "is this a proposal", because the two are not the
  # same set — a suggestion that reuses an envelope by id arrives with no envelope half at all and
  # still renders its schedule.
  def budget_amount_hint(budget, owner:, schedule_shown: false)
    return "Enter the maximum amount you want to spend in this category" unless owner

    basis = "What this rule asks for #{budget_rule_basis(budget)}"
    schedule_shown ? "#{basis}." : "#{basis} — the schedule itself is set on the pool."
  end

  # -----------------------------------------------------------------------------------------
  # §8's bottom half — the suggestions panel
  # -----------------------------------------------------------------------------------------

  # A STABLE HANDLE FOR ONE SUGGESTION. Kind AND subject id, because a category and a pool can
  # share a name — "Transportation" is a rate suggestion's category and could equally be the pool
  # a drift suggestion names — and `Capybara.exact` is unset in this suite, so a name-keyed
  # selector is one rename away from matching two rows.
  def suggestion_key(suggestion) = "#{suggestion.kind}:#{suggestion.subject.id}"

  # WHERE ACCEPTING GOES, one destination per kind. `SuggestionEngine` deliberately knows no URLs
  # (its report says so), so the mapping lives here — and `prefill` travels verbatim, in the units
  # the engine already put it in.
  #
  # The two PROPOSING kinds land on the budget form with the whole payload in the query string;
  # the two kinds ABOUT AN EXISTING RULE land on that rule's own edit form, drift carrying the
  # observed figure and a dead rule carrying nothing — the user decides there between keeping it
  # and deleting it, and this page deletes nothing on its own.
  def suggestion_accept_path(suggestion)
    prefill = suggestion.prefill

    case suggestion.kind
    when :drift then edit_budget_path(prefill[:id], budget: prefill[:budget])
    when :dead_rule then edit_budget_path(prefill[:id])
    else new_budget_path(**proposal_query(prefill))
    end
  end

  # THE ENVELOPE HALF IS RENAMED ON THE WIRE, and only here. The engine states it as `pool:` plus
  # a top-level `category_id`; `budgets#new` already reads a top-level `category_id` as the OWNER
  # of a category-mode cap, and the engine means the category to be MOVED INTO the new envelope.
  # Two meanings for one key on one form is a request that caps a category when it was asked to
  # fund an envelope, so the half travels as `envelope:` — see BudgetsController#set_envelope.
  #
  # `pool_type` is dropped rather than carried: an envelope is a budget pool by definition and the
  # controller does not permit the key at all.
  def proposal_query(prefill)
    return { budget: prefill[:budget].merge(pool_id: prefill[:pool_id]) } if prefill.key?(:pool_id)

    {
      budget: prefill[:budget],
      envelope: { name: prefill[:pool][:name], account_id: prefill[:pool][:account_id], category_id: prefill[:category_id] }
    }
  end

  # WHETHER ACCEPTING WOULD MOVE THE CATEGORY. True when the payload carries the creation half —
  # which is the half that also re-points — and false when it reuses the envelope the category
  # already points at, the state the SECOND bill in a category is in once the first was accepted.
  #
  # Not the same question as "would it create a pool": a name already taken by an envelope is
  # JOINED rather than created, and the category still moves. See
  # BudgetPagePresenter#joined_envelope_name.
  def suggestion_re_points_category?(suggestion) = suggestion.prefill.key?(:pool)

  # The name the ENGINE proposed, read straight off the payload — no query, because this is only
  # ever printed on the branch where the presenter has already established nothing by that name
  # exists.
  def suggestion_proposed_envelope_name(suggestion) = suggestion.prefill[:pool][:name]

  # WHAT THE BUTTON SAYS IT WILL DO, per kind. "Accept" on all four would be one word covering
  # four different acts — two of them write a new rule and an envelope, one changes a figure on an
  # existing rule, and one opens a rule for a decision this page refuses to make for the user.
  def suggestion_accept_label(suggestion)
    case suggestion.kind
    when :drift then "Update the rule"
    when :dead_rule then "Review the rule"
    else "Write this rule"
    end
  end

  # THE INDEX STRIP'S WORDING — "10 bills · 5 rates · 4 drifting · 2 dead", §8's own shorthand for
  # a panel that on the demo runs to about 5,000px. Short by design: this is a jump list, and the
  # heading it lands on says the kind in full.
  #
  # `pluralize` prints the count with the noun, and the two kinds that are ADJECTIVES rather than
  # nouns ("drifting", "dead") take the count directly — "4 drifts" would name a thing this app has
  # no word for, and "4 dead rules" is the heading's job, not the index's.
  def suggestion_kind_count(kind, count)
    case kind
    when :dated_bill then pluralize(count, "bill")
    when :rate then pluralize(count, "rate")
    when :drift then "#{count} drifting"
    else "#{count} dead"
    end
  end

  # WHAT A RUN OF ROWS IS, said in full at the top of the run — the index's shorthand expanded, so
  # a reader who jumped knows what they jumped to. Deliberately not the same strings: an index item
  # is read in a line of four, a heading is read alone.
  def suggestion_kind_heading(kind)
    case kind
    when :dated_bill then "Dated bills"
    when :rate then "Rates"
    when :drift then "Rules that have drifted"
    else "Rules that look dead"
    end
  end

  # The fragment the index links to and the heading carries. One reader, because an anchor whose
  # two ends are spelled separately is a link that silently stops working.
  def suggestion_kind_anchor(kind) = "suggestions-#{kind}"

  # "every month" / "every 6 months", said of a PROPOSED interval rather than of a saved rule.
  # `budget_rule_basis` reads a Budget and there is no Budget yet, so this reads the integer.
  def suggestion_interval_label(months) = months == 1 ? "every month" : "every #{months} months"
end
