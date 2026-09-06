# frozen_string_literal: true

# ** THE ONE TYPED DOOR ONTO A RULE'S COLUMNS (two-shapes spec §5; rules-own-the-budget §4). **
#
# A rule is five columns — `amount`, `basis`, `interval_months`, `anchor_date`, `rule_type` — and
# only two of them are things a person can be asked about directly. The other three are a CODE for
# one question: WHEN is this money needed. §2's table is the whole family of legal combinations, and
# every row a person can write is reachable from two radios, a checkbox and three inputs — but only
# if something turns the words back into the columns.
#
# ** WHY THE WIRE CARRIES WORDS AND NOT COLUMNS. ** Before this class the form submitted `basis`,
# `interval_months` and `anchor_date` raw, which means every caller that wanted to write a rule had
# to know that `monthly + interval 1 + no anchor` is "every month" while `monthly + interval 1 +
# an anchor` is "every month, due on the 21st", and that `per_period + an anchor` is a shape the
# model refuses outright. That knowledge was spread over the form, the controller and
# `SuggestionEngine`, each spelling a piece of it. It is spelled ONCE here, in both directions:
#
#   `#budget`         the user's words → the columns
#   `.from(budget)`   the columns → the user's words (the edit form, and a proposal's prefill)
#
# ** THE WORDS CHANGED WITH THE SHAPES (two-shapes §5, Henry's ruling of 2026-09-05). ** There were
# four schedules and an "unspent money: resets / builds up" radio revealing a Target field. There are
# TWO schedules and a checkbox:
#
#   per_period            "a spending allowance that resets with your paycheck"
#   by_date               "money saved up toward a day — a bill or a goal", revealing Due <date>
#   by_date + repeats     …and "repeats every [N] months"
#
# `unspent` and `target-amount` are gone with the columns they wrote (§7). A fund IS a dated rule
# whose amount is its target, so "builds up toward $5,000" is written as "$5,000 by Jun 1, 2027" —
# the same words a bill uses, which is why one option covers both.
#
# ** `monthly` LEFT THE FORM AND NOT THE MODEL, AND THE READ-BACK PRESERVES THE MONEY RATHER THAN
# THE NUMBER (fix round 1's ruling). ** "$260 every month" with no due date is still a legal row (§2
# row 2) and `SuggestionEngine` still writes one; the form simply does not OFFER it, because it is
# not a shape people write by hand. `.from` reads such a row back as `per_period` — and it divides:
# the box holds `Budget#steady_ask`, WHAT THE RULE COSTS EACH PERIOD ON THIS USER'S GRID ($260 a
# month is $120.00 a fortnight), so saving it untouched writes `per_period 120.00` and the user's
# money is exactly where it was. The earlier reading kept the NUMBER and multiplied the cost by
# 2.17×, which the form could only warn about. See `.schedule_for` and `.per_period_amount`.
#
# ** WHAT THIS CLASS DOES NOT DO IS OWNERSHIP. ** `category_id` and `item_id` arrive off the wire
# and a stranger's id must 404 rather than 422 — a foreign record the user cannot see is not a form
# error, it is a record that does not exist for them — so `BudgetsController#scoped_owners` looks
# both up through `current_user` before this class ever sees them. The two collections this class
# used to render are deleted with the picker (see below); the boundary stays where §7a drew it.
#
# ** `anchor_date` AND `interval_months` ARE REFUSED RATHER THAN LAUNDERED, and the refusal lands
# under "When is it needed?". ** There is no honest reading of a due date on a per-period rule:
# dropping it changes WHEN the money is needed, which is the one thing a bill is about, and the rule
# that saved would silently not be the rule the user described. The Stimulus controller clears a
# field as it hides it, so with JavaScript the refusal is unreachable; without JavaScript every
# control is on screen and the message lands under one the user can see.
class RuleForm
  include ActiveModel::Model

  # THE WORDS ON THE WIRE. Two, and `repeats` is what tells the two dated rows apart — a checkbox
  # rather than a third schedule, because "every 6 months" is a detail OF "by a date" and not a
  # different answer to when the money is needed.
  SCHEDULES = ["per_period", "by_date"].freeze

  # ** A HAND-MADE RULE IS A PER-PERIOD RATE (Henry's ruling of 2026-08-20, §2 row 1). ** `basis`
  # defaults to `monthly` on the column, which with no interval and no anchor is the one combination
  # `Budget#shape_must_be_valid` refuses outright, so the default has to be stated somewhere. It is
  # stated here, once, and a proposal's own `schedule` simply overwrites it.
  #
  # THE TYPE HAS NO DEFAULT, AND THAT IS NOT AN OVERSIGHT. `budgets.rule_type` defaults to `usage`
  # so an untyped ROW claims neither "must be paid" nor "up to you", but §5 makes the radio REQUIRED:
  # the type decides the give-way order when free money goes below zero, and a form that
  # pre-answered it would be deciding what this person is willing to sacrifice on their behalf. A
  # blank arrives as nil and `Budget`'s presence validation says so, under the radio.
  DEFAULT_SCHEDULE = "per_period"

  # EVERY FIELD THE FORM SUBMITS, and `BudgetsController::BUDGET_FIELDS` is this list. Named here
  # because the list IS this class's interface: a field added to the controller and not to this
  # class is a control that writes nothing.
  FIELDS = [
    :category_id,
    :item_id,
    :rule_type,
    :amount,
    :schedule,
    :repeats,
    :interval_months,
    :anchor_date
  ].freeze

  # WHERE A `Budget` ERROR LANDS ON THIS FORM — the field whose CHOICE produced the column that was
  # refused. `basis`, `interval_months` and `anchor_date` are all consequences of "How often", so a
  # message about any of them belongs under that radio. The alternative is a 422 whose only visible
  # text is "please review the problems below", which is what an error on an attribute the form does
  # not render produces.
  #
  # ** `carries-over` AND `target-amount` LEFT THE MAP WITH THE COLUMNS (§7). ** They routed to the
  # "Unspent money" radio and to the Target input, neither of which is on this form any more.
  BUDGET_ERROR_FIELDS = {
    basis: :schedule,
    interval_months: :schedule,
    anchor_date: :schedule,
    amount: :amount,
    rule_type: :rule_type,
    item: :item_id,
    category: :category_id
  }.freeze

  # ** THE ROW'S OWN MONTHLY FIGURE, WHERE THIS FORM IS EDITING THE `monthly`-NO-ANCHOR SHAPE. **
  # `.from` reads such a row back as `per_period` at its DIVIDED amount (fix round 1's ruling), so
  # the box holds $120.00 where the row says $260.00 a month. Everything on the page that has to name
  # the row rather than the box — the note under the amount, the preview's two-unit line, the
  # "Currently …" line beside a drift's proposal — needs the figure that is no longer anywhere on the
  # form, so the flag CARRIES it: it is the monthly amount, and `#converted_from_monthly?` is the
  # predicate over its presence.
  #
  # IT IS NOT ONE OF `BUDGET_FIELDS` — a POST cannot set it, because it is a fact about the row
  # rather than an answer the user gave — and it is gated on the schedule the merge left standing
  # (see #initialize), because it stops being true the moment the user answers with a date.
  attr_reader :user, :budget, :anchor_date, :converted_from_monthly, :converted_per_period
  attr_accessor :category_id,
                :item_id,
                :rule_type,
                :amount,
                :schedule,
                :interval_months

  # `repeats` HAS A WRITER AND A READER OF ITS OWN (below), because the reader CASTS: the accessor's
  # would hand the view the raw string the wire carried.
  attr_writer :repeats

  # `budget:` IS THE EDIT PATH AND NOTHING ELSE. A new rule is a `Budget.new` this class builds; an
  # existing one is handed in so the words are applied to the row the user is editing — including a
  # SHAPE CHANGE, which §4 rules is legal (the claim is computed, so the walk re-runs from the
  # rule's accrual start under the new shape).
  # ** THE FLAG IS READ AFTER `#assign`, AND IT IS GATED ON THE SCHEDULE THAT SURVIVED THE MERGE. **
  # It says one thing — "the figure in this box is a MONTH's and this form is about to call it a
  # PERIOD's" — which stops being true the moment the user answers "When is it needed?" with a date.
  # Both callers that merge (`BudgetsController#update` and `#preview`) put `RuleForm.from`'s words
  # UNDER the submission, so a monthly row switched to "By a date" arrived carrying the flag from the
  # row and a schedule from the user: the note beside the amount, and the preview's two-unit line,
  # would both have warned about a conversion that is not happening.
  def initialize(user, params = {}, budget: nil)
    @user = user
    @budget = budget || Budget.new
    assign(params)
    @converted_from_monthly = monthly_amount_in(params)
    @converted_per_period = monthly_row_per_period(budget)
    apply_to_budget
  end

  def converted_from_monthly? = converted_from_monthly.present?

  # ** WHAT THAT MONTHLY FIGURE COSTS A PERIOD ON THIS FORM'S GRID — the number the box holds on an
  # UNTOUCHED edit (fix wave — MED-4). ** The note has to name it on the path where the box does
  # NOT: a drift suggestion prefills the amount with the figure it measured, so the box says $200.00
  # while the rule is $260.00 a month and $120.00 a period, and a note that claimed the box was
  # "what it costs each period" was describing a figure that had been replaced.
  #
  # TAKEN IN THE CONSTRUCTOR, BEFORE `#apply_to_budget` (see #initialize): by the time anything asks,
  # the record has had the form's words written onto it — its `amount` is the BOX's and its `basis`
  # is `per_period` — so asking then would divide the answer by the grid a second time. It is read
  # off the row as it arrived, through the same `.per_period_amount` `.from` used to fill the box.

  # ** THE UNIT THE ROW'S STORED AMOUNT IS IN, AND IT IS NO LONGER THE BOX'S. ** Since the read-back
  # divides, the figure on the form is per-period money on every path and `#budget_amount_hint` reads
  # the record for it. What still needs this is the "Currently $260.00 a month." line, which names
  # the figure on the ROW beside a drift's proposal — the one number on the page that is not in the
  # form's own unit.
  def amount_unit = converted_from_monthly? ? "a month" : nil

  # ** THE COLUMNS → THE WORDS. ** The reverse of `#apply_to_budget`, and it must round-trip every
  # row of §2 or the edit form silently re-shapes a rule the moment it is opened.
  #
  # `repeats` COVERS AN INTERVAL OF ONE. A monthly bill with a due date is `monthly + interval 1 +
  # anchor`, which reads as "by a date, repeating every 1 month" — the same pair of controls the
  # six-monthly bill uses. `Budget#cadence` calls that shape `:monthly` and is right to, because it
  # is answering what a period of this rule IS; this is answering which control the user set, and the
  # two questions part company on exactly this row.
  # ** `user:` IS THE GRID THE DIVISION IS DONE ON, AND IT IS THE FORM'S OWN (fix wave — T4(d)). **
  # The conversion below used to read the OWNER off the row (`Budget#user`, which walks the category)
  # while the note beside the box named `RuleForm#user`'s cadence — the same person in production and
  # two different people in a fixture, which is how a note came to say "$120.00 a period on your
  # biweekly grid" over a figure divided on a monthly one. One grid, named once, passed in.
  # Nil for the two in-memory rules `SuggestionEngine` builds, neither of which is this shape.
  def self.from(budget, user: nil)
    schedule = schedule_for(budget)
    repeats = schedule == "by_date" && budget.interval_months.present?

    converted = schedule == "per_period" && budget.basis_monthly?

    {
      category_id: budget.category_id,
      item_id: budget.item_id,
      rule_type: budget.rule_type,
      # ** DIVIDED ON THE ONE ROW WHOSE UNIT THE READ-BACK CHANGES (fix round 1's ruling). ** The
      # form's box is per-period money, so a monthly row's own figure would be the wrong number in
      # it — and saving it would be a 2.17× rise the user never asked for.
      amount: converted ? per_period_amount(budget, user) : budget.amount,
      schedule: schedule,
      repeats: repeats,
      # SEE `#converted_from_monthly`: THE ROW'S MONTHLY FIGURE, which is the one number the form no
      # longer holds anywhere and which three sentences on the page have to name. PRESENT OR ABSENT,
      # never `false`, on `interval_months`' own convention two lines down — `SuggestionEngine` puts
      # these words on an accept URL through `.compact`, and a `false` there would ride in every
      # query string the panel builds to say nothing at all.
      converted_from_monthly: (budget.amount if converted),
      # NOT the column unless the checkbox is on: an interval handed back for a control that is not
      # revealed is a value the user never typed, and #check_interval refuses exactly that on the way
      # in.
      interval_months: (budget.interval_months if repeats),
      anchor_date: budget.anchor_date
    }
  end

  # ** AN ANCHORLESS `monthly` ROW READS BACK AS `per_period`, AND WHAT SURVIVES THE READ IS THE
  # MONEY (§5's ruling, corrected in fix round 1). ** "$260 every month" with no due date is a legal
  # row and `SuggestionEngine` still writes one, but the form's two options do not include it: this
  # returns `per_period`, whose columns are `basis: per_period, interval nil, anchor nil`.
  #
  # THE FIGURE IS DIVIDED WITH THE SHAPE. Opening such a rule and saving it unchanged converts it —
  # that much was always the ruling — and the question the fix round settled is WHICH of the two
  # things is preserved, the number or the cost. It is the cost: `#per_period_amount` below is
  # `Budget#steady_ask`, the app's one normaliser, so a $260-a-month rule opens at $120.00 on a
  # fortnightly grid and saves as $120.00 a period. Nothing the user has budgeted moves. The earlier
  # reading kept the number, which the form could only WARN about — and a warning is not a defence
  # against a save the user has no reason to doubt.
  def self.schedule_for(budget) = budget.anchor_date.present? ? "by_date" : "per_period"

  # ** WHAT THE ROW COSTS A PERIOD ON ITS OWNER'S GRID — `Budget#steady_ask` AND NEVER A DIVISION
  # SPELLED HERE. ** That reader is the app's one answer to "what does this rule cost a period"
  # (`amount × 12 ÷ periods_per_year ÷ interval`), and it is what the Budget page's tiles, the drift
  # detector and `ClaimCalculator` all ask; a second spelling would be a second answer, on the one
  # screen that WRITES the figure.
  #
  # ** THE GRID IS THE FORM'S USER, FALLING BACK TO THE ROW'S OWNER (fix wave — T4(d)). ** It read
  # `Budget#user` alone, which is the same person on every path a browser can reach and a DIFFERENT
  # one in a fixture that hands the form a user the row does not belong to — and the note beside the
  # box names the form's cadence, so the two could describe two grids in one sentence. The row's
  # owner stays as the fallback for the callers that pass none (`SuggestionEngine`'s two in-memory
  # rules, neither of which is this shape).
  #
  # The nil arm is the honest fallback for a record with no owner to have a grid: the figure is left
  # exactly as stored, which is what an undeclared user's `steady_ask` answers anyway
  # (`periods_per_year` falls back to 12, so `260 × 12 ÷ 12` is $260).
  def self.per_period_amount(budget, user = nil)
    owner = user || budget.user
    return budget.amount if owner.nil?

    budget.steady_ask(owner, today: owner.today)
  end

  # True and the rule is written, false and `#errors` says why, keyed by the controls on screen.
  #
  # `BudgetProposal` ON THE CREATE PATH, because writing a rule on a category is also what makes
  # that category START HOLDING MONEY (two-ledger spec §4) and the two writes are one act. An
  # UPDATE is a plain save: the category is already holding, and re-stamping `funded_since` would
  # move the date every time somebody corrected an amount.
  def save
    return false unless choices_are_coherent?

    written = budget.new_record? ? BudgetProposal.new(budget: budget).save : budget.save
    carry_budget_errors unless written

    written
  end

  # ** `#category_options` AND `#item_options` ARE DELETED WITH THE CONTROLS THEY FILLED
  # (two-shapes spec §5). **
  #
  # `#category_options` was the OWNER PICKER — this user's expense categories, offered on a bare
  # `/budgets/new`. There is no bare `/budgets/new`: every door into the form names the category
  # (`BudgetsController::NEW_NEEDS_A_CATEGORY`), the page is titled "New rule for Groceries", and a
  # select beside that title would offer to send the rule somewhere the title does not promise.
  #
  # `#item_options` was EVERY item the user owns, rendered at once and filtered in the browser as
  # the picker moved. With one category in force there is nothing to filter BETWEEN: the select is
  # `category.items` — one statement, the category's own — and the Stimulus controller loses the
  # branch that used to hide the other categories' options. What the old list bought (a form that
  # worked with no JavaScript) is bought more cheaply by not needing the filter at all.
  #
  # WHAT THE USER IS STILL HELD FOR is the ownership scoping the CONTROLLER does (`#scoped_owners`)
  # and the period grid `RulePreview` prices against; the boundary §7a drew has not moved.

  delegate :persisted?, to: :budget

  # ** A CHECKBOX, WHICH REACHES A FORM OBJECT AS `"1"` / `"0"` / ABSENT AND NEVER AS A BOOLEAN. **
  # `ActiveModel::Type::Boolean` is the same cast a `boolean` column applies, so the string an
  # unchecked box submits (`"0"`) is false here exactly as it would be in the database — a truthiness
  # test would read it as checked and write an interval onto a one-off.
  def repeats? = ActiveModel::Type::Boolean.new.cast(@repeats).present?

  # ** THE CHECKBOX READS THIS, SO IT HAS TO BE A BOOLEAN AND NOT THE STRING THE WIRE CARRIED. **
  # `RuleForm.from` sets `repeats: true`, which a suggestion's accept link URL-encodes as the STRING
  # "true"; `check_box` decides `checked` by `value.to_s == checked_value` — `"true" == "1"` — so a
  # measured every-N-months bill opened its form with the box UNCHECKED and the interval field
  # hidden and blank beside it. That is not only a display fault: the browser submits the state of
  # the control, so pressing Create on that form wrote the bill as a ONE-OFF with the interval
  # dropped, silently turning a recurring bill into a single payment.
  #
  # ONE CAST, HERE, and `#repeats?` reads the same ivar — the two cannot part company. It is the
  # same treatment `#anchor_date=` gives the one other field whose raw wire value is not renderable.
  #
  # ** PRE-EXISTING, AND FOUND BY RE-RUNNING `system/budget_page/suggestions_spec` (see this task's
  # report). ** It is fixed here rather than left for the rule form's own task because the flow it
  # breaks — accept a dated bill, land on the form — is the one this task re-homed inside the
  # category panel.
  def repeats = ActiveModel::Type::Boolean.new.cast(@repeats)

  # A DATE, NOT THE STRING THE WIRE CARRIED. `date_field` formats its value with `strftime`, so a
  # String reaches it as a NoMethodError rather than as a rendered form — and this is the one field
  # whose raw value is not already renderable. Everything else is left exactly as it arrived, so a
  # user who typed `40.00` gets `40.00` back on a refusal rather than `40.0`.
  def anchor_date=(value)
    @anchor_date = Budget.type_for_attribute(:anchor_date).cast(value)
  end

  private

  # ** THE ROW'S MONTHLY FIGURE, KEPT ONLY WHILE IT IS STILL TRUE OF THE FORM. ** It says one thing —
  # the box holds the per-period reading of a row stored per MONTH — which stops being true the
  # moment the user answers "When is it needed?" with a date. Both callers that merge
  # (`BudgetsController#update` and `#preview`) put `RuleForm.from`'s words UNDER the submission, so
  # a monthly row switched to "By a date" arrived carrying the figure from the row and the schedule
  # from the user, and the note and the preview's two-unit line would both have described a
  # conversion that is not happening.
  def monthly_amount_in(params)
    value = params.to_h.symbolize_keys[:converted_from_monthly]
    return nil unless value.present? && schedule == "per_period"

    value.to_d
  end

  # SEE `#converted_per_period`. The row is asked BEFORE `#apply_to_budget` rewrites it, and only
  # where the flag above says this form is looking at that shape — a `Budget.new` on the create path
  # has no columns to divide and answers nil, which is the note's own "say nothing" arm.
  def monthly_row_per_period(budget)
    return nil unless converted_from_monthly? && budget&.basis_monthly?

    self.class.per_period_amount(budget, user)
  end

  # `params.key?`, not `params[field].present?`: a field the request did not mention is left as it
  # is (the edit path hands in the rule's own words first), while a field it mentioned as BLANK is a
  # cleared control and must reach the columns as one.
  def assign(params)
    params = params.to_h.symbolize_keys
    FIELDS.each { |field| public_send(:"#{field}=", params[field]) if params.key?(field) }

    @schedule = choice(@schedule, DEFAULT_SCHEDULE)
    # NO FALLBACK FOR THE TYPE — see `DEFAULT_SCHEDULE`'s note: the radio is required.
    @rule_type = choice(@rule_type, nil)
  end

  def choice(value, fallback) = value.presence&.to_s || fallback

  # ** THE WORDS → THE COLUMNS (§2.1's table, in one method). ** Run in the constructor rather than
  # in `#save`, so `#budget` is the record these words describe on every path — the form re-renders
  # from it after a refusal, and `BudgetsController#edit` reads its amount for the "currently…"
  # line.
  def apply_to_budget
    budget.assign_attributes(
      category_id: category_id.presence,
      item_id: item_id.presence,
      amount: amount,
      **schedule_columns
    )
    budget.rule_type = rule_type if rule_type_known?
  end

  # ** §2'S TABLE, IN THREE ROWS. ** `per_period` → its own basis and neither of the other two
  # columns; `by_date` → the `monthly` basis an anchor needs, with `repeats` deciding whether an
  # interval rides along. The one-off is `interval NULL` and is the shape a goal takes.
  def schedule_columns
    return { basis: :per_period, interval_months: nil, anchor_date: nil } unless schedule == "by_date"

    { basis: :monthly, interval_months: (interval_months.presence if repeats?), anchor_date: anchor_date }
  end

  def rule_type_known? = rule_type.blank? || Budget.rule_types.key?(rule_type)

  def schedule_takes_interval? = schedule == "by_date" && repeats?
  def schedule_takes_anchor? = schedule == "by_date"

  # ** WHAT THIS FORM ANSWERS THAT `Budget` CANNOT. ** The model validates the COLUMNS, and by the
  # time it sees them the words are gone: a repeating rule with no N is indistinguishable from a
  # one-off (`shape_must_be_valid` returns early on any anchored rule), and a per-period rule whose
  # date was quietly dropped is a valid rule that is not the one the user described. So the
  # coherence of the CHOICES is asked here, and every message lands on the control that made them —
  # which for both the date and the interval is "When is it needed?", the question they are details
  # of.
  def choices_are_coherent?
    errors.clear
    check_known_choices
    check_schedule_fields
    errors.empty?
  end

  def check_known_choices
    errors.add(:schedule, "is not one of the choices on this form") unless SCHEDULES.include?(schedule)
    errors.add(:rule_type, "is not a kind of rule") unless rule_type_known?
  end

  def check_schedule_fields
    return unless SCHEDULES.include?(schedule)

    check_interval
    check_anchor
  end

  def check_interval
    if schedule_takes_interval?
      errors.add(:schedule, "needs the number of months it comes round in") if interval_months.blank?
    elsif interval_months.present?
      errors.add(:schedule, "does not take a number of months — tick \"repeats\" to set one")
    end
  end

  def check_anchor
    if schedule_takes_anchor?
      errors.add(:schedule, "needs the date it is first due") if anchor_date.blank?
    elsif anchor_date.present?
      errors.add(:schedule, "does not take a due date — choose \"By a date\" for a dated rule")
    end
  end

  # `Budget`'S REFUSALS, RE-KEYED ONTO THE CONTROLS THAT CAUSED THEM. Anything unmapped keeps its
  # own key, and `:base` stays `:base` — an owner-less rule is a fact about the whole record and the
  # form prints base errors in its own notification.
  #
  # THE ONE EXCEPTION IS THE CATCH-ALL RULE, which `Budget` states on `:base` because it is about
  # the record rather than about a column — but on THIS form it is about a control: the sentence's
  # own second half ("or point this rule at a single item") is the "Pays" select, three rows up. It
  # is routed by the message's identity rather than by matching its words, which is why
  # `Budget::CATCH_ALL_TAKEN` is a constant.
  def carry_budget_errors
    budget.errors.each do |error|
      errors.add(form_field_for(error), error.message)
    end
  end

  def form_field_for(error)
    return :item_id if error.attribute == :base && error.message == Budget::CATCH_ALL_TAKEN

    BUDGET_ERROR_FIELDS.fetch(error.attribute, error.attribute)
  end
end
