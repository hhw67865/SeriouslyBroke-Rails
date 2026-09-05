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
    :overdue
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
    def percent
      return 0 unless bar?

      ((filled / denominator) * 100).round.clamp(0, 100)
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
  PeriodRow = Data.define(:category, :lines, :spent) do
    # `Category#budgeted?`, WHICH IS THE APP'S ONE SPELLING OF IT SINCE FIX ROUND 1 (M2). This was
    # `lines.any?` — the same question asked of the rules this screen happened to have loaded — and
    # the entry form's impact card asked a THIRD thing (`holding.nil?`, which is about the funding
    # DATE) and drew a funded, ruleless category a red overdrawn envelope while this row called it
    # unbudgeted. One predicate, on the model, so the two screens cannot part company again.
    #
    # The two are the same set by construction (`#claim_lines` groups `ClaimLedger#rules`, which is
    # `Budget.for_user`) and it costs no query: `#categories` eager-loads `:budgets`.
    delegate :budgeted?, to: :category

    def needs_attention? = lines.any?(&:trouble?)

    # NOTHING TO SAY AT ALL: a holder with no rule that nobody has spent from this period. The
    # budgeted side of answers-first §4's rule that a zero-spend unbudgeted category is absent from
    # Home, for the same reason — `spent $0.00` under a name costs a line and reports nothing.
    def silent? = !budgeted? && spent.zero?
  end

  # AN EXPENSE CATEGORY NOBODY BUDGETED, WITH SPENDING INSIDE THIS PERIOD: the fact, and no bar
  # (answers-first §4). There is nothing for a bar to be a fraction of — no rule claims this money —
  # so a denominator here would be inventing the pressure rather than reporting it.
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

    def percent = ((day.to_f / days) * 100).round.clamp(0, 100)
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

  # ── "THIS PERIOD" — SPENDING AS PROGRESS (answers-first §4, computed-claims §3.4) ──────────────

  # THE BUDGETED ROWS, TROUBLE FIRST AND THEN PRIORITY (answers-first §4).
  #
  # `sort_by` IS NOT STABLE IN RUBY, so the index is part of the key rather than left to chance:
  # #budgeted_categories is already `[priority, name]`, and without the tiebreak two quiet categories
  # could swap places between page loads with no data change.
  def period_rows
    @period_rows ||= budgeted_categories.each_with_index
      .map { |category, index| [period_row_for(category), index] }
      .sort_by { |row, index| [row.needs_attention? ? 0 : 1, index] }
      .map(&:first)
      .reject(&:silent?)
  end

  # THE UNBUDGETED ROWS: an expense category nobody has given a rule, WITH spending inside this period
  # (answers-first §4). Zero-spend ones are absent by construction — they never appear in the grouped
  # sum — which is the rule stated as a query rather than as a filter somebody could forget.
  #
  # ORDERED BY NAME, not by amount: these rows carry no plan and therefore no ranking, and sorting
  # money the app is not asking the user to do anything about would imply one.
  def unbudgeted_rows
    @unbudgeted_rows ||= begin
      spending = unbudgeted_spending_this_period
      if spending.empty?
        []
      else
        user.categories.expenses.where(id: spending.keys).order(:name)
          .map { |category| UnbudgetedRow.new(category: category, spent: spending.fetch(category.id)) }
      end
    end
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
  def period_range
    return nil if user.period_cadence.blank? || user.period_anchor_date.blank?

    user.period_containing(today)
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

  # ── WHAT ONE "THIS PERIOD" ROW IS MADE OF ──────────────────────────────────────────────────────

  def period_row_for(category)
    PeriodRow.new(
      category: category,
      lines: claim_lines_for(category),
      spent: spent_this_period(category)
    )
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
      overdue: calculator.overdue?
    )
  end

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

  # ** WHAT EACH BUDGETED CATEGORY SPENT INSIDE THIS PERIOD, IN ONE GROUPED QUERY — AND NO NEW DATE
  # ARITHMETIC ANYWHERE IN IT. ** Two shared readers, composed, and neither is re-spelled here:
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
  # `budgeted_categories.empty?` GUARDED because the set is empty for every user on their first day,
  # and an `IN ()` list is a query with nothing to ask.
  def holder_spending_this_period
    @holder_spending_this_period ||=
      if budgeted_categories.empty?
        {}
      else
        period_entries
          .where("#{CategoryLedger::ENTRY_CATEGORY_ID} IN (:ids)", ids: budgeted_categories.map(&:id))
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
