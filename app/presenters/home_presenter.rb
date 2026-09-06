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
  # ** `ClaimLine`, `CategoryBlock`, `#claim_lines`, `#give_way_key` AND `#give_way_rank` ARE HOISTED
  # TO `ClaimRows` (this task). ** The Budget page's list is the same give-way order under a
  # different header (two-shapes spec §4) and the categories card is one category's slice of it, so
  # leaving the row type and the sort here meant either a second sort — the very defect
  # `ClaimRows#blocks` records — or two other screens reaching into this class's privates. Home
  # reads them through `#claim_rows` and every figure below is unchanged.

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

  # `rejected_opening:` IS THE "YOUR ACCOUNTS" CARD'S OWN 422 (account-openings spec §3), threaded
  # through rather than read off an ivar the view would have to know about. `AccountOpeningsController`
  # (and `BankAccountsController`, for the add row) hands back the refused `AccountOpening`, and
  # #rejected_opening_for is how the ONE row it was for gets it back — every other row renders blank.
  #
  # IT WAS `rejected_movement:`, onboarding step 2's AccountMovement, and the object changed with the
  # question: nothing on this screen asks the user about a movement any more.
  def initialize(user:, today: user.today, rejected_opening: nil)
    @user = user
    @today = today
    @rejected_opening = rejected_opening
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

  # ** ONBOARDING'S ONE GATE (account-openings spec §3): has this account said what it holds? **
  #
  # IT REPLACES TWO — `#awaiting_funding?` (step 2: "not main, and holding no money yet") and
  # `#awaiting_opening_balance?` (step 3: "is main, and the one-time latch is open") — and the
  # collapse is the whole point of the spec: the app asks one question per account now, and every
  # account answers it the same way, main included.
  #
  # `pools.opened_on`, NOT A BALANCE AND NOT A CATEGORY'S EXISTENCE. A balance-based gate could not
  # tell an account that holds nothing from one that has never been asked, and $0.00 is a real
  # answer to "what's in it right now". The old latch (`Category.opening_balance.exists?`) was one
  # fact for the whole USER, which cannot say anything about a particular account.
  def awaiting_opening?(account) = account.opened_on.nil?

  # IS THE USER STILL SETTING UP? Any account that has not said what it holds. Onboarding is complete
  # when the last one has (§3), and a user with no accounts at all is not "finished" — they are at
  # the add-account row, which is the same card.
  def onboarding? = accounts.empty? || accounts.any? { |account| awaiting_opening?(account) }

  # IS THIS THE ACCOUNT EVERYTHING FLOWS THROUGH? The view's gate on the Delete button, and it is
  # `Pool#main?` rather than a comparison of this screen's own: the model REFUSES the destroy on
  # exactly that predicate, so a differently-spelled question here could offer a button the server
  # then rejects — or hide one it would have accepted.
  def main?(account) = account.main?

  # THE REFUSED SAVE, IF THIS IS THE ROW IT WAS FOR — so the typed figure and the sentence that
  # refused it survive the re-render, exactly as the add-account row's name does. nil everywhere
  # else, which is every row on an ordinary render.
  def rejected_opening_for(account)
    return @rejected_opening if @rejected_opening&.account&.id == account.id

    nil
  end

  # WHAT THE "EDIT BALANCE" ROW OPENS ON: today's balance, which is the figure the user is being
  # asked to confirm or correct. `AccountLedger#balance_of` through the screen's one ledger — the
  # same snapshot the card's own "balance now" line prints, so the field and the sentence above it
  # cannot disagree.
  def balance_field_for(account)
    rejected = rejected_opening_for(account)
    return rejected.typed if rejected

    # `format` RATHER THAN THE BARE BigDecimal (measured in the browser): `650.0.to_s` puts "650.0"
    # in a money field, which reads as a figure the app half-knows. Two decimal places is the only
    # unit this app has anywhere else.
    format("%.2f", balance_of(account))
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

  # EVERY CATEGORY WITH A ROW ON THIS SCREEN — the holders, PLUS any category carrying a rule that
  # is not one (`funded_since` cleared after the fact). `ClaimRows#ranked_categories`, which is where
  # the give-way rank reads it: one list, so the strip and the section cannot rank a category two
  # ways. It takes THIS class's `#categories` (eager-loaded `:budgets`, which `#unruled_holders`
  # reads) rather than loading a second copy.
  delegate :ranked_categories, to: :claim_rows
  alias budgeted_categories ranked_categories

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

  # ** ONE BLOCK PER CATEGORY, IN GIVE-WAY ORDER (§3) — `ClaimRows#blocks`. ** The sort, the
  # grouping and the row type all live there now (this task), because the Budget page renders the
  # same list under a different header and a second grouping is how two screens come to rank one
  # category two ways.
  delegate :blocks, to: :claim_rows
  alias category_blocks blocks

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
  def other_accounts = accounts.reject { |account| main?(account) || awaiting_opening?(account) }

  def other_accounts_total = other_accounts.sum(0.to_d) { |account| balance_of(account) }

  # THE CARDS THE LINE HIDES, which is every account whose onboarding is finished — MAIN INCLUDED.
  # The line's FIGURE is about the others; the expansion is the accounts INDEX, and Home carries
  # rename and delete since `pools/index` and `pools/show` were deleted.
  def collapsed_accounts = accounts.reject { |account| awaiting_opening?(account) }

  # STILL UNFINISHED, so it gets a ROW in the "Your accounts" card rather than a card of its own
  # (§3). The gate is asked through the presenter's own predicate rather than re-spelled, because it
  # is ALSO the gate that decides whether the account's finished card renders in the expander.
  def onboarding_accounts = accounts.select { |account| awaiting_opening?(account) }

  # ── THE PERIOD, AND THE STRUCTURAL VERDICT ─────────────────────────────────────────────────────

  # WHICH PERIOD THE SCREEN IS TALKING ABOUT, or nil for a user who has declared none —
  # `ClaimRows#period_range`, which is where the rows' own `resets_on` and `due_this_period` are read
  # against it, so the heading and the rows cannot be talking about two fortnights.
  delegate :period_range, to: :claim_rows

  # ** THE ORDER CLAIMS GIVE WAY IN (rules-own-the-budget spec §3) — `ClaimRows#give_way_order`. **
  # PUBLIC, because it is a produced interface of this plan and `#uncovered_claims` is not its only
  # honest reader: the order is a fact about the screen, and a spec that had to reach it through
  # `send` would be pinning a private accident.
  delegate :give_way_order, to: :claim_rows

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
  #
  # ** A PAID ONE-OFF DRAWS NO TICK (this task's carry (a)). ** Its occurrence never rolls, so its
  # `next_due_on` sits inside this period for ever after it has been paid — and the tick it drew was
  # RED, because paying the bill empties the fund and `#fund_short?` read the emptiness as a
  # shortfall. It also counted its whole amount into `#due_total`, so the pace line told the user
  # money was still due on a bill they had already paid. `ClaimLine#paid?` is the one reading of the
  # fulfilment; the row beside the rail says "paid <date>" in its place.
  def runway_ticks(progress)
    give_way_order
      .select { |line| line.dated? && line.due_this_period && !line.paid? }
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

  # ** THE LINES THE STRIP IS ABOUT, WALKED IN THE ORDER THE BLOCKS BELOW ARE DRAWN IN — ONE SORT
  # ON THE SCREEN (fix wave — MED-1). **
  #
  # It walked `#budgeted_categories` (`ClaimRows#ranked_categories`, which is `[priority, name]` —
  # FILL order) and flat-mapped each category's lines, while every block under it is
  # `#give_way_order` grouped back. Those are two different orders and the difference is visible on
  # the ordinary case: Rent (a `bill` on a priority-0 category) overdue beside Fun (a `choice` on
  # priority 1) over listed Rent first in the strip and Fun first in the section, so a reader
  # scanning down the strip and then down the section met the same two categories ranked opposite
  # ways — the very defect `ClaimRows` was hoisted to end, back in a third reader.
  #
  # `#category_blocks` RATHER THAN `#give_way_order` DIRECTLY, so the strip is grouped exactly as
  # the section is: a category's troubled rules arrive together, at the position its first-giving-way
  # rule puts the block. Flattening the blocks and flattening the walk differ only where one
  # category's rules straddle another's in the give-way order, and there the section is what a
  # reader is looking at.
  def trouble_lines
    @trouble_lines ||= category_blocks.flat_map(&:rows).select(&:trouble?)
  end

  # ** `#give_way_key` AND `#give_way_rank` LEFT WITH THE SORT (`ClaimRows`). ** The key is the
  # order's definition and the order is now read by three screens; a copy here would be a second
  # definition free to disagree with the list it ranks.

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

  # ** THE ROWS, THE ORDER AND THE BLOCKS — ONE OBJECT, SHARED WITH THE BUDGET PAGE AND THE
  # CATEGORIES CARD (this task). ** It queries nothing: the calculators are the ledger's, the period
  # grid is `User#period_containing`, and `categories:` is the list this class already loaded (with
  # its `:budgets` preload, which `#unruled_holders` reads). Handing that list in rather than letting
  # `ClaimRows` load its own is what keeps the screen's statement count where the cost pin puts it.
  def claim_rows
    @claim_rows ||= ClaimRows.new(ledger: claim_ledger, today: today, categories: categories)
  end

  # ONE PHYSICAL LEDGER FOR THE SCREEN, and it is the CLAIM LEDGER'S OWN — the accounts band, the
  # overdraft lines, the onboarding gates and `free`'s cap all read one snapshot. A second
  # `AccountLedger` here would be a second reading of the same two SUMs, free to disagree with the
  # pot the hero prints.
  def account_ledger = claim_ledger.account_ledger

  # ** THE LATCH READER IS GONE (account-openings spec §3). ** `#opening_balance_recorded?` ran
  # `Category.opening_balance.exists?` — ONE fact for the whole user, which was the right shape while
  # onboarding's last step was a single main correction and is the wrong shape for a question asked
  # once per account. `#awaiting_opening?` reads `pools.opened_on` off a row this screen has already
  # loaded, which is also why the render's statement count fell by one.
end
