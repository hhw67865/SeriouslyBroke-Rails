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
  #
  # A STATUS RATHER THAN A `Group`, which is Task 5's widening and not a tidy-up: spec §8.1 puts
  # the same envelope on the Categories page, said in the same row vocabulary, and that screen has
  # no Group to hand over. Taking the object the clause actually reads — `PoolStatus`, which owns
  # both `amount_is_balance?` and `balance` — is what lets the second screen reuse this rather than
  # grow its own copy of the `· holds` rule. Renamed with the signature so the name stops promising
  # a Group. `Group#balance` delegates to its status, so the figure is unchanged on the Budget page.
  def pool_balance_clause(status)
    return "" if status.amount_is_balance?

    "· holds #{number_to_currency(status.balance)}"
  end

  # WHAT A RULE IS CALLED. The item it pays is the truest name — "Rent Bill" says what the money
  # does — and where there is none the rule is named by whatever owns it, because a rule with no
  # item is the category's own rate and the owner IS the subject.
  #
  # THE CATEGORY FIRST AND THE POOL BEHIND IT, in `Budget#user`'s own order and for its reason: the
  # category is the owner that survives, and the pool arm is TRANSITIONAL — `Budget.for_user` spans
  # both lanes until Task 8, and the sacrifice view lists every rule the user owns, so a rule
  # written before the cutover still has to be able to say its own name. Task 8 deletes the second
  # arm with the column.
  #
  # Deliberately NOT `HomeHelper#pool_rule_label`, which falls back to the rule's SHAPE
  # ("Every 6 months"). That fallback is right on Home, where a row prints a pool's rules
  # underneath the pool's own name and repeating it would say the name twice. Here the shape is
  # already printed beside the amount by #budget_rule_amount, so the name is free to be the one
  # thing the row was otherwise missing.
  def budget_rule_name(budget)
    budget.item&.name || budget.category&.name || budget.pool&.name
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

  # THE LIST `PATCH /budget/reorder` TAKES, with one category moved one place. `offset` is -1 for ▲
  # and +1 for ▼, and the whole list goes on the wire rather than "this category, one place up",
  # because the endpoint's contract is an ORDER and not an instruction — the same shape the drag
  # controller builds out of the DOM, so a reorder means one thing however it was made.
  #
  # A move off either end returns the list unchanged, so the button at an edge is a no-op even if
  # the `disabled` attribute on it is ever bypassed. #reorder_edge? is what hides it.
  def reordered_category_ids(groups, group, offset)
    ids = groups.map { |candidate| candidate.category.id }
    index = ids.index(group.category.id)
    target = index + offset
    return ids unless target.between?(0, ids.size - 1)

    ids.insert(target, ids.delete_at(index))
  end

  # Whether this category is already as far as `offset` would take it — the top row cannot move up
  # and the bottom row cannot move down.
  def reorder_edge?(groups, group, offset)
    index = groups.index(group)

    offset.negative? ? index.zero? : index == groups.size - 1
  end

  # `#budget_rule_reason` IS DELETED WITH THE ORPHAN BAND (two-ledger spec §5, Task 5). It said "no
  # account — nothing can fund it" about a rule on an account-less pool, which was the last shape a
  # rule outside the fill order could take. A rule belongs to a category and every category is in
  # the waterfall, so there is no row left for the clause to appear on.

  # WHAT THE AMOUNT FIELD IS AN AMOUNT OF, and the second clause is about WHERE THE SCHEDULE IS. It
  # is true on the EDIT form, where the shape is not on screen and a user reading "$1,200.00 every
  # 6 months" needs to know the six months is not something this form is asking them for. It stops
  # being true the moment the form RENDERS the schedule, which a new dated rule does: the interval
  # is a field three rows below and the anchor is stated beside it, so the clause would point away
  # from a control the user is looking straight at.
  #
  # IT NAMED THE POOL AND NAMES THE RULE (two-ledger spec §3). "— the schedule itself is set on the
  # pool" was never quite true even then: `basis`, `interval_months` and `anchor_date` are the
  # RULE's own columns and always were, and the pool it pointed at is the layer being deleted.
  #
  # Keyed on `schedule_shown:` rather than on "is this a proposal", because the two are not the
  # same set — a hand-made rate renders no schedule and is still a proposal of the user's own.
  def budget_amount_hint(budget, schedule_shown: false)
    basis = "What this rule asks for #{budget_rule_basis(budget)}"
    schedule_shown ? "#{basis}." : "#{basis} — the schedule itself is already set on this rule."
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
  #
  # `#proposal_query` IS GONE, AND THE PAYLOAD IS NOW ONE HASH (two-ledger spec §3). It existed to
  # rename the engine's envelope half onto the wire as `envelope:` — a proposed pool's name, type
  # and account, plus the category to be re-pointed at it — because none of that was a `Budget`
  # column. The owner IS a `Budget` column now, so the proposing kinds carry `budget[category_id]`
  # like any other field and there is nothing left to rename or to nest.
  def suggestion_accept_path(suggestion)
    prefill = suggestion.prefill

    case suggestion.kind
    when :drift then edit_budget_path(prefill[:id], budget: prefill[:budget])
    when :dead_rule then edit_budget_path(prefill[:id])
    else new_budget_path(budget: prefill[:budget])
    end
  end

  # WHETHER THIS ROW PROPOSES A RULE THAT DOES NOT EXIST YET — the two kinds whose acceptance
  # writes something new, and therefore the two whose rows owe the user a sentence about what
  # accepting does. Drift and a dead rule are about a rule that already exists; accepting either
  # opens its edit form and changes nothing on its own.
  #
  # THE KIND, WHERE THIS USED TO BE `#suggestion_re_points_category?` READING THE PAYLOAD. That
  # predicate asked whether the payload carried the envelope CREATION half, because that was the
  # half that also re-pointed the category — a question with three answers on a screen that had to
  # say three different sentences. Nothing is re-pointed; what differs between two proposing rows is
  # only whether the category is already holding money, which the engine states on the suggestion
  # itself (`detail[:starts_holding]`).
  def suggestion_proposes_a_rule?(suggestion) = [:dated_bill, :rate].include?(suggestion.kind)

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
