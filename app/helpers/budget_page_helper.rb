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

  def rule_type_heading(type) = TYPE_HEADINGS.fetch(type.to_s)

  # ** `TYPE_LABELS` AND `#rule_type_label` ARE DELETED (two-shapes spec §4). ** They printed a grey
  # "Bill" chip beside a rule's name on `_rule_row`, which died with the group card. The type is
  # still said twice on the new page and in two better places: as a coloured DOT per rule on the
  # category's row, and as the first word of `HomeHelper#shape_words` inside the open panel
  # ("bill · every 12 months"), which is the reading Home already gives it.

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

  # ** `#budget_rule_amount` IS DELETED (two-shapes spec §4). ** It printed the STICKER — what the
  # rule declares, `$1,200.00 every 6 months` — beside the claim's own figure on `_rule_row`, and
  # that row's header argued the repetition was deliberate ("the declaration confirmed by the
  # reading"). On a dated rule it was the target said twice inside one sentence, and the new table
  # has a column for the schedule alone: `HomeHelper#shape_words` says `bill · every 6 months`
  # without saying the money again, and Edit is one click away for the declaration itself.
  # `#budget_rule_basis` — the words the sticker was built from — survives, read by the dead-rule
  # suggestion and by the rule form's own hint.

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
  #
  # ** THE DRAWN ORDER IS WHAT THE ENDPOINT TAKES, AND THE REVERSAL IS DELETED (fix round MAJOR-1).
  # ** For one commit this list was drawn in GIVE-WAY order — type first, then priority — and this
  # method reversed the list before submitting it, because `Category.apply_fill_order` reads position
  # 0 as `priority: 0`. That reversal was a symptom: a list whose FIRST key is the rule type cannot
  # be dragged into a priority at all. Measured on Rent (bill, priority 0) beside Fun (choice,
  # priority 1): "move Fun down" produced the same two rows in the same places and moved RENT's
  # priority. The list is priority order now (`BudgetPagePresenter#category_rows`), so what the user
  # sees IS what `apply_fill_order` is handed, and `reorder_controller.js#submit` reads the DOM the
  # same way.
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

  # ** `#budget_rule_unfilled_reason` IS DELETED WITH `_not_filling` (two-shapes spec §4/§7). ** It
  # worded why a rule was outside the give-way order — "Utilities has no claiming date — spending
  # here isn't counted against it" — for a band that listed the rules no group could show. The list
  # is EVERY expense category now, so a category that is not holding money yet has a row of its own
  # with its rules under it; there is nothing left outside the list to have to excuse. What the band
  # was really about — that such a category's spending counts against nothing — is the category
  # page's own sentence, and the row here prints its claim like any other.

  # WHAT THE AMOUNT FIELD IS AN AMOUNT OF.
  #
  # ** THE SECOND CLAUSE AND ITS `schedule_shown:` SWITCH ARE GONE (rules-own-the-budget spec §7).
  # ** It read "— the schedule itself is already set on this rule", and it was true of exactly one
  # form: the edit form that refused to re-offer a rule's shape. §4's form offers every control on
  # both paths, so the sentence now points away from a radio the user is looking straight at, four
  # rows down. What is left is the clause that was always the point — the amount's UNIT.
  #
  # ** THE `unit:` OVERRIDE IS DELETED WITH THE MIXED UNIT IT DESCRIBED (fix round 1's ruling). ** It
  # existed for exactly one row: a `monthly`-no-anchor rule read back as "Every period" with its
  # MONTHLY figure still in the box, so the record's own phrase would have called a month's money a
  # period's. `RuleForm.from` DIVIDES that figure now — the box is per-period money on every path —
  # so the record's phrase is the true one on every path and there is nothing left to override. The
  # note below is what names the row's own unit.
  def budget_amount_hint(budget)
    "What this rule asks for #{budget_rule_basis_phrase(budget)}."
  end

  # ** THE SENTENCE BESIDE A ROW WHOSE SHAPE THE READ-BACK CHANGES (fix round 1's ruling). ** §5 rules
  # that a `monthly`-no-anchor rule reads back as "Every period" and converts on save; the fix round
  # settled which of the two things the conversion preserves, and it is the MONEY: `RuleForm.from`
  # divides by `Budget#steady_ask`, so $260 a month opens at $120.00 on a fortnightly grid and saves
  # as $120.00 a period. Nothing the user has budgeted moves.
  #
  # ** SO THIS IS NO LONGER A WARNING — IT IS AN EXPLANATION, and that is the change. ** It used to
  # say "saving it as every period would make it $260.00 a period — change the amount if you mean
  # that", which asked the reader to defend themselves against the form. What is left to say is why
  # the figure in the box is not the figure they remember typing, and that the cost is unchanged.
  # Nil on every other rule, so the note is never a fixture of the page.
  def budget_monthly_conversion_note(rule_form)
    return nil unless rule_form.converted_from_monthly?

    grid = rule_form.user&.period_cadence.presence
    was = number_to_currency(rule_form.converted_from_monthly)

    "This rule was #{was} a month — shown here as what it costs each period" \
      "#{" on your #{grid} grid" if grid}. Saving keeps that cost."
  end

  # ** WHERE THE CHEVRON GOES WITH SCRIPTING OFF (two-shapes spec §4). ** One category is open at a
  # time, so the link on a CLOSED row opens it and the link on the OPEN one closes the list — the
  # same control saying both halves of one state, which is why it is one reader rather than an `if`
  # in the partial. `category_list_controller` intercepts the click and flips the panels in place;
  # without it these two hrefs are the whole mechanism.
  def category_toggle_path(row) = row.open? ? budget_page_path : budget_page_path(open: row.category.id)

  def category_toggle_label(row) = "#{row.open? ? "Hide" : "Show"} #{row.category.name}"

  # ** WHAT A RULE-LESS CATEGORY'S ROW SAYS INSTEAD OF `$X claimed` (§4). ** Nothing claims this
  # money, so there is no claim to print; what there is is a fact about the entries, over the same
  # window the suggestions beside it are measured in (`SuggestionEngine#recent_spending`).
  #
  # "nothing spent yet" AT ZERO AND FOR A USER WITH NO WINDOW, because `$0.00 spent in 6 periods` is
  # a figure pretending to be a measurement — and a user who has declared no cadence has no periods
  # to have spent anything in. One sentence for both silences, because the row's reader cannot act
  # on the difference.
  def spent_recently_words(spending)
    return "nothing spent yet" if spending.nil? || !spending.total.positive?

    "#{number_to_currency(spending.total)} spent in #{pluralize(spending.periods, "period")}"
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
  # ** THE PANEL'S OWN CATEGORY RIDES ON THE PROPOSING LINK (two-shapes spec §4). ** The payload
  # already carries `budget[category_id]`, and `category_id` beside it is what the form's breadcrumb
  # and its empty-payload path read (`BudgetsController#new`) — the same parameter the panel's own
  # "+ New rule for <category>" button carries, so the two doors into that form are one door.
  def suggestion_accept_path(suggestion, category: nil)
    prefill = suggestion.prefill

    case suggestion.kind
    when :drift then edit_budget_path(prefill[:id], budget: prefill[:budget])
    when :dead_rule then edit_budget_path(prefill[:id])
    else new_budget_path(category_id: category&.id, budget: prefill[:budget])
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
  # ** "Write it →" IS THE MOCK'S OWN WORDING (two-shapes spec §4), AND THE ARROW IS THE POINT. **
  # It was "Write this rule", which reads as a button that WRITES one — and it does not: every one
  # of the four opens a form the user then saves. Inside the category's own panel the noun is
  # already said by everything around it, so what is left for the label is where the click goes.
  def suggestion_accept_label(suggestion)
    case suggestion.kind
    when :drift then "Update the rule"
    when :dead_rule then "Review the rule"
    else "Write it →"
    end
  end

  # ** `#suggestion_kind_count` AND `#suggestion_kind_heading` ARE DELETED WITH THE INDEX STRIP
  # (two-shapes spec §4). ** "10 bills · 5 rates · 4 drifting · 2 dead" was navigation for a
  # page-wide panel about 5,000px tall; inside the category it is about, a panel is two or three
  # rows under one heading and has nothing to navigate.

  # ** `#suggestion_kind_anchor` IS DELETED WITH THE RUNS IT NAMED (two-shapes spec §4). ** The
  # fragment `#suggestions-dated_bill` was the id on a run's heading inside the page-wide panel; the
  # panel is per category, so the categories page's pointer carries `?open=<category>` instead — a
  # parameter the page acts on rather than a scroll position it has to happen to have.

  # "every month" / "every 6 months", said of a PROPOSED interval rather than of a saved rule.
  # `budget_rule_basis` reads a Budget and there is no Budget yet, so this reads the integer.
  def suggestion_interval_label(months) = months == 1 ? "every month" : "every #{months} months"

  # -----------------------------------------------------------------------------------------
  # §5's preview card — the rule said back
  # -----------------------------------------------------------------------------------------
  #
  # ** THE COPY TARGET IS §5 VERBATIM: ** "Water gets $48.20 every 2 months, next due Oct 3. Each
  # period sets aside its share so the money is there on the day. It's a bill, so it's the last
  # thing to give way."
  #
  # ** THESE ARE THE SECOND PERSON'S WORDS FOR A SHAPE THE APP ALREADY CLASSIFIES, NOT A FIFTH
  # CLASSIFICATION. ** Which shape a rule is comes off `RulePreview`, which reads it off the one
  # `ClaimCalculator` it holds — the same reader behind `HomeHelper#shape_words`' `usage · every 12
  # months`. A row has space for three words; a preview is a sentence a person can check their own
  # intention against, which is why the two registers exist and why neither re-derives the shape.
  #
  # THEY LIVE HERE, BESIDE `#budget_amount_hint` AND `#budget_monthly_conversion_note`, which are the
  # rule form's other copy. This module is the Budget page AND the form it opens.

  # THE DATE ON THIS CARD ALWAYS CARRIES ITS YEAR, and that is a deliberate difference from the rows
  # (`HomeHelper#when_words` prints `Sep 17`). A row is read in the context of a period the screen
  # has already named; this is read seconds after the user typed the date into a date input, where a
  # mistyped year is both the easiest error to make and the one no other figure on the page reveals —
  # "$600 by Dec 1, 2036" is a rule whose per-period cost the card would otherwise report as $6.
  PREVIEW_DATE = "%b %-d, %Y"

  def rule_preview_date(date) = date&.strftime(PREVIEW_DATE)

  # THE HEADLINE. The bold half is the rule itself — who gets how much, how often — and the due date
  # of a REPEATING rule trails it unbolded, because "every 2 months" is the rule and "next due Oct 3"
  # is where the cycle happens to stand today. A one-off's date is inside the bold: the day IS the
  # rule there.
  def rule_preview_sentence(preview)
    lead = "#{budget_rule_name(preview.rule)} gets #{number_to_currency(preview.amount)} " \
           "#{rule_preview_schedule_words(preview)}"

    safe_join([tag.strong(lead), rule_preview_due_clause(preview), "."])
  end

  def rule_preview_schedule_words(preview)
    return "every period" if preview.rate?
    return suggestion_interval_label(preview.rule.interval_months) if preview.repeating?

    "by #{rule_preview_date(preview.next_due_on)}"
  end

  def rule_preview_due_clause(preview)
    preview.repeating? ? ", next due #{rule_preview_date(preview.next_due_on)}" : ""
  end

  # WHAT BECOMES OF THE MONEY — the one sentence that separates §2's two shapes, and the question
  # the deleted "Unspent money" radio used to ask the user to answer. It is not a question any more:
  # an allowance resets and a dated rule accrues, and which one this is was decided in step 2.
  #
  # THE DATELESS ARM IS FOR A USER WHO HAS DECLARED NO PERIOD, whose rate rule genuinely has no
  # boundary to name (`ClaimRows.period_range_for` returns nil for them). It says the fact without
  # the date rather than inventing a month nobody set.
  def rule_preview_holding_sentence(preview)
    return "Each period sets aside its share so the money is there on the day." unless preview.rate?
    return "Whatever's unspent resets when your next period starts." if preview.line.resets_on.blank?

    "Whatever's unspent resets on #{rule_preview_date(preview.line.resets_on)}."
  end

  # ** WHERE THIS RULE SITS IN THE GIVE-WAY ORDER, WHICH IS WHAT THE TYPE IS FOR (§3). ** The radio
  # in step 3 names three kinds; this says what choosing one COSTS, which is the only reason the
  # question is asked — when free money goes below zero the walk takes the choices first and the
  # bills last. `fetch` for `TYPE_HEADINGS`' own reason: a fourth type added to the enum without a
  # sentence is a card that silently stops explaining the most consequential answer on the form.
  TYPE_GIVE_WAY = {
    "bill" => "It's a bill, so it's the last thing to give way.",
    "usage" => "It's usage, so it gives way after your choices and before your bills.",
    "choice" => "It's a choice, so it's the first thing to give way."
  }.freeze

  def rule_preview_type_sentence(preview) = TYPE_GIVE_WAY.fetch(preview.rule.rule_type)

  # ** THE TWO UNITS, FOR THE ONE ROW WHOSE STORED FIGURE IS NOT THE ONE ON SCREEN (§5's ruling;
  # this task's carry). ** A `monthly`-no-anchor rule reads back as "Every period" at its DIVIDED
  # amount (fix round 1), so the row says $260.00 a month and the box says $120.00. Both numbers are
  # true and a user who remembers typing one of them is owed the other: the note beside the field
  # says why the box changed, and this says what the pair IS, in money, on the card that prices the
  # rule. The monthly figure is the ROW's (`RuleForm#converted_from_monthly` carries it); the
  # per-period one is whatever is in the box, so it follows an edit.
  #
  # NIL ON EVERY OTHER RULE, so the line is never a fixture of the card.
  def rule_preview_units(preview)
    return nil unless preview.converted_from_monthly?

    grid = preview.user.period_cadence.presence
    per_period = "#{number_to_currency(preview.amount)} a period"
    per_period = "#{per_period} on your #{grid} grid" if grid

    "#{number_to_currency(preview.monthly_amount)} a month · #{per_period}"
  end
end
