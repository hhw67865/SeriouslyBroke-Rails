# frozen_string_literal: true

# The Budget page's row copy. See the UI design spec §8.
module BudgetPageHelper
  # ** `#pool_balance_clause` IS GONE (computed-claims spec §6). ** It appended `· holds $400.00`
  # to a row whose `HoldingStatus` had printed a bill's shortfall instead of the envelope's money,
  # so that every group said its balance exactly once. There is no balance: a category's money is
  # `Category#claim`, and §3.4's row prints `spent of rate` or `built up of target` — one figure,
  # named, with nothing left for a second clause to fill in. The status class it read is deleted.

  # ** THE THREE KINDS OF RULE, IN THE TWO REGISTERS THE PAGE NEEDS (rules-own-the-budget spec §3).
  # ** The overview's line is a heading over a SUM of rules, so `bill` pluralises there; the label on
  # one row names ONE rule and does not. `usage` and `choice` are mass nouns and are the same word in
  # both registers, which is exactly why the pair is a table rather than an `if` on pluralisation —
  # "Usages" is not a word this app should be one edit away from printing.
  #
  # `fetch`, SO A FOURTH TYPE FAILS LOUDLY rather than rendering a blank label beside a real figure.
  # `Budget::TYPE_RANK` is spelled with the same discipline and for the same reason.
  TYPE_HEADINGS = { "bill" => "Bills", "usage" => "Usage", "choice" => "Choice" }.freeze

  TYPE_LABELS = { "bill" => "Bill", "usage" => "Usage", "choice" => "Choice" }.freeze

  def rule_type_heading(type) = TYPE_HEADINGS.fetch(type.to_s)

  def rule_type_label(type) = TYPE_LABELS.fetch(type.to_s)

  # WHAT A RULE IS CALLED. The item it pays is the truest name — "Rent Bill" says what the money
  # does — and where there is none the rule is named by whatever owns it, because a rule with no
  # item is the category's own rate and the owner IS the subject.
  #
  # THE ITEM FIRST AND THE CATEGORY BEHIND IT, and there is no third arm. The POOL arm this note
  # used to describe — kept so a rule written before the cutover could still say its own name — is
  # GONE with `budgets.pool_id` (Task 8): `budgets.category_id` is NOT NULL, `Budget.for_user` is
  # one lane, and every rule the sacrifice view lists is owned by a category that has a name.
  #
  # Deliberately NOT `HomeHelper#pool_rule_label`, which falls back to the rule's SHAPE
  # ("Every 6 months"). That fallback is right on Home, where a row prints a pool's rules
  # underneath the pool's own name and repeating it would say the name twice. Here the shape is
  # already printed beside the amount by #budget_rule_amount, so the name is free to be the one
  # thing the row was otherwise missing.
  def budget_rule_name(budget)
    budget.item&.name || budget.category&.name
  end

  # "$400.00 / period", "$600.00 every 6 months" — the amount and what it is an amount PER.
  # A figure with no basis is unreadable on this page: $600 a period and $600 every six months
  # are the same digits and a twelvefold difference in what the user owes.
  #
  # ** THE "fed by hand" ARM IS KEPT AS A GUARD AND IS NO LONGER REACHABLE FROM THE DATA (two-shapes
  # spec §7). ** Zero used to be legal on exactly one shape — a goal the user fed by hand and never
  # on a schedule (`Budget#set-aside-only`) — and this printed "$0.00 / period" for one, beside a
  # real built-up figure on the same row: a rate of nothing read as a rule set wrong rather than a
  # rule that was never about a rate. `Budget` validates `amount > 0` on every shape now and
  # `TwoShapes` converted every such row, so no rule this can meet takes this arm. It stays because
  # the column cannot go negative on any shape and a row that somehow did should say this rather
  # than print a minus sign as a rate.
  def budget_rule_amount(budget)
    return "fed by hand" unless budget.amount.to_d.positive?

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

  # THE SAME FACT SAID IN A SENTENCE RATHER THAN BESIDE A FIGURE (design review M1). `/ period` is
  # right in a row where it sits against `$400.00` and reads as a unit; in prose it produced "What
  # this rule asks for / period." and "Currently $45.00 / period.", where the slash is a piece of
  # notation stranded in an English sentence. Only the `:per_period` arm differs — the other three
  # already read as words — so this delegates rather than restating the classification, and a fifth
  # cadence cannot be added to one of the two and forgotten in the other.
  #
  # ** THE "builds up" CLAUSE IS DELETED WITH THE COLUMNS (two-shapes spec §7). ** It read
  # `budget.carries-over` and named `budget.target-amount` where there was one, because a dateless
  # rule could either reset at the boundary or keep every unspent penny and the cadence alone could
  # not say which. There is one dateless shape now — the allowance that resets — and what a fund is
  # building toward is its own AMOUNT with a DATE beside it, which `#budget_rule_amount` and the
  # row's due date already print. So this is the cadence words and nothing else, exactly as it was
  # before the build-up clause was added, and every figure a resetting rule printed is unchanged.
  def budget_rule_basis_phrase(budget)
    budget.cadence == :per_period ? "per period" : budget_rule_basis(budget)
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

  # WHY THIS RULE IS NOT IN THE FILL ORDER, and never merely that it is not — a row that fell silent
  # here would read as a rule that failed to render.
  #
  # IT REPLACES `#budget_rule_reason`, WHICH SAID SOMETHING ELSE. That one worded one reason ("no
  # account — nothing can fund it") about a rule on an account-less pool, a setup problem inside the
  # layer being deleted. Both reasons here are about the PURPOSE ledger and both are transitional,
  # with a deleter each:
  #
  #   * a category that is not holding money yet — `Category#holder?` false, so it is outside
  #     `Category.in_fill_order` and no distribution reaches it. Task 7 makes `funded_since`
  #     editable, which is what makes this reachable at all.
  #   * a rule that names only a pool, written before the cutover. Task 8 drops the column, and
  #     this arm goes with it.
  #
  # A CLAUSE RATHER THAN A SENTENCE, which is the correction its predecessor made at the browser: a
  # full sentence under each row rendered the identical text down the whole band and read as a
  # rendering fault. Each row says why beside its own name, in the length the rest of this app's
  # rows use.
  #
  # THE CATEGORY IS NAMED ONLY WHERE THE ROW HAS NOT ALREADY NAMED IT (design review, nits).
  # `#budget_rule_name` prefers the ITEM a rule pays and falls back to its CATEGORY, so this clause
  # named the category twice on every item-less rule — the band rendered "Subscriptions ·
  # Subscriptions isn't holding money yet", which reads as a rendering fault rather than as
  # emphasis. An item-backed rule still needs the name, and for the original reason: "Phone · isn't
  # holding money yet" would never say WHAT is not holding it.
  #
  # `budget.item` is the same question `#budget_rule_name` asks to make its own choice — the two
  # branch on one fact, so the clause cannot repeat a name the row did not print.
  def budget_rule_unfilled_reason(budget)
    category = budget.category
    return "written before the cutover — no category to hold it" if category.blank?

    subject = budget.item.present? ? "#{category.name} has" : "has"
    "#{subject} no claiming date — spending here isn't counted against it"
  end

  # WHAT THE AMOUNT FIELD IS AN AMOUNT OF.
  #
  # ** THE SECOND CLAUSE AND ITS `schedule_shown:` SWITCH ARE GONE (rules-own-the-budget spec §7).
  # ** It read "— the schedule itself is already set on this rule", and it was true of exactly one
  # form: the edit form that refused to re-offer a rule's shape. §4's form offers every control on
  # both paths, so the sentence now points away from a radio the user is looking straight at, four
  # rows down. What is left is the clause that was always the point — the amount's UNIT — and it now
  # carries the build-up too, because "$300 per period" means one thing for a fund and another for a
  # grocery budget.
  # `unit:` IS THE ONE OVERRIDE, and it exists for exactly one row (fix round 1 — MED-5): a
  # `monthly`-no-anchor rule is read back as "Every period" by `RuleForm.from` (§5's ruling), so by
  # the time this renders the RECORD says per-period while the FIGURE in the box is still a month's.
  # `RuleForm#amount_unit` is what the form passes; every other caller passes nothing and gets the
  # record's own phrase.
  def budget_amount_hint(budget, unit: nil)
    "What this rule asks for #{unit || budget_rule_basis_phrase(budget)}."
  end

  # ** THE SENTENCE BESIDE A ROW WHOSE WORDS DO NOT DESCRIBE ITS OWN COLUMNS (fix round 1 — MED-5).
  # ** §5 rules that a `monthly`-no-anchor rule reads back as "Every period" and CONVERTS on save.
  # That is a real change to what the rule costs — `Budget#steady_ask` prices $260 a month at $120 a
  # fortnight, so saving it unchanged multiplies the claim by 2.17× — and a form that made it in
  # silence would be re-shaping a rule the user opened to correct a typo in.
  #
  # IT NAMES BOTH FIGURES AND WHAT TO DO, because "this will change" without the numbers is a warning
  # a reader cannot act on. Nil on every other rule, so the note is never a fixture of the page.
  def budget_monthly_conversion_note(rule_form)
    return nil unless rule_form.converted_from_monthly?

    amount = number_to_currency(rule_form.amount)
    "This rule is #{amount} a month; saving it as every period would make it #{amount} a period — " \
      "change the amount if you mean that."
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
