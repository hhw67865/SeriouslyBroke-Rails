# frozen_string_literal: true

# Everything the Home screen renders — THE PHYSICAL LEDGER AND THE CLAIMS COMPUTED OVER IT
# (computed-claims spec §§2-4). Read-only: it builds no movements, writes nothing, and — as of this
# task — reads no `allocations` at all.
#
#   THE PHYSICAL SIDE — the accounts, each showing what the bank says. `AccountLedger#balance_of`,
#                       and main's balance IS the pot. Untouched by this plan.
#   THE PURPOSE SIDE  — CLAIMS. `free = pot − Σ claims` (two-shapes §2), computed from the rules,
#                       the calendar, the spending and the dated adjustments. Nothing moved to put
#                       the money anywhere, so there is no balance to read and nothing to distribute.
#
# ** WHAT THIS CLASS STOPPED CONSUMING (Task 3 of the computed-claims plan), and every one of them
# is still ALIVE for the Distribute screen until Task 4 deletes it. ** The old readers are not gone;
# HOME simply no longer asks them anything:
#
#   `AllocationCalculator` (`#proposal`, `#waterfall`, `#available`) — the distribution's own
#     apparatus. `#remaining_plan` was a sum over its rows and `#free_to_spend` was
#     `available − remaining_plan`; both are replaced by `ClaimLedger#free`, which is a DEFINITION
#     rather than a subtraction of two moving parts (§2).
#   `HoldingCalculator` / `HoldingStatus` (`#status_for`, `#row_for`, `Row`, `#period_closed?`,
#     `#attention_categories`, `#dated_rules_for`, `#calculator_for`) — a holding is what was MOVED
#     into a category, and nothing moves. `over?` and an overdue date come off `ClaimCalculator`.
#   `CategoryLedger`'s allocation lane (`#ledger`, `#anything_set_aside_or_spoken_for?`) — its ENTRY
#     lane survives, and is what `#holder_spending_this_period` still composes.
#   `DistributionClock` (`#changed_after_distributing?`, `#undistributed_period?`) — it exists to say
#     which distribution is this period's, and there is no distribution.
#   `ReallocationPresenter` and the whole FIX apparatus (`Fix`, `#fix_for`, `#fix_amount_for`,
#     `#fix_candidates_for`, `#covered_by_waterfall?`, `#free_amount_for`) — a fix was an ALLOCATION,
#     a purpose-side move, and §5 of the spec leaves the purpose side with no moves at all. The
#     remedy for a shortfall is spending less or editing a rule (§4), which is what the strip now
#     says and where its one door goes.
#
# See docs/superpowers/specs/2026-09-03-computed-claims-design.md §§2-4 and
# docs/superpowers/specs/2026-09-02-answers-first-home-design.md §§2-6, whose four questions and
# whose copy this screen still answers — only the readers underneath changed.
class HomePresenter
  # WHAT AN ITEM-LESS RULE IS CALLED ON A BLOCK ROW (two-shapes spec §3, and the rule form's own
  # words — §5: "the whole category" means "anything in <category> no other rule pays"). It is NOT
  # `HomeHelper#pool_rule_label`, which names such a rule by its SHAPE ("Per period", "One-off"): a
  # block row already prints the shape in its own clause, so the shape said twice would displace the
  # one thing the row is missing — which lane of the category this rule is about.
  #
  # HERE RATHER THAN INSIDE `ClaimLine`, where it belongs and where rubocop will not have it
  # (Lint/ConstantDefinitionInBlock). The Data block's lexical scope is this class, so `#name` reads
  # it unqualified.
  WHOLE_CATEGORY = "Whole category"

  # ONE RULE'S CLAIM, AS THE SCREEN SAYS IT (spec §3.4). Every member comes off ONE
  # `ClaimCalculator`, from the page's ONE `ClaimLedger`, so a row cannot pair one rule's figure with
  # another's state and cannot cost a walk of its own.
  #
  # `shape` RATHER THAN A BOOLEAN, because §3.4 gives the two shapes two different sentences: a rate
  # rule says `spent of rate`, a dated one says `built up of target · next due · $X per period`, and
  # the classification lives in exactly one place (`ClaimCalculator#shape`).
  #
  # ** `capped` LEFT THE MEMBER LIST WITH `ClaimCalculator#capped` (two-shapes spec §7). ** It was
  # carried onto the row because an UNCAPPED building rule's `#target` was NIL and every reader of
  # `target` had to ask a second question first. There is no such shape: a dated rule's target is its
  # own amount and a rate rule's is zero, so `#target` is always a figure and `#dated?` is the only
  # question a reader has left.
  ClaimLine = Data.define(
    :category,
    :rule,
    :shape,
    :claim,
    :spent,
    :accrued,
    :built_up,
    :target,
    :next_due_on,
    :per_period,
    :over,
    :over_by,
    :overdue,
    :due_this_period,
    :resets_on
  ) do
    def rate? = shape == :rate

    # MONEY SAVED UP TOWARD A DAY (two-shapes spec §2) — a bill or a goal, which are one shape.
    def dated? = shape == :dated

    # SPENT PAST WHAT THE RULE HAD — `ClaimCalculator#over?`, which reads the figure BEFORE the clamp
    # at zero and is therefore the only reader that can tell "spent it exactly" from "spent more than
    # there was". Both leave a claim of zero (§3.1/§3.2).
    def over? = over

    # A DATE THAT PASSED WITH THE MONEY STILL MISSING (§3.2). Not merely a date in the past: a bill
    # whose fund is FULL is waiting to be PAID, which is a different sentence and not trouble — the
    # cycle rolls on payment, so an unpaid occurrence stays anchored where it was and goes on asking.
    #
    # A MEMBER RATHER THAN A DERIVATION, because the comparison is against the presenter's `today` and
    # a Data object computing it would have to reach for a clock of its own — which is the one thing
    # every reader on this screen is built to avoid. That day is the OWNER's (`User#today`, fix round
    # 2 — LOW-1), so a Data object reaching for `Date.current` would not merely be a second clock: it
    # would be a second clock in the wrong zone.
    def overdue? = overdue

    def trouble? = over? || overdue?

    # ** IS THE MONEY FOR THIS OCCURRENCE THERE, OR NOT (fix round 1 — MED-1)? ** It used to be half
    # of `#overdue?` and it is the wrong half to gate a trigger on (see `ClaimCalculator#overdue?`) —
    # a bill nobody paid needs a human whether or not the fund is whole. What it is exactly right for
    # is which SENTENCE the strip says about it: "the fund is short $200.00 — this needs paying" is a
    # different instruction from "the money is set aside — pay it and the fund starts again", and only
    # this pair can tell them apart.
    # BOTH READ `#target`, SO BOTH ASK `#dated?` FIRST. The strip only reaches them on an OVERDUE
    # rule, which has a due date and is therefore always dated — so the rate arms below are
    # unreachable from `_trouble.html.erb` today and are stated anyway, because "unreachable" is a
    # fact about one caller and this is a fact about the row.
    def fund_short? = dated? && built_up < target

    def fund_gap = dated? ? target - built_up : 0.to_d

    # WHAT THE BAR MEASURES: spending against the rate for an envelope, the running total against the
    # target for a fund (§3.4). One pair of readers rather than a signed number, because the two
    # halves are read by different parts of the row.
    def filled = rate? ? spent : built_up

    # THIS PERIOD'S ACCRUAL FOR A RATE RULE, THE TARGET FOR A DATED ONE. Never nil since the two
    # shapes: the uncapped fund that had no figure to be a fraction of is retired (§7).
    def denominator = rate? ? accrued : target

    # A BAR NEEDS SOMETHING TO BE A FRACTION OF, and a rate rule skipped to nothing this period has
    # no denominator — the row prints the fact and no track, `EntryImpactPresenter#bar?`'s rule for
    # its reason.
    def bar? = denominator.positive?

    # WHOLE PERCENT, CLAMPED, matching `HomePresenter::Progress#percent` and
    # `HoldingCalculator#progress_percentage` — the app's other bars — so all of them draw alike.
    #
    # ** THE BRIEF CALLS THIS `bar_fraction` AND IT IS THE SAME NUMBER, SO IT KEEPS ONE NAME. ** A
    # fraction beside a percent is two spellings of one quantity and the view would have to know
    # which one the CSS wants; every bar in this app is drawn `style="width: <percent>%"`.
    def percent
      return 0 unless bar?

      ((filled / denominator) * 100).round.clamp(0, 100)
    end

    # ── WHAT A CATEGORY BLOCK'S ROW IS MADE OF (two-shapes spec §3) ────────────────────────────
    #
    # All four are derivations rather than members: each is a reading of members this object already
    # carries, and a member would be a second place for the same fact to be set differently. The
    # WORDS that go beside them are `HomeHelper#shape_words` / `#when_words` / `#figure_words` — one
    # spelling each, shared with Task 3's Budget rows.

    # WHICH COLOUR THE STRIPE IS: the RULE's type, never the category's (rules-own-the-budget §3).
    # A category may carry a bill beside a choice, and the stripe is what says so at a glance.
    def stripe_type = rule.rule_type.to_sym

    # WHICH LANE OF THE CATEGORY THIS RULE PAYS FOR (§3.1's partition): the item it names, or
    # everything no other rule claims.
    def name = rule.item&.name || WHOLE_CATEGORY

    # ** THE MONEY IS NOT ALL THERE AND THE DAY IS HERE OR GONE. ** Two facts, and both are needed:
    # `#fund_short?` alone is true of every goal that has not finished saving — a $5,000 target due
    # in 2027 is not "short", it is accruing — and the date alone is true of a bill whose money is
    # sitting ready. This is the pair the runway's tick colours split on, said once so the tick and
    # the row underneath it cannot disagree about one rule on one afternoon.
    def short? = fund_short? && (due_this_period || overdue?)

    # WHAT THE BAR IS SAYING (§3). `over` is spending past what the rule had; `short` is the state
    # above; `full` is a bar that has arrived — a fund at its target, or a rate rule spent to the
    # penny. `normal` is everything in progress.
    #
    # `over` FIRST, because an over-spent rate rule is also a full one and the news is the excess.
    def bar_state
      return :over if over?
      return :short if short?
      return :full if bar? && filled >= denominator

      :normal
    end
  end

  # ONE CATEGORY AS A ROW, AND ITS RULES AS LINES (spec §3.4 + answers-first §4).
  #
  # ** THE RULING: A ROW PER CATEGORY, A LINE PER RULE. ** §3.4 gives per-RULE sentences and
  # `Category#claim` is a SUM, so a category carrying a $400-a-period rate rule beside a $1,200
  # six-monthly bill cannot honestly print one "spent of rate" or one "built up of target" — the two
  # figures are denominated in different things and summing them would state a number that is true
  # of neither. The category is still the heading (answers-first §4's fourth question is about
  # categories), and where it has exactly ONE rule — the ordinary shape, and the only one
  # `Budget#category_may_hold_one_item_less_rule` lets a user build without naming items — the row
  # renders as it always did: name, figure, bar.
  #
  # `spent` IS THE CATEGORY'S WHOLE SPENDING THIS PERIOD and is what an UNRULED holder prints. It is
  # deliberately not summed into the lines: each line already carries its own lane's spending, and
  # the lanes partition (§3.1's `Entry.on_unruled_items`), so adding them would be the same money
  # said twice.
  CategoryBlock = Data.define(:category, :rows, :claimed) do
    delegate :name, to: :category

    def rule_count = rows.size

    # ** THE HEADER TINT (two-shapes spec §3): "a category in trouble — any rule over, short or
    # overdue — tints its header". **
    #
    # IT IS A WIDER TEST THAN `ClaimLine#trouble?`, DELIBERATELY, AND THE DIFFERENCE IS `short?`.
    # That predicate is the TROUBLE STRIP's population (`#trouble_lines`), and §5 gives the strip
    # exactly two per-rule triggers — spending past the rate, and a date gone by unpaid. A bill due
    # on the 20th with $80 of its $120 saved is neither: nothing has gone wrong yet, the runway
    # names it in its pace line, and the block tints so the eye lands there. Widening the strip's
    # own predicate would have added a fifth kind of trouble to a list §5 fixes at four.
    def trouble? = rows.any? { |row| row.trouble? || row.short? }
  end

  # ** A CATEGORY WITH NO RULE AT ALL AND SPENDING THIS PERIOD (answers-first §4). ** The fact, and
  # no bar: nothing claims this money, so a denominator would be inventing the pressure rather than
  # reporting it.
  #
  # ** IT WAS TWO ROW TYPES SAYING ONE SENTENCE AND NOW IT IS ONE (this task). ** `PeriodRow` carried
  # a `budgeted?` arm whose whole output was `spent $32.00` — the same string this row prints — for a
  # holder that had been funded and never given a rule, while `UnbudgetedRow` printed it for a
  # category that was never funded. The two are the same fact about the same absence (no rule claims
  # these receipts), they rendered identical markup, and the split existed only because the budgeted
  # side of the section was a per-CATEGORY row. It is per-RULE now — a category with no rules has no
  # block to be a row of — so the arm has nowhere left to live and `#unbudgeted_rows` answers for
  # both populations at once. The name still fits, exactly: `Category#budgeted?` is "has a rule", so
  # a funded holder with none IS unbudgeted, and the widening is the predicate finally being asked
  # of the whole population rather than of one half of it.
  UnbudgetedRow = Data.define(:category, :spent)

  # ONE THING THAT NEEDS A HUMAN (answers-first §5, computed-claims §4). `kind` is which trigger;
  # `subject` is the thing it is about — a Pool for :overdraft, a ClaimLine for :over and :overdue,
  # nil for the two that are about the user's whole position.
  #
  # A TYPE RATHER THAN FOUR LISTS ON THE PRESENTER, because the strip has to know whether it is
  # rendering at all before it renders anything: `#trouble?` is `troubles.any?`, one question over one
  # list, where four predicates OR'd together in a view is four chances to add a fifth trigger and
  # forget the gate.
  #
  # ** `:undistributed` IS DELETED (computed-claims §6). ** "This period hasn't been distributed yet"
  # was trouble only because money had to be MOVED before a category could hold any; claims are
  # computed, so there is nothing to hand out and nothing to have missed. `:shortfall` takes its place
  # in the list — the state §4 says IS worth a human — and it is the one arm that carries a door.
  Trouble = Data.define(:kind, :subject)

  # ONE UNCOVERED CLAIM, AND HOW MUCH OF IT THE SHORTFALL EATS (§4). `amount` is what this claim is
  # short by after everything lower down the give-way order has already given way — so the last one
  # in the list is usually PARTIAL, which is the honest reading and the reason this is a walk rather
  # than a filter.
  Uncovered = Data.define(:line, :amount) do
    delegate :category, :claim, to: :line

    # Did the shortfall swallow the whole claim, or only bite into it? The strip says which.
    def whole? = amount >= claim
  end

  # WHERE THE PERIOD IS, AS THE CARD DRAWS IT (answers-first §2). Four members and two derived
  # answers, because the two are one subtraction apart and a member for each would be a second place
  # for the same number to be wrong.
  #
  # `day` IS 1-BASED AND INCLUSIVE AT BOTH ENDS, which is the only reading that makes both edges true:
  # the opening day is day 1 of 14 rather than day 0, and the closing day is day 14 with nothing left.
  # That fixes #days_left as `days - day` — the same figure as `last - today`, spelled off the members
  # this object already carries so the two cannot disagree.
  Progress = Data.define(:first, :last, :day, :days) do
    def days_left = days - day

    def percent = percent_at(day)

    # ** WHERE A GIVEN DAY OF THIS PERIOD SITS ALONG IT, AS A WHOLE PERCENT. ** The runway's ticks
    # and today's own marker are placed by this one method, so a tick cannot be measured against a
    # ruler the marker is not on. `day_index` is 1-based and inclusive at both ends, exactly like
    # `#day`: the opening day is 1 of 14 and the closing day is 14, which is what makes both edges
    # true.
    def percent_at(day_index) = ((day_index.to_f / days) * 100).round.clamp(0, 100)
  end

  # ── THE RUNWAY (two-shapes spec §3) ────────────────────────────────────────────────────────────
  #
  # ONE DATED RULE FALLING DUE INSIDE THIS PERIOD, AS A MARK ON THE PERIOD'S OWN RULER. The picture
  # is the point: a period is a line, today is a point on it, and the days money has to be there on
  # are points further along — which is the one question a list of figures cannot answer.
  #
  # ** `state` HAS TWO VALUES AND THE THIRD COLOUR IS THE RAIL'S — the ruling this task takes. **
  # §3 names three colours (green ready, red short, olive otherwise) and the brief asks exactly how
  # `accruing` differs from `short` for a rule due THIS period. It cannot differ: a rule due inside
  # this period either has its money (`claim == target`, ready) or does not (short) — there is no
  # third state left for a day that arrives before the next period does, and an "accruing" tick
  # would be a rule being told it still has time on the day the money is needed. So a tick is never
  # accruing, and the olive stays where it is always true: the RAIL, the part of the period that has
  # not happened yet. `ClaimLine#when_words` keeps the accruing SENTENCE for the rows it belongs to
  # — a goal due in 2027 reads `Apr 2 · +$41.67` — which is where "otherwise" was really pointing.
  RunwayTick = Data.define(:line, :day_index, :percent, :label, :amount, :state, :gap) do
    def ready? = state == :ready

    def short? = state == :short
  end

  # `progress` RATHER THAN A COPY OF `day` AND `days`: the card draws today's marker and the ticks on
  # ONE ruler, and two objects holding the period's length is two chances for a tick to be placed on
  # a period the marker is not on. The brief's `days`/`day` are delegated, so a reader asks for
  # exactly what it asks for.
  Runway = Data.define(:progress, :ticks, :due_total, :short) do
    delegate :first, :last, :day, :days, :days_left, :percent, to: :progress

    def any_due? = ticks.any?
  end

  # WHICH PACE SENTENCE THIS SCREEN IS SAYING, AND THE FIGURE IN IT (§3). Two arms of one question —
  # what a day may cost from here — so one object answers both and the view never compares figures:
  #
  #   free ≥ 0  →  fine, and the amount is what a day may cost for the rest of the period
  #   free < 0  →  not fine, and the amount is `#per_day_pace` — what a day must come DOWN by
  #
  # ** IT CARRIES THE FIGURE AND NOT THE SENTENCE, AND THAT IS A DEVIATION FROM THE BRIEF WITH A
  # REASON. ** The brief asks `#pace_line` for the sentence itself; no presenter in this app formats
  # money (`number_to_currency` is ActionView's, and every money string on every screen is a helper's
  # or a view's), so a presenter returning "$32.81 a day is fine…" would be the first — and the
  # sentence is then unavailable to the ONE other place that must say it identically, the shortfall
  # strip. `HomeHelper#pace_words(pace)` is the one spelling of both arms and both panels render it.
  Pace = Data.define(:amount, :fine) do
    def fine? = fine
  end

  attr_reader :user, :today

  # `rejected_movement:` IS ONBOARDING STEP 2'S OWN 422 (main-account spec §5), threaded through
  # rather than read off an ivar the view would have to know about. AccountFundingsController's
  # failure branch hands back the unsaved, invalid AccountMovement it tried to save, and
  # #funding_movement_for is how the ONE account it was for gets it back — every other account's card
  # renders a fresh, blank one.
  def initialize(user:, today: user.today, rejected_movement: nil)
    @user = user
    @today = today
    @rejected_movement = rejected_movement
  end

  # ── THE PHYSICAL LEDGER ────────────────────────────────────────────────────────────────────────

  def accounts
    @accounts ||= user.pools.accounts.order(:name).to_a
  end

  # WHAT THE BANK SAYS ABOUT ONE ACCOUNT — `AccountLedger#balance_of`, and for MAIN that figure is
  # the pot (§2: income − expenses − Σ moves out + Σ moves in).
  #
  # ONE LEDGER FOR EVERY ACCOUNT ON THE SCREEN — and it is the SAME `AccountLedger` the claim ledger
  # reads its pot and its total out of, so the accounts band, the hero's two figures and `free`
  # itself cannot come from two snapshots.
  delegate :balance_of, to: :account_ledger

  # Accounts that have gone below zero, and the loudest fact on the screen.
  #
  # THEY CARRY NO FIX BUTTON, and that was already the ruling before this plan: an overdrawn account
  # is a PHYSICAL fact — money already spent out of a bank account — and nothing on the purpose side
  # can reach it. What goes away is the button, not the debt.
  def overdrawn_accounts
    accounts.select { |account| balance_of(account).negative? }
  end

  # The debt as a positive figure, for the sentence that states it.
  def overdraft_for(account) = -balance_of(account)

  # ONBOARDING STEP 2'S ONE GATE (main-account spec §5): not main, and holding no money yet. ONE
  # predicate, asked by the view (which account gets the card — home/_account.html.erb) and by
  # AccountFundingsController (which write is legal), so the two cannot drift into two different
  # answers about the same account.
  #
  # `user.default_account.present?` FIRST (HIGH-1, a 500 fixed): the card used to read
  # `main_account.name` unconditionally, and a user with no main account 500'd on Home with no door
  # back in. No main account means no card anywhere.
  def awaiting_funding?(account)
    user.default_account.present? && account != user.default_account && balance_of(account).zero?
  end

  # ONBOARDING STEP 3'S OWN GATE (main-account spec §5): the account under review must BE the user's
  # main account, and the one-time latch — the "Opening Balance" category's own existence — must still
  # be open. Asked here and LITERALLY BY `OpeningBalancesController#create`, which builds its own
  # presenter and calls this same method, so the card's render gate and the write's legality gate
  # cannot drift into two different answers.
  def awaiting_opening_balance?(account)
    user.default_account.present? && account == user.default_account && !opening_balance_recorded?
  end

  # IS THIS THE ACCOUNT EVERYTHING FLOWS THROUGH? The view's gate on the Delete button, and it is
  # `Pool#main?` rather than a comparison of this screen's own: the model REFUSES the destroy on
  # exactly that predicate, so a differently-spelled question here could offer a button the server
  # then rejects — or hide one it would have accepted.
  def main?(account) = account.main?

  # THE FUND-ACCOUNT CARD'S FORM OBJECT (onboarding step 2). The rejected movement if THIS is the
  # account it was refused for — so its typed amount and its errors survive the re-render — and a
  # fresh unsaved one otherwise.
  def funding_movement_for(account)
    return @rejected_movement if @rejected_movement&.to_pool_id == account.id

    AccountMovement.new(to_pool: account)
  end

  # ── THE CLAIMS (computed-claims spec §§2-3) ────────────────────────────────────────────────────

  # THE CATEGORIES THIS SCREEN SPEAKS ABOUT, in the order priority ranks them.
  #
  # `Category.in_fill_order` IS STILL THE SET AND STILL THE ORDER, and priority survives this plan as
  # the GIVE-WAY order (§4) rather than as a fill order — the same ranking read for the opposite
  # question: who yields when the money runs out.
  #
  # `:budgets` eager-loaded because a row asks for them and so does the trouble strip.
  def categories
    @categories ||= user.categories.in_fill_order.includes(:budgets).to_a
  end

  # EVERY CATEGORY WITH A ROW ON THIS SCREEN — the holders, PLUS any category carrying a rule that is
  # not one (`funded_since` cleared after the fact, which `BudgetPagePresenter#unfilled_rules` is the
  # Budget page's band about). The second half is load-bearing rather than defensive: `ClaimLedger`
  # counts EVERY rule's claim into `free`, so a claim with no row would be money missing from the
  # hero's figure with nothing on the screen to explain it.
  #
  # `[priority, name]`, `Category.in_fill_order`'s own key — priority alone is not a total order, and
  # a tie falling through to database order means the same data ranks differently between loads.
  def budgeted_categories
    @budgeted_categories ||= (categories + claim_ledger.rules.filter_map(&:category))
      .uniq.sort_by { |category| [category.priority, category.name] }
  end

  # ── THE HERO CARD (answers-first §§2-3, on computed-claims' terms) ─────────────────────────────

  # THE NUMBER THE USER'S BANK APP SHOWS — `AccountLedger#pot`, which is main's balance and only
  # main's (§2). Named for what the card calls it, off the same ledger `free` subtracts from, so the two
  # figures on one screen cannot come from two snapshots.
  def in_checking = claim_ledger.pot

  # ** THE ONE DERIVED NUMBER (two-shapes spec §2): `free = pot − Σ claims`. **
  #
  # IT IS A DEFINITION, NOT A SUBTRACTION OF TWO MOVING PARTS. This was `available − remaining_plan`
  # — the distribution's post-sweep root less the rest of the period's unfunded ask — and both
  # operands were the distribution's own arithmetic. Claims are computed, so there is nothing to have
  # been handed out and nothing still owed: the money in checking is either claimed by a rule or it
  # is free.
  #
  # ** THE CAP AND THE OTHER-ACCOUNTS TERM ARE BOTH GONE (§2, Henry's ruling of 2026-09-05). ** It
  # was `min(pot, total_money − Σ claims)`, which folded savings into the subtraction and then capped
  # the answer at the pot — so for every user whose other accounts covered their rules the two hero
  # figures were the SAME NUMBER, and the claims were invisible in the one figure that is about them.
  # Money elsewhere is shown, never subtracted from or added to anything: `#other_accounts_total` is
  # its own sentence.
  #
  # NEVER CLAMPED. A period whose rules claim more than checking holds renders a negative figure in
  # red with a sentence that says why; rounding it up to zero would be the app telling the user they
  # are fine (§4: free below zero is a signal, never a refusal).
  def free_to_spend = claim_ledger.free

  # EVERYTHING THE RULES CLAIM — `Σ ClaimCalculator#claim` over every rule the user owns. The strip's
  # shortfall walk and the subline's cause both read it.
  delegate :total_claims, to: :claim_ledger

  # ** HOW MUCH OF CHECKING THE RULES HAVE SPOKEN FOR, AS THE TWO-SEGMENT BAR DRAWS IT (§3). ** The
  # money tile's bar is `free | claimed` of the pot, so one figure places both segments and they
  # cannot add to something other than the whole.
  #
  # NIL WHERE THE POT IS NOT POSITIVE, and that is the same refusal every other bar on this screen
  # makes: an overdrawn or empty account is not a quantity anything can be a fraction OF, and a bar
  # drawn there would have to pick a denominator the user does not have.
  #
  # CLAMPED AT 100, because claims routinely outrun checking (that is `#short?`, the state the whole
  # strip is about) and a segment 340% wide would simply run off the card. The figure beside it says
  # by how much.
  #
  # WHOLE PERCENT, matching `Progress#percent` and `ClaimLine#percent` — the app's bars draw alike.
  def claimed_percent
    return nil unless in_checking.positive?

    ((total_claims / in_checking) * 100).round.clamp(0, 100)
  end

  # ── THE SUBLINE'S TWO ARMS (two-shapes spec §2) ────────────────────────────────────────────────
  #
  # ** IT WAS A FOUR-ARM TABLE WITH SEVEN SENTENCES, AND THE `min` IS WHAT MADE IT ONE. **
  # `free = min(pot, total_money − Σ claims)` could go negative for two completely different reasons
  # — the claims outrun the money, or the money is in the wrong account — and could be POSITIVE with
  # or without a "rest" in checking depending on which term bound. Each of the four arms then needed
  # a predicate that ESTABLISHED its cause rather than inferring one from the signs of two figures,
  # which is what `#claims_outrun_the_money?`, `#rest_in_checking?` and `#free-cap-bound` were for.
  # All three are deleted with the `min`.
  #
  # `free = pot − Σ claims` has one cause per sign, so the card says TWO facts and never guesses
  # between them — how much of checking is claimed, and (separately) how much sits elsewhere:
  #
  #   free ≥ 0   →  "$X of checking is claimed by your rules."
  #                 + ", and $Y sits in N other accounts"        (#money_parked_elsewhere?)
  #   free < 0   →  "Your rules claim $X more than checking holds."     (red)
  #                 + "Move some in from your other accounts."   (#money_parked_elsewhere?)
  #                 else "You have spent past what you had."
  #
  # THE SECOND CLAUSE IS ABOUT A DIFFERENT PILE OF MONEY, which is the whole point of separating
  # them: what is in savings is neither added to `free` nor subtracted from it, so the card can state
  # it as a fact rather than as an explanation of an arithmetic the reader cannot see.
  #
  # ONE PREDICATE PER CAUSE, ASKED HERE. The view branches and never compares figures.

  # IS THERE MONEY IN ANOTHER ACCOUNT AT ALL — the cause both "parked" sentences assert, and the
  # figure is `#other_accounts_total`: THE SAME SUM THE ACCOUNTS LINE PRINTS (answers-first §6), so
  # the card cannot claim money the line below it shows as absent. `positive?` rather than
  # `#other_accounts.any?`: an account that exists and holds nothing is exactly the empty accounts
  # line the M-1 fixture read.
  def money_parked_elsewhere? = other_accounts_total.positive?

  # IS ANY OF THE USER'S MONEY CLAIMED BY A RULE — the noun of four of the seven sentences above.
  #
  # IT REPLACES `#anything_set_aside_or_spoken_for?`, whose two nouns were a HOLDING (money moved
  # into a category) and the rest of a distribution's ASK. Neither exists. `Σ claims` is one figure
  # the ledger has already computed for `free`, so this costs nothing the card was not paying — where
  # the old predicate opened the purpose ledger to ask each holder what it held.
  def anything_claimed? = total_claims.positive?

  # WHERE WE ARE IN THE PERIOD — day X of Y, and the bar's own percentage (answers-first §2).
  #
  # Off `#period_range`, never a second window: that reader is `User#period_containing`, the one
  # method that owns this arithmetic, and it is nil for a user who has declared no period. The card
  # draws no bar there rather than inventing a calendar month.
  def period_progress
    range = period_range
    return nil if range.nil?

    Progress.new(first: range.first, last: range.last, day: (today - range.first).to_i + 1, days: range.count)
  end

  # ── "THIS PERIOD" — ONE BLOCK PER CATEGORY, ONE ROW PER RULE (two-shapes spec §3) ──────────────

  # ** THE BLOCKS ARE `#give_way_order` GROUPED BACK, AND THAT IS THE WHOLE OF THE SORT. ** §3: "two
  # columns, give-way order (type rank of the category's lowest-ranked rule, then highest priority
  # number first — the one sort, `HomePresenter#give_way_order`, grouped back by category)".
  #
  # `group_by` KEEPS FIRST-APPEARANCE ORDER, which is exactly the rule the spec states: a block's
  # position is its FIRST line's position in the walk, so a category is placed by the rule of its
  # that gives way soonest. No second sort exists to disagree with the strip's list — the shortfall
  # walk and this section are one ordering read twice, which is what stops the strip naming a
  # category the section below it ranks somewhere else.
  #
  # THE ROWS INSIDE A BLOCK COME OUT IN THE SAME ORDER, and that is a consequence rather than a
  # separate decision: `#give_way_key`'s third term is `Category.rule_order`, the app's one
  # within-category key, so two rules of one type keep the order every other screen prints them in
  # and a choice sorts above a bill because that is the order they would give way in.
  #
  # ** IT REPLACES `#period_rows` AND `PeriodRow` (this task). ** That reader was a row per CATEGORY
  # sorted trouble-first then priority — a second ordering over the same lines, and one that could
  # not say what §3 asks for: a category's own rules ranked by type. Its `#silent?` gate and its
  # rule-less `budgeted?` arm survive in `#unbudgeted_rows`, which now answers for both populations.
  def category_blocks
    @category_blocks ||= give_way_order.group_by { |line| line.category.id }.map do |_id, rows|
      CategoryBlock.new(category: rows.first.category, rows: rows, claimed: rows.sum(0.to_d, &:claim))
    end
  end

  # ** THE RUNWAY: THIS PERIOD AS A LINE, WITH A MARK ON EVERY DAY MONEY IS NEEDED (§3). **
  #
  # ONE TICK PER DATED RULE WHOSE `next_due_on` FALLS INSIDE `User#period_containing(today)` — no
  # other date arithmetic anywhere in it: the window is `#period_range`, the position is
  # `Progress`'s own 1-based day, and the two are the same object the marker is drawn from.
  #
  # AN OVERDUE RULE HAS NO TICK, and that is the window doing its job rather than an omission: its
  # date is in a period that has gone, so there is no point on THIS ruler for it to sit on. It is in
  # the trouble strip, which is where a date already missed belongs.
  #
  # NIL FOR A USER WHO HAS DECLARED NO PERIOD — the same refusal `#period_progress` makes, for the
  # same reason: a runway is a picture OF a period, and inventing a calendar month would draw thirty
  # days nobody agreed to.
  def runway
    return @runway if defined?(@runway)

    @runway = build_runway
  end

  # WHAT A DAY MAY COST FROM HERE (§3), as the figure and which sentence it belongs to. See `Pace`.
  #
  # THE DIVISOR IS FLOORED AT ONE ON BOTH ARMS, and the floor is the CLOSING DAY rather than a guard:
  # `Progress#days_left` is zero on the last day of the period, when today is the whole of what is
  # left — the same floor and the same reason `#per_day_pace` carries.
  def pace_line
    progress = period_progress
    return nil if progress.nil?
    return Pace.new(amount: per_day_pace, fine: false) if short?

    Pace.new(amount: (free_to_spend / [progress.days_left, 1].max).round(2), fine: true)
  end

  # EVERY CATEGORY WITH NO RULE AND SPENDING INSIDE THIS PERIOD (answers-first §4): the fact, and no
  # bar. Two populations that are one fact — a category nobody funded, and a holder that was funded
  # and never given a rule — and see `UnbudgetedRow` for why they were two rows for one sentence.
  #
  # ZERO-SPEND ONES ARE ABSENT BY CONSTRUCTION on both halves: neither grouped sum has a key for a
  # category nothing was spent on, which is the rule stated as a query rather than as a filter
  # somebody could forget.
  #
  # ORDERED BY NAME, not by amount: these rows carry no plan and therefore no ranking, and sorting
  # money the app is not asking the user to do anything about would imply one.
  def unbudgeted_rows
    @unbudgeted_rows ||= (unruled_holder_rows + unfunded_category_rows).sort_by { |row| row.category.name }
  end

  # ── TROUBLE, ONLY WHEN TRUE (answers-first §5, computed-claims §4) ─────────────────────────────

  # EVERYTHING THAT NEEDS A HUMAN, AS ONE LIST, in the order a reader needs it: money already gone
  # (a bank overdraft), then the one fact about the user's whole position that spending can still
  # change (the shortfall), then the categories it is going wrong in, then the verdict no amount of
  # care this period can fix.
  #
  # FOUR KINDS WHERE THE OLD STRIP HAD FIVE, and the arithmetic of the change is: `:undistributed`
  # DIED (§6 — there is no distribution to have missed), `:category` SPLIT into `:over` and
  # `:overdue` (they were one `HoldingStatus` state machine and are now two facts about a claim,
  # each read off `ClaimCalculator`), and `:shortfall` is new (§4).
  def troubles
    @troubles ||= [
      *overdrawn_other_accounts.map { |account| Trouble.new(kind: :overdraft, subject: account) },
      *(short? ? [Trouble.new(kind: :shortfall, subject: nil)] : []),
      *trouble_lines.map { |line| Trouble.new(kind: line.over? ? :over : :overdue, subject: line) },
      *(structurally_underwater? ? [Trouble.new(kind: :structural, subject: nil)] : [])
    ]
  end

  # WHETHER THE STRIP RENDERS AT ALL. Asked once, over one list: answers-first §5 rules out a
  # permanent "Nothing needs you" box, so silence is the good state and this is the gate that
  # produces it.
  def trouble? = troubles.any?

  # A NON-MAIN ACCOUNT BELOW ZERO. Main is excluded because ITS overdraft is the hero card's red "In
  # Checking" figure with its own sentence (answers-first §2) — printing the same debt twice, with two
  # different sentences about what counts it, is worse than printing it once.
  def overdrawn_other_accounts
    overdrawn_accounts.reject { |account| main?(account) }
  end

  # ** FREE BELOW ZERO — THE SIGNAL (§4). ** Never a refusal to record anything; the strip states it,
  # names who gives way, and says what pace lands the period at zero.
  def short? = free_to_spend.negative?

  # THE SHORTFALL AS A POSITIVE FIGURE, for the sentence that states it. `-free`, exactly as
  # #overdraft_for spells the physical one.
  def shortfall = -free_to_spend

  # ** WHICH CLAIMS THE SHORTFALL EATS, IN GIVE-WAY ORDER (§4), AND THE WALK IS SPELLED ONCE. **
  #
  # THE ORDER IS `#give_way_order`'s (rules-own-the-budget spec §3): type first, then priority. The
  # walk takes each rule's claim until the shortfall is absorbed. The last claim reached is usually
  # only PARTLY uncovered, which is why this is a walk rather than a filter: "Car repair is short
  # $120" is a different sentence from "Car repair is uncovered", and only the walk can tell them
  # apart.
  #
  # ZERO CLAIMS ARE SKIPPED rather than listed as covered: a rate rule spent flat claims nothing, and
  # a row saying "$0.00 of it is uncovered" is a line that reports nothing.
  #
  # `break` RATHER THAN A `take_while`, because the boundary claim is IN the list with a REDUCED
  # amount — a filter can only decide whether the whole row belongs.
  #
  # ** IT RUNS ON `free < 0` AND NOTHING ELSE (two-shapes spec §2). ** The gate was
  # `#claims_outrun_the_money?`, because the capped `free` could go negative for a reason this walk is
  # not about — the money sitting outside checking while every claim was covered — and walking there
  # named Groceries as uncovered with the savings account holding its money two inches further down
  # the same screen. `free = pot − Σ claims` has ONE cause per sign, so `#short?` IS that predicate
  # and the second one is deleted rather than kept as a synonym.
  def uncovered_claims
    @uncovered_claims ||= begin
      remaining = short? ? shortfall : 0.to_d
      list = []
      give_way_order.each do |line|
        break unless remaining.positive?
        next unless line.claim.positive?

        taken = [line.claim, remaining].min
        list << Uncovered.new(line: line, amount: taken)
        remaining -= taken
      end
      list
    end
  end

  # ** WHAT THE SHORTFALL IS PAST EVERY CLAIM THERE IS (fix round 1 — LOW-1). ** The walk above stops
  # when it runs out of claims, so on a screen whose spending has gone further than the rules ever
  # asked for, the list sums to LESS than the headline — $900 short over a list totalling $500, with
  # nothing naming the other $400. It is the headline minus the list, by construction, so the strip's
  # figures add up to the figure above them.
  #
  # ZERO WHERE THE LIST IS EMPTY, and that is a refusal rather than an arithmetic accident: with no
  # claims walked there is no "past everything the rules claim" to say — the two arms that reach that
  # state (nothing claimed at all, and the money sitting in another account) are already carrying the
  # sentence that names their own cause.
  def uncovered_remainder
    return 0.to_d if uncovered_claims.empty?

    shortfall - uncovered_claims.sum(0.to_d, &:amount)
  end

  # ** THE PACE THAT LANDS THE PERIOD AT ZERO (§4): `shortfall ÷ days left`. ** No new date
  # arithmetic — `days left` is `Progress#days_left`, off `User#period_containing`, the one reader
  # that owns this calendar and the same one the hero's bar and this section's heading print.
  #
  # NIL FOR A USER WHO HAS DECLARED NO PERIOD, because there is no "rest of the period" to spread a
  # shortfall over and inventing a calendar month would state a boundary nobody set — the same
  # refusal `#period_range` makes.
  #
  # THE DIVISOR IS FLOORED AT ONE, and the floor is the CLOSING DAY rather than a guard against a
  # bad number: `days_left` is `days - day` on a 1-based inclusive day, so it is ZERO on the last day
  # of the period — the user still has today, and today is the whole of what is left. Dividing by
  # zero there would raise on the one afternoon the sentence matters most.
  def per_day_pace
    progress = period_progress
    return nil if progress.nil? || !short?

    (shortfall / [progress.days_left, 1].max).round(2)
  end

  # ── THE ACCOUNTS, DEMOTED TO ONE LINE (answers-first §6) ───────────────────────────────────────

  # WHAT THE LINE IS ABOUT: the accounts that are neither main nor mid-onboarding. Main is out because
  # its balance IS the hero's "In Checking" figure, and counting it here would answer one question
  # twice with two different numbers; an onboarding account is out because its card is rendered
  # top-level and a figure in the line for a card sitting above it reads as two accounts.
  def other_accounts = accounts.reject { |account| main?(account) || onboarding?(account) }

  def other_accounts_total = other_accounts.sum(0.to_d) { |account| balance_of(account) }

  # THE CARDS THE LINE HIDES, which is every account whose onboarding is finished — MAIN INCLUDED.
  # The line's FIGURE is about the others; the expansion is the accounts INDEX, and Home carries
  # rename and delete since `pools/index` and `pools/show` were deleted.
  def collapsed_accounts = accounts.reject { |account| onboarding?(account) }

  # STILL UNFINISHED, so the card surfaces top-level (answers-first §6). Both gates asked through the
  # presenter's own predicates rather than re-spelled, because each is ALSO the gate a controller
  # checks before accepting the write the card submits.
  def onboarding_accounts = accounts.select { |account| onboarding?(account) }

  def onboarding?(account) = awaiting_funding?(account) || awaiting_opening_balance?(account)

  # ── THE PERIOD, AND THE STRUCTURAL VERDICT ─────────────────────────────────────────────────────

  # WHICH PERIOD THE SCREEN IS TALKING ABOUT, or nil for a user who has declared none.
  #
  # `User#period_containing`, the one method that owns this arithmetic. GATED ON THE DECLARATION
  # rather than taken on trust: `period_containing` falls back to the calendar month for an undeclared
  # user, which is the right fallback for a normaliser and a lie on this card, since "Aug 1 – Aug 31"
  # would state a boundary the user never set.
  # MEMOISED WITH `defined?` RATHER THAN `||=`, because the nil arm is a real answer and the common
  # one for an undeclared user — `||=` would re-walk the boundaries for every row on the screen for
  # exactly the users who have none. `#claim_line_for` asks this once per rule now (`#due_this_period?`).
  def period_range
    return @period_range if defined?(@period_range)

    @period_range =
      if user.period_cadence.blank? || user.period_anchor_date.blank?
        nil
      else
        user.period_containing(today)
      end
  end

  # ** THE ORDER CLAIMS GIVE WAY IN (rules-own-the-budget spec §3), AND IT IS ONE SORT OVER EVERY
  # CLAIM LINE. ** It was `budgeted_categories.reverse.flat_map { … }` — a category-level walk that
  # could only rank whole categories against each other — and the type is a fact about a RULE: one
  # category may carry a bill beside a choice, and under the old walk both gave way together at
  # whatever rank their category held. Every line is now ranked individually, on one key:
  #
  #   1. `Budget#type_rank` — `{ choice: 0, usage: 1, bill: 2 }`, spelled once on the model (§3).
  #      Discretionary money goes first and a must-pay is the last thing reached, which is the whole
  #      point of giving rules a type. It DECIDES BEFORE PRIORITY DOES, which closes §3's open
  #      question about intra-category order: a restaurant rule on a high-priority category gives way
  #      before the rent does.
  #   2. THE CATEGORY, IN REVERSE FILL ORDER — `#budgeted_categories` read backwards, which is
  #      `[priority, name]` reversed and is exactly what the old walk did. The category that would
  #      have been funded LAST is the one that goes without first, so a HIGHER priority number gives
  #      way sooner; a tie on priority breaks on the later NAME. Both are unchanged, and both are
  #      taken as an INDEX into the list this screen already sorted rather than re-spelled here —
  #      `Category.in_fill_order`'s key exists in one place and a second copy of it could rank the
  #      trouble strip differently from the section below it.
  #   3. `Category.rule_order` — the app's one within-category key (see #claim_lines), so two rules
  #      of one type on one category give way in the order the rows are printed in.
  #
  # PUBLIC, because it is a produced interface of this plan and because `#uncovered_claims` is not
  # the only honest reader of it: the order is a fact about the screen, and a spec that had to reach
  # it through `send` would be pinning a private accident.
  def give_way_order
    @give_way_order ||= claim_lines.values.flatten.sort_by { |line| give_way_key(line) }
  end

  # DOES THE BUDGET FIT THE INCOME — a question about the SHAPE of the rules, not about this
  # afternoon's cash, and the one kind of trouble no amount of care this period can fix.
  #
  # `Budget.steady_need` reads the rules and the calendar and NOTHING ELSE — no spending, no
  # adjustment, no fund state (`ClaimCalculator#standing_ask`, fix wave 2 — MED-A). It is deliberately
  # not `Σ claims`, which is THIS period's answer (catch-up on anything behind, zero on anything
  # already full) and diverges from the structural question in both directions on the same budget:
  # for one wave the one-off branch read exactly that figure, and this verdict then appeared on an
  # unpaid $600 bill and vanished when the bill was paid, with no rule changed.
  #
  # BOTH HALVES OF THE DECLARATION, income AND cadence — the same gate `BudgetPagePresenter#declared?`
  # applies, because it is the same question.
  #
  # Memoised, and the `false` case has to be memoised too — `||=` would recompute the whole sum on
  # every call for exactly the users who answer false.
  def structurally_underwater?
    return @structurally_underwater if defined?(@structurally_underwater)

    @structurally_underwater =
      user.typical_income.present? &&
      user.period_cadence.present? &&
      Budget.steady_need(user, today: today, ledger: claim_ledger) > user.typical_income.to_d
  end

  private

  # ── THE RUNWAY'S TICKS ─────────────────────────────────────────────────────────────────────────

  def build_runway
    progress = period_progress
    return nil if progress.nil?

    ticks = runway_ticks(progress)
    Runway.new(
      progress: progress,
      ticks: ticks,
      due_total: ticks.sum(0.to_d, &:amount),
      short: ticks.select(&:short?)
    )
  end

  # IN DATE ORDER, because the ruler is: two ticks out of order would be two labels crossing their
  # own marks. The name breaks a tie so two bills on one day rank the same way on every load.
  #
  # THE LABEL IS THE ITEM'S NAME OR THE CATEGORY'S — never `ClaimLine#name`'s "Whole category", which
  # is a phrase about a LANE and reads as nonsense on a mark saying what is due ("$1,200 Whole
  # category"). §3: "labelled amount + rule name (item name or category)".
  def runway_ticks(progress)
    claim_lines.values.flatten
      .select { |line| line.dated? && line.due_this_period }
      .sort_by { |line| [line.next_due_on, line.name] }
      .map { |line| runway_tick(line, progress) }
  end

  def runway_tick(line, progress)
    day_index = (line.next_due_on - progress.first).to_i + 1

    RunwayTick.new(
      line: line,
      day_index: day_index,
      percent: progress.percent_at(day_index),
      label: line.rule.item&.name || line.category.name,
      amount: line.target,
      state: line.fund_short? ? :short : :ready,
      gap: line.fund_gap
    )
  end

  # ── THE TWO HALVES OF "A CATEGORY WITH NO RULE, AND SPENDING" ──────────────────────────────────

  # A HOLDER THAT WAS FUNDED AND NEVER GIVEN A RULE. It costs no query: `#categories` eager-loads
  # `:budgets`, which is what `Category#budgeted?` reads, and its spending is in the grouped sum
  # `#holder_spending_this_period` has already run for the blocks.
  #
  # `#categories` RATHER THAN `#budgeted_categories`: the extra half of that list is the categories
  # the RULES name, every one of which owns a rule by construction and is therefore never here — and
  # asking `budgeted?` of one would load its rules a second time, one statement per category.
  def unruled_holder_rows
    unruled_holders.filter_map do |category|
      spent = spent_this_period(category)
      UnbudgetedRow.new(category: category, spent: spent) if spent.positive?
    end
  end

  # THE HOLDERS WITH NO RULE, MEMOISED — it is the population of the row above AND the population the
  # grouped spending query below asks about, and computing it twice is how the two come to disagree
  # about which categories the sum covers.
  def unruled_holders = @unruled_holders ||= categories.reject(&:budgeted?)

  # A CATEGORY NOBODY EVER FUNDED, whose receipts drain no category at all.
  def unfunded_category_rows
    spending = unbudgeted_spending_this_period
    return [] if spending.empty?

    user.categories.expenses.where(id: spending.keys).order(:name)
      .map { |category| UnbudgetedRow.new(category: category, spent: spending.fetch(category.id)) }
  end

  # EVERY RULE'S CLAIM, BY CATEGORY, OFF THE PAGE'S ONE LEDGER. Built once for the whole screen: the
  # "This period" rows, the trouble strip's over/overdue triggers and the shortfall's give-way walk
  # are three readings of ONE list, and three lists would be three chances for the strip to name a
  # category the section below it describes differently.
  def claim_lines_for(category) = claim_lines.fetch(category.id, [])

  # ** `Category.rule_order`, WHICH IS THE APP'S ONE KEY SINCE THE FIX WAVE (LOW-3). ** This sorted
  # by `[item name, id]` — the catch-all first, then the items by name — on the argument that the
  # item-less rule is the category's own envelope and the item-backed ones are exceptions carved out
  # of it (§3.1's lane partition). The Budget page's group and the category card both sorted the SAME
  # category's rules by the date the row prints, so one category read one way here and another way
  # two clicks along. The date key won: it orders on a fact the reader can see, and it was already
  # two screens' answer against this one's. See `Category.rule_order` for the whole argument.
  #
  # THE LINES ARE BUILT BEFORE THEY ARE SORTED, because the key reads `next_due_on` — which is the
  # CLAIM's reading of the schedule and not a column. It costs nothing extra: the calculators are the
  # ledger's own and the map ran either way.
  def claim_lines
    @claim_lines ||= claim_ledger.rules
      .map { |rule| claim_line_for(rule) }
      .sort_by { |line| Category.rule_order(next_due_on: line.next_due_on, amount: line.rule.amount, id: line.rule.id) }
      .group_by { |line| line.category.id }
  end

  def claim_line_for(rule)
    calculator = claim_ledger.calculator_for(rule)

    ClaimLine.new(
      category: rule.category,
      rule: rule,
      shape: calculator.shape,
      claim: calculator.claim,
      spent: calculator.spent_this_period,
      accrued: calculator.accrued_this_period,
      built_up: calculator.built_up,
      target: calculator.target,
      next_due_on: calculator.next_due_on,
      per_period: calculator.planned_this_period,
      over: calculator.over?,
      over_by: calculator.over_by,
      overdue: calculator.overdue?,
      due_this_period: due_this_period?(calculator.next_due_on),
      resets_on: calculator.rate? ? next_period_opens_on : nil
    )
  end

  # ** THE DAY A RATE RULE STARTS AGAIN (§3: "resets Oct 1"). ** Use-it-or-lose-it is reset at every
  # boundary (§3.1), so the day is the one after this period's close — `#period_range`'s own last
  # day, never a second calendar. Nil for a dated rule (nothing resets; it has a due date instead)
  # and for a user who has declared no period, where the row simply says one clause fewer.
  #
  # A MEMBER ON THE LINE RATHER THAN AN ARGUMENT TO `HomeHelper#when_words`: that helper is one
  # spelling for Home's blocks and Task 3's Budget rows, and a signature carrying the period would
  # make every caller supply a calendar the row object already knows.
  def next_period_opens_on = period_range.nil? ? nil : period_range.last + 1

  # ** IS THE DAY THIS RULE'S MONEY IS NEEDED ON INSIDE THE PERIOD ON THE SCREEN? ** A MEMBER RATHER
  # THAN A DERIVATION, for `ClaimLine#overdue?`'s own reason: the comparison is against the
  # presenter's window, and a Data object computing it would have to reach for a calendar of its own
  # — which is the one thing every reader on this screen is built to avoid.
  #
  # `#period_range` IS THE WINDOW, so this is `User#period_containing` and nothing else; nil for a
  # user who has declared no period, where the honest answer is false rather than a month nobody set.
  def due_this_period?(due) = due.present? && period_range.present? && period_range.cover?(due)

  # THE LINES THE STRIP IS ABOUT, in the order the section lists their categories, so a reader
  # scanning down the strip and then down the section meets the same categories in the same order.
  def trouble_lines
    @trouble_lines ||= budgeted_categories.flat_map { |category| claim_lines_for(category) }.select(&:trouble?)
  end

  # ONE LINE'S PLACE IN THE GIVE-WAY ORDER. See #give_way_order for what each term is and why.
  def give_way_key(line)
    [
      line.rule.type_rank,
      give_way_rank.fetch(line.category.id),
      Category.rule_order(next_due_on: line.next_due_on, amount: line.rule.amount, id: line.rule.id)
    ]
  end

  # ** THE CATEGORY HALF OF THE KEY: `#budgeted_categories` READ BACKWARDS, AS AN INDEX. ** The
  # negated position in a list already sorted `[priority, name]`, so the reverse-fill order arrives
  # as one comparable number and `Category.in_fill_order`'s key is not written out a second time.
  # Every line's category is in that list by construction — it is `categories + the rules' own
  # categories` — so `fetch` is a claim rather than a lookup with a default.
  def give_way_rank
    @give_way_rank ||= budgeted_categories.each_with_index.to_h { |category, index| [category.id, -index] }
  end

  def spent_this_period(category) = holder_spending_this_period.fetch(category.id, 0.to_d)

  # ** WHAT EACH RULE-LESS HOLDER SPENT INSIDE THIS PERIOD, IN ONE GROUPED QUERY — AND NO NEW DATE
  # ARITHMETIC ANYWHERE IN IT. **
  #
  # ** IT COVERED EVERY BUDGETED CATEGORY UNTIL THIS TASK, AND ITS POPULATION SHRANK WITH
  # `#period_rows` (two-shapes §3). ** That reader printed a per-CATEGORY spending figure for every
  # row on the screen; the section is per-RULE now, and a rule's own lane spending comes off its
  # `ClaimCalculator` (the ledger's two batched lanes, which partition — §3.1). So the ONE reader
  # left is `#unruled_holder_rows`, whose categories have no rule and therefore no lane, and the
  # query asks about exactly those: a holder with rules is answered by the ledger, and asking about
  # it here as well would be summing the same receipts twice for nobody.
  #
  # THE CONSEQUENCE IS ONE STATEMENT FEWER ON MOST SCREENS, and it is pinned rather than noticed:
  # `home_presenter_spec`'s cost block counts fourteen for an ordinary render and fifteen when a
  # rule-less holder has spending, which is the only shape that needs this sum at all.
  #
  # Two shared readers, composed, and neither is re-spelled here:
  #
  #   WHICH CATEGORY AN EXPENSE DRAINS — `CategoryLedger::ENTRY_CATEGORY_ID`, the app's ONE statement
  #     of that rule (funded-since gate and the owner's-day timezone boundary included). It is the
  #     same expression `ClaimLedger`'s own lanes group by, so this figure and a claim's
  #     `spent_this_period` cannot count different rows.
  #   WHERE THE PERIOD STARTS AND ENDS — `User#period_datetimes_containing`, the app's ONE reader of
  #     that, with the widening to the closing day's own midnight that `entries.date` being a DATETIME
  #     requires.
  #
  # THE WINDOW IS TAKEN UNGATED, unlike `#period_range`: nothing here prints a boundary, and a month
  # is the same fallback `Budget#steady_ask` normalises an undeclared user's rules against.
  #
  # `unruled_holders.empty?` GUARDED because that is the ordinary screen — a user whose categories
  # all carry rules — and an `IN ()` list is a query with nothing to ask.
  def holder_spending_this_period
    @holder_spending_this_period ||=
      if unruled_holders.empty?
        {}
      else
        period_entries
          .where("#{CategoryLedger::ENTRY_CATEGORY_ID} IN (:ids)", ids: unruled_holders.map(&:id))
          .group(CategoryLedger::ENTRY_CATEGORY_ID).sum(:amount).transform_values(&:to_d)
      end
  end

  # THE SAME PARTITION, READ FOR ITS OTHER ANSWER: spending inside this period that drains no category
  # at all, split by the category that NAMES the entry. Together the two queries cover every expense
  # entry in the window exactly once.
  #
  # BUDGETED CATEGORIES ARE REJECTED AFTERWARD RATHER THAN IN SQL, and the reject is load-bearing
  # rather than defensive: a category funded PART-WAY THROUGH this period drains nothing for the
  # receipts dated before its `funded_since` and itself for the ones after, so without this it would
  # be listed twice — once with a bar and once as unbudgeted.
  def unbudgeted_spending_this_period
    @unbudgeted_spending_this_period ||= begin
      budgeted = budgeted_categories.to_set(&:id)

      period_entries.where("#{CategoryLedger::ENTRY_CATEGORY_ID} IS NULL")
        .group("categories.id").sum(:amount)
        .except(*budgeted)
        .transform_values(&:to_d)
    end
  end

  # THE SCOPE BOTH GROUPED READS START FROM. `Entry.expenses` already carries the `item: :category`
  # join both the constant and the `categories.user_id` filter need; `ENTRY_CATEGORY_JOINS` brings the
  # aliased owner whose timezone the constant's day-boundary comparison re-zones through.
  def period_entries
    Entry.expenses
      .joins(*CategoryLedger::ENTRY_CATEGORY_JOINS)
      .where(categories: { user_id: user.id }, date: user.period_datetimes_containing(today))
  end

  # ** ONE CLAIM LEDGER FOR THE WHOLE RENDER (§3.3). ** Three statements for the user's entire rule
  # set, where a calculator per rule would be two per rule and a walk each. Every claim figure on this
  # screen — the hero's `free`, each row's bar, each trouble line, the give-way walk — comes out of
  # this one object, so the strip cannot name a category the section describes differently.
  #
  # LAZY, like everything else here: Home writes nothing, so there is no write for the snapshot to
  # fall the wrong side of, and the laziness only keeps a presenter built and never rendered free.
  #
  # PINNED, not asserted: `home_presenter_spec`'s cost block counts the statements a five-rule screen
  # costs against a one-rule one, because a reader that quietly grew a ledger of its own is invisible
  # to every other example in the file.
  def claim_ledger = @claim_ledger ||= ClaimLedger.new(user, today: today)

  # ONE PHYSICAL LEDGER FOR THE SCREEN, and it is the CLAIM LEDGER'S OWN — the accounts band, the
  # overdraft lines, the onboarding gates and `free`'s cap all read one snapshot. A second
  # `AccountLedger` here would be a second reading of the same two SUMs, free to disagree with the
  # pot the hero prints.
  def account_ledger = claim_ledger.account_ledger

  # THE LATCH ITSELF, memoised: #awaiting_opening_balance? is asked once per account this screen
  # renders, and every account but main gets a `false` from the first half of that predicate before
  # this one is ever reached.
  #
  # `Category.opening_balance`, NOT a hand-rolled `exists?(name: …)`: that scope is CASE-INSENSITIVE,
  # matching `Category`'s own uniqueness validation, so a user who already has a category spelled
  # "opening balance" reads as latched here exactly as it would refuse a second `create!`.
  #
  # `defined?` rather than `||=`: the open latch is `false`, the common case for as long as onboarding
  # is unfinished, and `||=` would re-run the EXISTS on every hit.
  def opening_balance_recorded?
    return @opening_balance_recorded if defined?(@opening_balance_recorded)

    @opening_balance_recorded = user.categories.opening_balance.exists?
  end
end
