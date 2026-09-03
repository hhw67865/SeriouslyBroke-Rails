# frozen_string_literal: true

# Everything the Home screen renders — BOTH LEDGERS OVER ONE TOTAL (two-ledger spec §2). Read-only:
# it builds no movements, writes no allocations and saves nothing; the fix buttons below are LINKS
# to the reallocation screen, which owns the write.
#
#   THE PHYSICAL BAND  — the accounts, each showing what the bank says. `AccountLedger#balance_of`,
#                        and main's balance IS the pot. Accounts no longer contain anything: the
#                        `pools_for(account)` nesting, the orphan band and the whole apparatus that
#                        went with them are deleted (Task 6).
#   THE PURPOSE BAND   — AVAILABLE and the holder categories that hold the rest. `CategoryLedger`,
#                        `Category.in_fill_order`, and ONE waterfall over ONE root.
#
# WHAT THE COLLAPSE FROM PER-ACCOUNT TO ONE ROOT ACTUALLY DELETED, said here because five readers
# on this class existed only to carry it: `#account_pots`, `#sweeps_by_account`, `#fill_waterfall`'s
# per-account pot map, `#cutoff`'s `accounts.one?` gate and `#projected_buffer`'s "cash in an account
# with nothing left to fund" reading. Allocating money is an act of intention rather than of location
# (§2), so there is no account for money to be stranded in and no second reason the standing band's
# figures fail to subtract. #shortfall and `remaining_plan - available` agreed wherever available was
# non-negative — and BOTH `#cutoff` and `#shortfall` are themselves deleted now (answers-first Task
# 2), with the waterfall band that was their only caller. Their marker sits beside `#waterfall`,
# which is the reader that survived.
#
# THE HERO CARD REPLACED THE STANDING BAND (answers-first spec §§2-3), and with it went the last of
# that machinery: `#projected_buffer` is deleted and `#total_required` is `#remaining_plan`. Home
# stops describing the system and answers "how much is in checking, how much of it is free, where
# are we in the period" — see #in_checking, #free_to_spend and #period_progress below, all three
# composed from readers this class already had.
#
# See docs/superpowers/specs/2026-08-21-two-ledger-design.md §2,
# docs/superpowers/specs/2026-08-15-budgeting-ui-design.md §4 and
# docs/superpowers/specs/2026-09-02-answers-first-home-design.md §§2-3
class HomePresenter
  # WHAT ONE PROBLEM ROW OFFERS TO DO ABOUT ITSELF (spec §4.2): the amount to move, the source that
  # can genuinely cover it, and what the move would cost the source.
  #
  # `candidate` is a ReallocationPresenter::Candidate, not a shape of our own — the same object, from
  # the same class, that the screen this button opens will render half a second later. "What would
  # this move cost" has one answer, and Home prints it through the same `AllocationsHelper` sentence
  # `/allocations/new` prints. Two readers answering one question has produced a defect in every task
  # on this plan.
  #
  # nil `candidate` is the no-fix case and is REACHABLE — see #fix_candidates_for. The view says so
  # in words rather than rendering a dead button.
  Fix = Data.define(:category, :amount, :candidate, :covered) do
    # THE CANDIDATE ITSELF, not a record inside it: a source may be AVAILABLE, which is not a
    # category at all (ReallocationPresenter::ROOT). Both answer #id and #name, which is the whole
    # reason the root is a null object rather than a `nil`.
    def source = candidate

    # The next distribution funds this category's whole ask, so there is nothing for a move to do.
    # See HomePresenter#covered_by_waterfall?.
    def covered? = covered

    # WHETHER MOVING MONEY IN WOULD CHANGE ANYTHING, and it is a real branch rather than a guard.
    # `amount` is HoldingStatus#funding_gap, which is zero for an overdue bill whose category already
    # holds the money — the demo's Renters Insurance. That category needs paying, not funding, and
    # the view says so instead of offering a button that would double-fund it.
    def needs_money? = amount.positive?

    # PLAIN DIGITS FOR THE QUERY STRING. `number_to_rounded` scales to two decimals and is asked for
    # `delimiter: ""`, so a four-figure amount cannot reach `?amount=` as "1,500.00" — which the
    # browser would read as one dollar fifty. `DigitsHelper.digits` is the one spelling of "money a
    # browser can parse" on this branch; four copies of it is four chances to leave the delimiter in.
    def amount_param = DigitsHelper.digits(amount)
  end

  # ONE BUDGETED CATEGORY AS A BAR: what it spent this period, of what it plans to spend in one
  # (answers-first spec §4).
  #
  # ** THE INVERSE OF THE ROW THIS REPLACED, AND THE SAME TWO READINGS OF THE SAME CATEGORY. ** The
  # categories band printed `$90.00 left` — `HoldingStatus#amount` on a `:left_to_spend` row — and
  # `$310.00 of $400.00` is that same $90 said from the other end. Nothing new is derived: `spent`
  # is `CategoryLedger::ENTRY_CATEGORY_ID` inside `User#period_datetimes_containing` (see
  # HomePresenter#holder_spending_this_period, which names both shared readers) and `planned` is
  # `EntryImpactPresenter#denominator`'s rule (see #planned_this_period).
  #
  # `status` TRAVELS ON THE ROW because the vocabulary survives as a small clause (spec §4, and
  # HomeHelper#period_row_clause) — one object carrying the figures AND the state, so a view cannot
  # pair one category's bar with another's word. `changed_after_distributing` rides along for the
  # same reason it rides on `Row`: the clause is threaded off ONE object rather than passed as an
  # optional keyword a caller is free to forget.
  PeriodRow = Data.define(
    :category,
    :spent,
    :planned,
    :held,
    :goal,
    :status,
    :changed_after_distributing
  ) do
    def goal? = goal
    def changed_after_distributing? = changed_after_distributing
    delegate :needs_attention?, to: :status

    # WHAT THE BAR FILLS TO. An envelope's bar measures SPENDING against the plan; a goal's measures
    # its HOLDING against the target it is saving toward (spec §4: "savings goals keep their target
    # bars"), which is the same bar `HoldingCalculator#progress_percentage` draws everywhere else in
    # the app. One member each rather than one signed number, because the two are read by different
    # halves of the row: #filled draws the bar, #held is what the goal's figure prints.
    def filled = goal? ? held : spent

    # A BAR NEEDS SOMETHING TO BE A FRACTION OF. A holder carrying no rule and no target has no
    # per-period plan, so the row prints the fact and no track — `EntryImpactPresenter#bar?`'s rule,
    # for its reason: an empty track beside a real figure says "nothing left" an inch under a line
    # saying otherwise.
    def bar? = planned.positive?

    # NOTHING TO SAY AT ALL: a holder carrying no rule and no target, which nobody has spent from
    # this period. It is the budgeted side of spec §4's rule that a zero-spend unbudgeted category is
    # absent from Home, and it is the same rule for the same reason — `spent $0.00` under a name is a
    # row that reports nothing and costs a line on the one screen that is supposed to answer four
    # questions. The Categories page remains the full index.
    def silent? = !bar? && spent.zero?

    # SPENT PAST THE PLAN — red bar, red figure (spec §4). NEVER true of a goal: holding more than
    # you were saving for is not an overspend. Exactly the plan is NOT over, for
    # `EntryImpactPresenter#overdrawn?`'s reason — spending an envelope to the penny is the tidiest
    # possible outcome and reading it as trouble would be the same lie as `-$0.00`.
    def over? = !goal? && bar? && spent > planned

    # WHOLE PERCENT, CLAMPED, matching `HoldingCalculator#progress_percentage` and
    # `HomePresenter::Progress#percent` — the app's other two bars — so all three draw the same way.
    def percent
      return 0 unless bar?

      ((filled / planned) * 100).round.clamp(0, 100)
    end
  end

  # AN EXPENSE CATEGORY NOBODY BUDGETED, WITH SPENDING INSIDE THIS PERIOD: the fact, and no bar
  # (spec §4). There is nothing for a bar to be a fraction of — its receipts drain AVAILABLE (§4's
  # start-date rule, which is the same rule that puts it in this list) — so a denominator here would
  # be inventing the pressure rather than reporting it.
  UnbudgetedRow = Data.define(:category, :spent)

  # ONE THING THAT NEEDS A HUMAN (spec §5). `kind` is which trigger; `subject` is the thing it is
  # about — a Pool for :overdraft, a Category for :category, nil for the two that are about the
  # user's whole position.
  #
  # A TYPE RATHER THAN FOUR LISTS ON THE PRESENTER, because the strip has to know whether it is
  # rendering at all before it renders anything: `#trouble?` is `troubles.any?`, one question over
  # one list, where four predicates OR'd together in a view is four chances to add a fifth trigger
  # and forget the gate.
  Trouble = Data.define(:kind, :subject)

  # ONE CATEGORY AS A ROW, AND IT IS `BudgetPagePresenter::Group`'S SHAPE ON PURPOSE.
  #
  # The two screens print the same sentence about the same category, and twice now they have printed
  # it differently: the Budget page's group passed `period_closed:` and not
  # `changed_after_distributing:`, and Home's own two bands passed one suffix each. Both defects were
  # possible for one reason — `pool_status_label` takes the suffixes as OPTIONAL keywords, so every
  # caller is free to thread one and forget the other, and a forgotten one is silent.
  #
  # This is the fix, and it is structural rather than vigilant: `shared/_holding_status` threads both
  # suffixes off ONE object, and that object is this Data — so a caller does not decide which
  # suffixes to pass, it decides which OBJECT to pass, and an object missing an answer raises
  # NoMethodError at render rather than dropping a clause.
  #
  # `orphan` IS GONE (Task 6) and so is `#needs_attention?`'s OR with it. A category belongs to no
  # account and needs none — allocating money moves nothing physical (§2) — so the state "nothing can
  # fund this" has no shape left to describe, and the status alone decides both the colour and the
  # auto-expand.
  Row = Data.define(:category, :status, :period_closed, :changed_after_distributing) do
    def period_closed? = period_closed
    def changed_after_distributing? = changed_after_distributing
    delegate :needs_attention?, to: :status

    # THE CLAUSE THIS SCREEN ADDS AFTER THE STATE, and Home's is a date. Of the three quiet states —
    # `on track`, `saving` and `left to spend` — only the first has one to add: the other two have no
    # anchored rule to take a date from, so #due_on is nil there anyway. A row needing attention has
    # already said its date inside the label.
    def due_marker? = !status.needs_attention? && status.due_on.present?

    # Home does NOT print `· holds $X`, which is the Budget page's clause. Both screens print one
    # clause after the state and they are different clauses, deliberately: a Home row shows no rules
    # and no balance elsewhere, so a date is the thing it is missing, while a Budget card lists every
    # rule underneath and is missing only the money. Said here rather than in the partial so the
    # partial asks the row instead of asking which screen it is on.
    def balance_clause? = false
  end

  # WHERE THE PERIOD IS, AS THE CARD DRAWS IT (answers-first spec §2). Four members and two derived
  # answers, because the two are one subtraction apart and a member for each would be a second place
  # for the same number to be wrong — `AllocationCalculator::Row#short`'s rule, one level up.
  #
  # `day` IS 1-BASED AND INCLUSIVE AT BOTH ENDS, which is the only reading that makes both edges
  # true: the opening day is day 1 of 14 rather than day 0 (nobody is zero days into a period they
  # are standing in), and the closing day is day 14 with nothing left. That fixes #days_left as
  # `days - day` — the same figure as `last - today`, spelled off the members this object already
  # carries so the two cannot disagree.
  Progress = Data.define(:first, :last, :day, :days) do
    def days_left = days - day

    # WHOLE PERCENT, CLAMPED, matching `HoldingCalculator#progress_percentage` — the app's other
    # bar — so the two draw the same way. The clamp is belt and braces: `period_containing(today)`
    # contains today by construction, so neither bound is reachable from here.
    def percent = ((day.to_f / days) * 100).round.clamp(0, 100)
  end

  attr_reader :user, :today

  # `rejected_movement:` IS ONBOARDING STEP 2'S OWN 422 (main-account spec §5), threaded through
  # rather than read off an ivar the view would have to know about. AccountFundingsController's
  # failure branch hands back the unsaved, invalid PoolMovement it tried to save, and #funding_
  # movement_for below is how the ONE account it was for gets it back — every other account's
  # card renders a fresh, blank one. Optional and nil everywhere else Home is built, which is
  # every other caller of this presenter.
  #
  # A `PoolMovement` AND NOT AN `Allocation`, which is not a leftover: account funding is a move on
  # the PHYSICAL ledger (main → the account it is really in), and that lane is untouched by this plan
  # until Task 8 renames its table. Nothing on the purpose side has a form on this screen.
  def initialize(user:, today: Date.current, rejected_movement: nil)
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
  # It was `#current_buffer_for`, and the rename is the model rather than a tidy-up. A "buffer" was
  # an account's cash net of the envelopes housed inside it; nothing is housed inside an account any
  # more, so the account's balance IS everything it holds and there is no unallocated remainder to
  # name. The word ALSO moved: the distribution screen calls AVAILABLE the buffer (§7.1 — the money
  # no category has claimed), so leaving it here would have put one word over two different
  # quantities on one screen, which is the exact defect #projected_buffer vs #current_buffer_for was
  # split to prevent.
  #
  # ONE LEDGER FOR EVERY ACCOUNT ON THE SCREEN, so the accounts band, the overdraft lines and the two
  # onboarding gates all read one snapshot.
  delegate :balance_of, to: :account_ledger

  # Accounts that have gone below zero, and the loudest fact on the screen.
  #
  # THEY ARE NOT PROBLEM ROWS ANY MORE (Task 6), and that is a correction rather than a loss. An
  # overdrawn account is a PHYSICAL fact — money already spent out of a bank account — and the fix
  # button beside a problem row proposes an ALLOCATION, which moves nothing physical (§2). Offering
  # one here would be a real mistake proposed to fix a problem it cannot touch, which is the same
  # ruling that keeps a fix off an overdue bill whose category already holds the money. The standing
  # band names the account and the figure in red, and the accounts band prints the negative balance;
  # what goes away is the button, not the debt.
  def overdrawn_accounts
    accounts.select { |account| balance_of(account).negative? }
  end

  # The debt as a positive figure, for the sentence that states it. `-balance`, exactly as
  # HoldingStatus spells :overdrawn's own amount.
  def overdraft_for(account) = -balance_of(account)

  # ONBOARDING STEP 2'S ONE GATE (main-account spec §5): not main, and holding no money yet. ONE
  # predicate, asked by the view (which account gets the card — home/_account.html.erb) and by
  # AccountFundingsController (which write is legal), so the two cannot drift into two different
  # answers about the same account.
  #
  # `AccountLedger#balance_of` WHERE THIS READ `Pool#total` (Task 6). That reader was "unallocated
  # cash PLUS every envelope housed inside it", and it existed because an account whose envelopes
  # held every dollar it had read as "never funded" — the card came back under a fully funded account
  # asking the user to match their bank statement a second time. Nothing is housed inside an account
  # now, so the family total and the balance are the same figure and only one of them still has a
  # reader. `Pool#total` is envelope-era and dies in Task 8.
  #
  # MED-1'S PROTECTION SURVIVES UNCHANGED, which is what the money test is for: a fresh account is
  # zero however many categories the user owns, because a category is not inside it. Deliberately NOT
  # "has no categories" in any spelling — money is the only signal.
  #
  # `user.default_account.present?` FIRST (HIGH-1, a 500 fixed): the card used to read
  # `main_account.name` unconditionally, and a user with no main account 500'd on Home with no door
  # back in. No main account means no card anywhere, full stop, not merely "no card on the pool that
  # used to be main": every account is equally un-fundable with nothing to fund it FROM.
  #
  # THE SHAPE THAT REACHES IT IS NOW THE FIRST DAY, not a deletion (final fix wave, C-1). This note
  # used to credit `users.default_account_id`'s `on_delete: :nullify` — main being DELETED out from
  # under the pointer — and `Pool#main_account_is_not_deletable` closed that path: main cannot be
  # destroyed while it is main. What remains reachable is a user who has not created an account yet,
  # which is every user on their first visit, so the guard is load-bearing exactly as before.
  def awaiting_funding?(account)
    user.default_account.present? && account != user.default_account && balance_of(account).zero?
  end

  # ONBOARDING STEP 3'S OWN GATE (main-account spec §5): the account under review must BE the user's
  # main account — not merely funded, this correction only ever applies to the one account that isn't
  # funded by a movement — and the one-time latch, the "Opening Balance" category's own existence,
  # must still be open. Asked here (which account gets the card — home/_account.html.erb) and
  # LITERALLY BY `OpeningBalancesController#create`, which builds its own presenter and calls this
  # same method rather than re-spelling either half of it, so the card's render gate and the write's
  # legality gate cannot drift into two different answers.
  #
  # `user.default_account.present?` FIRST, for the same HIGH-1 reason #awaiting_funding? checks it
  # first. It also makes `awaiting_opening_balance?(nil)` — reachable if a crafted POST names no
  # account — false rather than a NoMethodError, because `nil.present?` short-circuits the `&&`
  # before `account == user.default_account` is ever asked.
  def awaiting_opening_balance?(account)
    user.default_account.present? && account == user.default_account && !opening_balance_recorded?
  end

  # IS THIS THE ACCOUNT EVERYTHING FLOWS THROUGH (final fix wave, C-1)? The view's gate on the Delete
  # button, and it is `Pool#main?` rather than a comparison of this screen's own: the model REFUSES
  # the destroy on exactly that predicate, so a screen asking a differently-spelled question could
  # offer a button the server then rejects — or, worse, hide one it would have accepted.
  #
  # FREE ON THIS SCREEN: `#accounts` loads through `user.pools`, so each row's `belongs_to :user` is
  # the presenter's own already-loaded user through the automatic inverse, and `default_account_id` is
  # a column on it. No query per card.
  def main?(account) = account.main?

  # THE FUND-ACCOUNT CARD'S FORM OBJECT (onboarding step 2). The rejected movement if THIS is the
  # account it was refused for — so its typed amount and its errors survive the re-render, the same
  # courtesy BankAccountsController's own 422 branch pays the add-account card — and a fresh unsaved
  # one otherwise, so every other card's `simple_form_for` still has a record to ask for a (blank)
  # value rather than a bare symbol with nothing behind it.
  def funding_movement_for(account)
    return @rejected_movement if @rejected_movement&.to_pool_id == account.id

    AccountMovement.new(to_pool: account)
  end

  # ── THE PURPOSE LEDGER ─────────────────────────────────────────────────────────────────────────

  # THE CATEGORIES THAT HOLD MONEY, in the order a distribution reaches them. `Category.in_fill_order`
  # rather than a scope of this screen's own: it is holders (`expense? && funded_since.present?`)
  # ordered `[priority, name]`, which is exactly the set and exactly the order AllocationCalculator
  # fills — so the band, the waterfall and the action the button opens cannot fall into different
  # orders or over different sets. Priority alone is not a total order; `name` is unique per user, so
  # the pair is.
  #
  # `:budgets` eager-loaded because every row asks for them three times over — #dated_rules_for,
  # the status's anchored rules, and DistributionClock#changed_after_distributing?.
  def categories
    @categories ||= user.categories.in_fill_order.includes(:budgets).to_a
  end

  # MONEY WITH NO JOB YET, PLUS WHAT THE NEXT DISTRIBUTION SWEEPS BACK — `AllocationCalculator
  # #available` to the character, and that identity is the point rather than a coincidence.
  #
  # THE SWEEP IS NOT DOUBLE-COUNTING: swept money is inside the user's total but not inside
  # `CategoryLedger#available`, because funding the category was an allocation out. It is sitting in a
  # category and the sweep is what moves it back to the root.
  #
  # NOT CLAMPED AT ZERO, which is the one place this reader CHANGED with the collapse to one root.
  # The pool era clamped each account's pot before summing, because an overdrawn account cancelling a
  # healthy one's surplus gives a figure that is true about net worth and false about what can be
  # allocated. There is no sibling to cancel against now — one root — so a negative available is a
  # fact the screen must state rather than a figure to round up to nothing, exactly as
  # AllocationCalculator leaves it. The two screens no longer diverge; the divergence that used to be
  # pinned in spec/system/home/fixes_spec.rb is gone with the accounts it was about.
  #
  # IT IS NOW THE PROPOSAL'S OWN FIGURE RATHER THAN AN EXPRESSION THAT MATCHED IT (Task 7, the T6
  # review's adopted recommendation). This read `ledger.available + total_swept`, which is
  # character-for-character `AllocationCalculator#available` — two spellings of one figure, kept in
  # step by three cross-pins in the specs. Delegated, they cannot drift at all.
  delegate :available, to: :proposal

  # WHAT THE REST OF THIS PERIOD'S PLAN STILL ASKS FOR AND HAS NOT BEEN GIVEN — the hero card's
  # "spoken for" (answers-first spec §3). Post-sweep, exactly as the distribution screen computes
  # it, and off the SAME ROWS: a category the fill rejects for asking nothing contributes nothing to
  # a sum over the rows. The `0.to_d` seed is the type guarantee for the user with no rows at all.
  #
  # ** ONE SPELLING, AND THIS IS THE READER IT IS. ** `AllocationCalculator::Row#needed` is
  # `HoldingCalculator#required` on the net-of-sweep calculator `AllocationCalculator
  # #ask_calculator_for` builds — the same object, from the same class, that the distribute
  # waterfall prints a row of and that `DistributionPresenter::Line#needed` carries. Spec §3 writes
  # the figure as `Σ max(0, this period's ask − allocated this period)`, and every part of that is
  # ALREADY inside `needed`: `#required` measures each rule against `#allocated_balances` (what the
  # category is already holding for it), and `AllocationCalculator#fill` floors the category's ask
  # at zero and drops the rows that ask for nothing. Re-deriving any of it here would be a second
  # answer to "what do I still owe this period", which is the one thing this plan forbids —
  # `spec/presenters/home_presenter_spec.rb` reads the figure through both entry points on one
  # fixture and compares them.
  #
  # IT WAS `#total_required`, RENAMED RATHER THAN JOINED (answers-first Task 1). Two names for one
  # sum is the drift the rule is written against; what changed is Home's word for it.
  #
  # DELIBERATELY NOT `Budget.steady_need`, which is the STRUCTURAL question — what the rules claim
  # from a TYPICAL period — and diverges from this in both directions on the same budget. See
  # #structurally_underwater?, which is the reader that wants the other one.
  def remaining_plan = waterfall.sum(0.to_d, &:needed)

  # Fills top-down by priority, exactly as a distribution would, so the user sees who gets paid first
  # and where the money ran out.
  #
  # ONE POT, NOT ONE PER ACCOUNT (§2). The pool era filled each account's own buffer because money
  # could not cross an account boundary; an allocation crosses nothing, so a single `remaining` is
  # the model rather than a simplification of it — and it is `AllocationCalculator#fill`'s own shape.
  #
  # Memoised because #remaining_plan, #free_to_spend, #undistributed_period? and
  # #covered_by_waterfall? all derive from these rows, so a Home render asks for them several times
  # over. (#shortfall, #covered? and #cutoff were three more, and they are deleted — see below.)
  # ROWS ARE `AllocationCalculator::Row` NOW, not hashes this class fills itself (Task 7). They
  # answer #category, #needed, #funded and #short.
  #
  # `Struct#[]` ANSWERS THE FIRST THREE BY NAME AND RAISES ON THE FOURTH, which is worth writing
  # down because it decided which lines had to change: `category`, `needed` and `funded` are
  # MEMBERS, so the deleted `home/_attention.html.erb`'s `row[:funded]` rendered unchanged; `short`
  # is a METHOD (`needed - funded`, so a fourth member would be a second place for one number to be
  # wrong), and `row[:short]` raises `NameError: no member 'short' in struct`. Every reader of it is
  # `row.short` — measured, not reasoned about: the deleted #cutoff's block took the root route down
  # until it was, and `fixes_spec`'s cross-pins spell `sum(&:short)` for the same reason.
  def waterfall = proposal.rows

  # ── `#cutoff`, `#shortfall` AND `#covered?` ARE DELETED (answers-first Task 2), and the reason is
  # that Home stopped asking their question rather than that nothing happened to call them.
  #
  # All three existed for the waterfall band: `#cutoff` drew "— ran out here —" between two groups of
  # rows, `#shortfall` printed the figure inside that line, and `#covered?` was the band's gate and
  # the standing band's headline branch. The band is gone (spec §1: Home stops showing the system),
  # and so is the headline branch — the hero card renders in every state and a short period is simply
  # a negative `#free_to_spend` (spec §2, which rules the covered/uncovered question closed).
  #
  # NOTHING ELSE ASKED THEM. Grepped across `app/`: `#waterfall` has three live readers here
  # (`#remaining_plan`, `#undistributed_period?`, `#covered_by_waterfall?`), and these three had
  # none once the band went. They would have survived as readers kept alive by their own specs,
  # which is the shape a comment cannot fix.
  #
  # WHERE EACH QUESTION LIVES NOW: the cutoff RULE is `Waterfall.cutoff`, drawn by
  # `DistributionPresenter#cutoff` on the screen the trouble strip's own Distribute button opens
  # (pinned both directions in `spec/system/distributions/proposal_spec.rb` and `overrides_spec.rb`);
  # the total gap is `waterfall.sum(&:short)`, which is what the cross-screen pins in
  # `spec/system/home/fixes_spec.rb` compare against `AllocationCalculator` directly.

  # ── THE HERO CARD (answers-first spec §§2-3) ───────────────────────────────────────────────────
  #
  # `#projected_buffer` IS DELETED HERE, and the deletion is what these three readers are for. It
  # was `available − Σ FUNDED`, so it clamped itself to what the waterfall actually handed out and
  # read $0.00 on every short period — "nothing left over", said to a user $250 short. Worse, the
  # band that printed it had to gate on `available.negative?` to stop calling a deficit "unclaimed
  # money" (fix round 1, MED-1). `#free_to_spend` subtracts what the plan still ASKS for, so the
  # gap is the figure rather than a state to be branched on, and there is one card in every state.

  # THE NUMBER THE USER'S BANK APP SHOWS — `AccountLedger#pot`, which is main's balance and only
  # main's (§2: main carries the entry side of the physical ledger, every other account is movements
  # alone). Named for what the card calls it, off the same ledger the accounts band reads, so the
  # two figures on one screen cannot come from two snapshots.
  #
  # MEMOISED, AND MEASURED RATHER THAN ASSUMED. `AccountLedger#pot` is `#balance_of(main)`, and that
  # method's entry term is NOT memoised in the ledger — it is two SUMs over the user's entries every
  # time it is asked. The card asks three times (this figure, then #free_to_spend's `min`, then
  # #free_cap_bound?'s comparison), which measured as six statements before this memo; the pin in
  # `spec/presenters/home_presenter_spec.rb` holds it at two and then at none. `||=` is safe where
  # `defined?` would be needed for a falsy answer: a zero pot is `BigDecimal("0")`, which is truthy.
  def in_checking = @in_checking ||= account_ledger.pot

  # ** THE ONE DERIVED NUMBER (spec §3): `min(pot, available − remaining_plan)`. **
  #
  # `#available` IS THE PROPOSAL'S, POST-SWEEP, AND IT HAS TO BE THAT ONE. Spec §3 names
  # `CategoryLedger#available`; this presenter's `#available` is that figure PLUS what the next
  # distribution sweeps back, and `#remaining_plan` is the ask computed as if the sweep had ALREADY
  # happened (see AllocationCalculator#ask_calculator_for, which exists for exactly that reason).
  # Subtracting a post-sweep ask from a pre-sweep root charges the user for every swept dollar
  # twice: the money is missing from the left-hand side while the right-hand side already assumes it
  # is back. The two halves have to describe one moment, and this presenter's `#available` is the
  # moment the rest of the screen is about.
  #
  # THE CAP AT THE POT IS RULED (spec §3): free money you would have to transfer out of savings
  # before you could spend it is not free in the moment. #free_cap_bound? is which side won.
  #
  # NEVER CLAMPED. A period that has promised or spent more than it has renders a negative figure in
  # red with a sentence that says why; rounding it up to zero would be the app telling the user they
  # are fine. The `min` of two BigDecimals is a BigDecimal, and both operands carry their own type
  # guarantee, so the fresh user gets `0.0` rather than an Integer.
  def free_to_spend = [in_checking, unspoken_for].min

  # DID THE CAP BIND — the subline's gate, and the reason it is a predicate rather than the view
  # comparing the two figures itself: a screen that re-spelled the `min`'s condition could print
  # "more is parked in other accounts" beside a figure the other branch produced.
  #
  # A STRICT `<`, so equality is not "parked somewhere else": with $1,000 in checking and exactly
  # $1,000 unspoken for there is one pile of money, and the card would be inventing a second.
  def free_cap_bound? = in_checking < unspoken_for

  # ** WHICH KIND OF NEGATIVE THIS IS, AND IT IS A REAL BRANCH RATHER THAN A SHADE OF ONE (fix
  # round 1 — MED-1). ** `#free_to_spend` goes below zero for two completely different reasons and
  # the card was telling both of them the same story:
  #
  #   THE PLAN OUTRUNS THE MONEY — this is true. Every rule this period wants more than the root
  #     holds, so there genuinely is nothing spare anywhere and spending goes further under.
  #   THE MONEY IS IN THE WRONG ACCOUNT — this is NOT that. Measured: $1,000 of income with $1,200
  #     walked over to a savings account and nothing budgeted at all leaves the pot at -$200 while
  #     $1,000 is unspoken for. The card said "More is set aside or spoken for than you have" — $0
  #     is set aside — and "nothing is free until money comes in", one transfer away from $1,000.
  #     Two false sentences about a user who is not in trouble.
  #
  # THE SIGN OF `unspoken_for`, WHICH IS `#free_to_spend` BEFORE THE POT CAPS IT, is the only thing
  # that tells them apart: the capped figure cannot, because the cap is exactly what erases the
  # difference. `#free_cap_bound?` is NOT this question and must not be used for it — a pot of
  # -$500 against an unspoken-for -$100 is cap-bound AND genuinely out of money.
  #
  # WHAT THE VIEW IS ALLOWED TO DO WITH IT: branch. The card asks this and #free_cap_bound?; it
  # never compares `#in_checking` against anything itself, because a second spelling of the `min`'s
  # own condition is how a figure and the sentence under it come to describe different arithmetic.
  def plan_outruns_the_money? = unspoken_for.negative?

  # WHERE WE ARE IN THE PERIOD — day X of Y, and the bar's own percentage (spec §2).
  #
  # Off `#period_range`, never a second window: that reader is `User#period_containing`, the one
  # method that owns this arithmetic, and it is nil for a user who has declared no period. The card
  # draws no bar there rather than inventing a calendar month — the same refusal the band this
  # replaced made about the same reader.
  def period_progress
    range = period_range
    return nil if range.nil?

    Progress.new(first: range.first, last: range.last, day: (today - range.first).to_i + 1, days: range.count)
  end

  # Sorted for the same reason #waterfall is, and by the same key: this is a rendered list, and the
  # order the user ranked their categories in is the order "what do I deal with" wants. #categories
  # is already `[priority, name]`, so the select preserves it.
  def attention_categories
    categories.select { |category| status_for(category).needs_attention? }
  end

  # ── "THIS PERIOD" — SPENDING AS PROGRESS (answers-first spec §4) ───────────────────────────────

  # THE BUDGETED ROWS, TROUBLE FIRST AND THEN FILL ORDER (spec §4).
  #
  # `sort_by` IS NOT STABLE IN RUBY, so the index is part of the key rather than left to chance:
  # #categories is already `[priority, name]` — the order a distribution reaches them — and without
  # the tiebreak two quiet categories could swap places between page loads with no data change,
  # which is the same defect `HoldingCalculator#budgets_by_due_date` carries its triple key for.
  def period_rows
    @period_rows ||= categories.each_with_index
      .sort_by { |category, index| [status_for(category).needs_attention? ? 0 : 1, index] }
      .map { |category, _index| period_row_for(category) }
      .reject(&:silent?)
  end

  # THE UNBUDGETED ROWS: an expense category nobody has given a rule, WITH spending inside this
  # period (spec §4). Zero-spend ones are absent by construction — they never appear in the grouped
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

  # ── TROUBLE, ONLY WHEN TRUE (answers-first spec §5) ────────────────────────────────────────────

  # EVERYTHING THAT NEEDS A HUMAN, AS ONE LIST. Each entry comes from a reader this class already
  # had — the strip re-houses the attention band's sources rather than re-deriving them — and the
  # ORDER is the order a reader needs them: money already gone, then the categories it went missing
  # from, then the two acts that are still available (hand this period out; change the rules).
  #
  # FIVE KINDS WHERE SPEC §5 LISTS FOUR, and the fifth is the plan's own carry-over rather than an
  # addition: §9's permanent "your budget doesn't fit your income" button had no home once the
  # standing band became a card, so Task 1 parked it on the hero and Task 2 claims it. A strip that
  # renders ONLY when something is true is the right place for it — the verdict IS something true,
  # and it is the one kind of trouble no reallocation can fix.
  def troubles
    @troubles ||= [
      *overdrawn_other_accounts.map { |account| Trouble.new(kind: :overdraft, subject: account) },
      *attention_categories.map { |category| Trouble.new(kind: :category, subject: category) },
      *(undistributed_period? ? [Trouble.new(kind: :undistributed, subject: nil)] : []),
      *(structurally_underwater? ? [Trouble.new(kind: :structural, subject: nil)] : [])
    ]
  end

  # WHETHER THE STRIP RENDERS AT ALL. Asked once, over one list: spec §5 rules out a permanent
  # "Nothing needs you" box, so silence is the good state and this is the gate that produces it.
  def trouble? = troubles.any?

  # A NON-MAIN ACCOUNT BELOW ZERO. Main is excluded because ITS overdraft is the hero card's red
  # "In Checking" figure with its own sentence (spec §2) — printing the same debt twice, with two
  # different sentences about what counts it, is worse than printing it once.
  #
  # `main?` rather than a comparison of this class's own, for the reason that predicate exists: the
  # model refuses a destroy on exactly it, so a second spelling here could hide a real debt or
  # double-report one.
  def overdrawn_other_accounts
    overdrawn_accounts.reject { |account| main?(account) }
  end

  # THIS PERIOD'S MONEY HAS NOT BEEN HANDED OUT, AND THERE IS SOMETHING TO HAND OUT.
  #
  # `DistributionClock#distributed_this_period?` is the same one query `#changed_after_distributing?`
  # already runs for this screen — the clock owns "which distribution is this period's", and a second
  # `Allocation.distributed` inside a period window spelled here would be free to disagree with it
  # and with `AllocationCommitter`.
  #
  # THE `waterfall.any?` HALF IS NOT A GUARD, IT IS THE OTHER HALF OF THE QUESTION. Every fresh
  # account has an undistributed period by definition, so without it the strip would greet every new
  # user with a demand they cannot act on. A user whose rules ask for nothing has nothing to
  # distribute, which is not trouble.
  def undistributed_period? = waterfall.any? && !distribution_clock.distributed_this_period?

  # ── THE ACCOUNTS, DEMOTED TO ONE LINE (answers-first spec §6) ──────────────────────────────────

  # WHAT THE LINE IS ABOUT: the accounts that are neither main nor mid-onboarding. Main is out
  # because its balance IS the hero's "In Checking" figure, and counting it here would answer one
  # question twice with two different numbers; an onboarding account is out because its card is
  # rendered top-level and a figure in the line for a card sitting above it reads as two accounts.
  def other_accounts = accounts.reject { |account| main?(account) || onboarding?(account) }

  def other_accounts_total = other_accounts.sum(0.to_d) { |account| balance_of(account) }

  # THE CARDS THE LINE HIDES, which is every account whose onboarding is finished — MAIN INCLUDED.
  # The line's FIGURE is about the others; the expansion is the accounts INDEX, and Home carries
  # rename and delete since `pools/index` and `pools/show` were deleted, so main's card has to stay
  # reachable somewhere.
  def collapsed_accounts = accounts.reject { |account| onboarding?(account) }

  # STILL UNFINISHED, so the card surfaces top-level (spec §6). Both gates asked through the
  # presenter's own predicates rather than re-spelled, because each is ALSO the gate a controller
  # checks before accepting the write the card submits.
  def onboarding_accounts = accounts.select { |account| onboarding?(account) }

  def onboarding?(account) = awaiting_funding?(account) || awaiting_opening_balance?(account)

  # THE ROW OBJECT `shared/_holding_status` IS GIVEN, built here rather than in the partial for the
  # reason #status_for and #period_closed? are: every member is dated against THIS presenter's
  # `today`, and a view assembling its own would be free to build one of them against `Date.current`
  # and disagree with the rest of the screen silently.
  #
  # Both suffixes are read HERE, together, for every row — which is the point. They used to be two
  # keyword arguments a partial could pass separately, and Home's two bands did exactly that.
  def row_for(category)
    Row.new(
      category: category,
      status: status_for(category),
      period_closed: period_closed?(category),
      changed_after_distributing: changed_after_distributing?(category)
    )
  end

  # Views MUST use this rather than calling `category.status` directly. HoldingStatus defaults to
  # Date.current, so a bare call in a partial would compute against a different day than this
  # presenter whenever `today` is injected — and disagree silently.
  def status_for(category)
    @statuses ||= {}
    @statuses[category.id] ||= category.status(today: today, terms: ledger.terms_for(category))
  end

  # Whether this category's money belongs to a period that has already ended — what the row marks as
  # ` · last period` and what the next distribution will sweep back.
  #
  # Here rather than in the partial for the same reason as #status_for, and routed through
  # #calculator_for so it reuses the calculator Home has already built for this category.
  def period_closed?(category) = calculator_for(category).period_closed?

  # SPEC §8'S ONE ROUGH EDGE — `behind $50.00 — you changed a rule here after distributing`, the
  # clause that tells a user whose category went red because they edited a rule apart from one whose
  # money genuinely went missing.
  #
  # `DistributionClock` OWNS THE WHOLE ANSWER, including the wording's justification and the
  # period-bounded query behind it. It moved out of this class when the Budget page had to print the
  # same clause, and Task 6 moved this caller onto its CATEGORY arm: one root means one distribution
  # per period and one moment it happened at, so the clock takes a user and no account list at all.
  #
  # `delegate` TO A PRIVATE METHOD, and both halves are deliberate. Rails emits an implicit-receiver
  # call, so a private target is reachable; and the laziness this screen needs lives inside
  # #distribution_clock's own memo, so the clock's one query runs only when a row actually asks.
  delegate :changed_after_distributing?, to: :distribution_clock

  # The dated rules behind a category, earliest due first, each paired with the due date its row
  # prints. What an expanded row shows: a category needing attention owes the user the rules that put
  # it there.
  #
  # Here rather than in the partial for the same reason as #status_for, one level down:
  # `budget.calculator` defaults to Date.current, so a view building its own calculators would date
  # these rules against a different day than every other figure on the screen.
  #
  # Anchorless rules are excluded because they have no date to print; a row whose rules are all
  # anchorless renders its own explanation instead (see _holding_row). The sort key is
  # BudgetCalculator#due_order, the same one HoldingStatus#anchored_budgets and the fill order itself
  # use — `category.budgets` carries no ORDER BY, so without it two rules sharing a due date could
  # swap places between page loads. Memoised because BudgetCalculator#due_date re-runs its
  # paid_since_anchor SUM on every call, which is also why the date this has already computed is
  # handed to #due_order rather than left for it to ask again.
  def dated_rules_for(category)
    (@dated_rules ||= {})[category.id] ||= category.budgets
      .select { |budget| budget.anchor_date.present? }
      .map { |budget| [budget, calculator_for_budget(budget).due_date] }
      .sort_by { |budget, due_on| calculator_for_budget(budget).due_order(due_on) }
  end

  # ── THE PERIOD, AND THE STRUCTURAL VERDICT ─────────────────────────────────────────────────────

  # WHICH PERIOD THE SCREEN IS TALKING ABOUT, or nil for a user who has declared none.
  #
  # `User#period_containing`, the one method that owns this arithmetic — the same window
  # `DistributionPresenter#period` and `EntryImpactPresenter#period_ends_on` both read off, never
  # re-derived here. GATED ON THE DECLARATION rather than taken on trust: `period_containing` falls
  # back to the calendar month for an undeclared user, which is the right fallback for a normaliser
  # and a lie on this card, since "Aug 1 – Aug 31" would state a boundary the user never set.
  def period_range
    return nil if user.period_cadence.blank? || user.period_anchor_date.blank?

    user.period_containing(today)
  end

  # DOES THE BUDGET FIT THE INCOME — a question about the shape of the rules, not about this
  # afternoon's cash.
  #
  # `Budget.steady_need`, not `remaining_plan`, which is THIS period's ask — catch-up on anything
  # behind, zero on anything already funded — and the two diverge in both directions on the same
  # budget. A period spent catching up on a slipped bill reported "your budget doesn't fit your
  # income" at someone whose rules fit it comfortably, and the period right after a distribution
  # reported nothing at all on a budget that does not fit. The second is the dangerous one: the whole
  # point of the check is that reallocation cannot fix a budget that does not fit.
  #
  # BOTH HALVES OF THE DECLARATION, income AND cadence — the same gate `BudgetPagePresenter#declared?`
  # applies, because it is the same question. Income with a blank cadence is a reachable state, and in
  # it `Budget.steady_need` falls back to treating the period as a calendar month. That fallback is
  # right for a per-rule normaliser and useless as a verdict: "$1,668 a period" at a user who has not
  # said how long a period is states a figure with no unit, and this band delivers the verdict WITHOUT
  # the figures that would justify it. `/budget` already refuses to print those figures; Home refusing
  # to print the verdict from them is the same refusal.
  #
  # Memoised, and the `false` case has to be memoised too — `||=` would recompute the whole sum on
  # every call for exactly the users who answer false.
  def structurally_underwater?
    return @structurally_underwater if defined?(@structurally_underwater)

    @structurally_underwater =
      user.typical_income.present? &&
      user.period_cadence.present? &&
      Budget.steady_need(user, today: today) > user.typical_income.to_d
  end

  # ── THE FIX A PROBLEM ROW OFFERS ───────────────────────────────────────────────────────────────

  # WHAT MOVING MONEY IN WOULD ACTUALLY CLOSE — HoldingStatus#funding_gap, not #amount.
  #
  # The two coincide on :overdrawn, :behind and :wont_make_it, and those are the only attention
  # states whose ROW prints a figure at all (`overdrawn $80.00`, `behind $385.00`; the other prints a
  # date), so the button and the label beside it still name one number.
  #
  # They diverge on :overdue, and taking #amount there was a measured defect: the demo's Renters
  # Insurance holds every penny of a $180 premium that has simply not been paid, and Home offered
  # "Take $180.00 from Available" — a real mistake proposed to fix an imaginary problem, which would
  # have left the category holding $360 against a $180 bill. #funding_gap returns zero there, and the
  # band says what the bill actually needs instead. See _attention.html.erb.
  #
  # `.round(2)` so the THREE places this figure lands cannot disagree: the button's label (rounded by
  # number_to_currency), the link's `amount=` (rounded by Fix#amount_param) and the damage preview
  # (computed from whatever is passed to ReallocationPresenter). Display-identical either way; the
  # point is that the link and its own preview describe one move.
  def fix_amount_for(category) = status_for(category).funding_gap.round(2)

  # THE PARTIES WITH ENOUGH FREE MONEY, IN THE ORDER THE REALLOCATION SCREEN OFFERS THEM.
  #
  # AVAILABLE IS ALWAYS ONE OF THEM AND IS ALWAYS FIRST — `ReallocationPresenter#sources`' own order,
  # for its own reason: idle money costs nothing to move, while a category's money is money the user
  # decided to protect. Richest-first proposed exactly the opposite on the demo — a $950 house down
  # payment offered four times over while $330 of unallocated money sat unoffered.
  #
  # THERE IS NO SAME-ACCOUNT TEST. `PoolMovement#crosses_accounts?` decided which pools could reach
  # each other; an allocation moves nothing physical (§2), so every one of the user's holder
  # categories is reachable from every other and the whole filter is gone.
  #
  # `free_amount` — holding less what EVERY rule holds — and not the balance, which is the threshold
  # a USER-INITIATED move is gated on (ReallocationPresenter::Candidate#affordable?). Two thresholds
  # for two different acts, deliberately: there the app STATES the damage rather than forbidding the
  # move, here the app is PROPOSING, so it must not propose robbing a category that is counting on the
  # money. AVAILABLE is in the third case by construction — it holds money for no rule, so its free
  # amount is its whole holding.
  #
  # A category whose own status needs attention is excluded outright: proposing to rob a category that
  # is itself behind is not a fix.
  def fix_candidates_for(category)
    (@fix_candidates ||= {})[category.id] ||= compute_fix_candidates(category)
  end

  # The one fix a problem row renders. nil `candidate` is the no-source case.
  #
  # `fetch` with a block rather than `||=`, because nil is a real answer here and `||=` would rebuild
  # it on every hit.
  def fix_for(category)
    @fixes ||= {}
    @fixes.fetch(category.id) { @fixes[category.id] = build_fix(category) }
  end

  private

  # ── WHAT ONE "THIS PERIOD" ROW IS MADE OF ──────────────────────────────────────────────────────

  # Every member dated against THIS presenter's `today` and read off the ONE calculator this screen
  # already built for the category — `#calculator_for`'s memo, so a row costs no aggregate of its
  # own and the bar's shape (`goal`) cannot come from a different reading than the figure in it.
  def period_row_for(category)
    calculator = calculator_for(category)

    PeriodRow.new(
      category: category,
      spent: spent_this_period(category),
      planned: planned_this_period(category),
      held: calculator.balance,
      goal: calculator.saving_toward_a_target?,
      status: status_for(category),
      changed_after_distributing: changed_after_distributing?(category)
    )
  end

  # WHAT THIS CATEGORY PLANS TO SPEND IN ONE PERIOD — `EntryImpactPresenter#denominator`'S RULE,
  # ASKED RATHER THAN RESTATED. That reader is the app's existing answer to "what is this category
  # for, per period", and it is two arms for reasons measured on the demo seeds:
  #
  #   A GOAL MEASURES AGAINST ITS TARGET. `target_amount` is the figure `HoldingCalculator
  #     #progress_percentage` and `#remaining_amount` already measure against, and it is what keeps
  #     spec §4's "savings goals keep their target bars" true of a goal that ALSO carries a rate
  #     rule (Retirement Supplement: $150 a period against $100,000) — under Σ steady_ask its bar
  #     draws full an inch under a line reading "of $100,000.00".
  #   AN ENVELOPE MEASURES AGAINST Σ `Budget#steady_ask`. That is the app's ONE per-period
  #     normaliser: a $1,500-a-month rule claims $692.31 of a biweekly period, and a denominator in
  #     sticker prices would draw a full envelope as a fifth of one.
  #
  # `saving_toward_a_target?` OFF THE MEMOISED CALCULATOR, which is the CHROME level of the app's
  # two-level goal classification (see that reader's own comment) — the same predicate the impact
  # card, the holdings card and the categories index card all ask to decide whether to draw a target
  # bar. Home's row VOCABULARY stays on the other level (`HoldingStatus#saving?`), deliberately, and
  # the pair is why an anchor-dated goal reads `on track` beside an envelope-shaped bar.
  #
  # DELIBERATELY NOT `HoldingCalculator#required`, which is what the category still ASKS for — zero
  # on anything already funded, a catch-up on anything behind. A bar denominated in it would shrink
  # as the user funded the category, which is the opposite of a plan.
  def planned_this_period(category)
    return category.target_amount.to_d if calculator_for(category).saving_toward_a_target?

    category.budgets.sum(0.to_d) { |budget| budget.steady_ask(user, today: today) }
  end

  def spent_this_period(category) = holder_spending_this_period.fetch(category.id, 0.to_d)

  # ** WHAT EACH BUDGETED CATEGORY SPENT INSIDE THIS PERIOD, IN ONE GROUPED QUERY — AND NO NEW DATE
  # ARITHMETIC ANYWHERE IN IT (spec §8: no ledger arithmetic beyond composing existing readers). **
  # Two shared readers, composed, and neither is re-spelled here:
  #
  #   WHICH CATEGORY AN EXPENSE DRAINS — `CategoryLedger::ENTRY_CATEGORY_ID`, the app's ONE
  #     statement of that rule (funded-since gate and the owner's-day timezone boundary included).
  #     It is the same expression `CategoryLedger#grouped_entries` groups the ledger's own expense
  #     term by, so this figure and `HoldingCalculator#balance` cannot count different rows.
  #   WHERE THE PERIOD STARTS AND ENDS — `User#period_datetimes_containing`, the app's ONE reader of
  #     that, with the widening to the closing day's own midnight that `entries.date` being a
  #     DATETIME requires. `DistributionClock` and `AllocationCommitter` bound themselves by the
  #     same call, so Home, the clock and the write path cannot disagree about which period this is.
  #
  # THE WINDOW IS TAKEN UNGATED, unlike `#period_range`. That reader refuses the calendar-month
  # fallback because the hero PRINTS the boundary and "Aug 1 – Aug 31" would state one the user
  # never set; nothing here prints a boundary, and a month is the same fallback `Budget#steady_ask`
  # normalises an undeclared user's rules against — so the two halves of every bar describe one
  # period whether or not the user has declared it.
  #
  # `categories.empty?` GUARDED because the fill order is empty for every user on their first day,
  # and an `IN ()` list is a query with nothing to ask.
  def holder_spending_this_period
    @holder_spending_this_period ||=
      if categories.empty?
        {}
      else
        period_entries
          .where("#{CategoryLedger::ENTRY_CATEGORY_ID} IN (:ids)", ids: categories.map(&:id))
          .group(CategoryLedger::ENTRY_CATEGORY_ID).sum(:amount).transform_values(&:to_d)
      end
  end

  # THE SAME PARTITION, READ FOR ITS OTHER ANSWER: spending inside this period that drains no
  # category at all — `CategoryLedger#unfunded_spending`'s rule, split by the category that NAMES
  # the entry instead of summed into one figure. Together the two queries cover every expense entry
  # in the window exactly once, which is the same partition §2 rests on one level up.
  #
  # HOLDERS ARE REJECTED AFTERWARD RATHER THAN IN SQL, and the reject is load-bearing rather than
  # defensive: a category funded PART-WAY THROUGH this period drains available for the receipts
  # dated before its `funded_since` and itself for the ones after, so without this it would be
  # listed twice — once with a bar and once as unbudgeted. It is already in the list above, with the
  # bar; its pre-funding spending belongs to available, which the hero's figures already carry.
  def unbudgeted_spending_this_period
    @unbudgeted_spending_this_period ||= begin
      holders = categories.to_set(&:id)

      period_entries.where("#{CategoryLedger::ENTRY_CATEGORY_ID} IS NULL")
        .group("categories.id").sum(:amount)
        .except(*holders)
        .transform_values(&:to_d)
    end
  end

  # THE SCOPE BOTH GROUPED READS START FROM. `Entry.expenses` already carries the `item: :category`
  # join both the constant and the `categories.user_id` filter need; `ENTRY_CATEGORY_JOINS` brings
  # the aliased owner whose timezone the constant's day-boundary comparison re-zones through.
  def period_entries
    Entry.expenses
      .joins(*CategoryLedger::ENTRY_CATEGORY_JOINS)
      .where(categories: { user_id: user.id }, date: user.period_datetimes_containing(today))
  end

  # THE UNCAPPED HALF OF `#free_to_spend` — money with no job once the rest of this period's plan is
  # paid for. Private and spelled once because ALL THREE public readers need it: #free_to_spend
  # takes the `min` of it and the pot, #free_cap_bound? asks which of the two that was,
  # #plan_outruns_the_money? asks for its sign, and a second spelling of the subtraction is a card
  # whose figure and whose subline could describe different arithmetic.
  #
  # Not memoised: both operands already are (`#available` on the proposal, `#remaining_plan` on the
  # rows), so this is a subtraction of two memos and the card asks for it twice.
  def unspoken_for = available - remaining_plan

  # ONE PHYSICAL LEDGER FOR THE SCREEN. Lazy, like everything else here: Home writes nothing, so
  # there is no write for the snapshot to fall the wrong side of, and the laziness is only so a
  # presenter built and never rendered costs nothing.
  def account_ledger = @account_ledger ||= AccountLedger.new(user)

  # ONE PURPOSE LEDGER FOR THE SCREEN, over exactly the categories this screen asks about, plus
  # `user:` so `#available` is answerable for a user whose holder set is EMPTY — which is every user
  # on their first day, and exactly the user Home renders for first. Read off the categories alone,
  # CategoryLedger raises `NoSingleOwner` rather than answering.
  def ledger = @ledger ||= CategoryLedger.new(categories, user: user)

  # THE LATCH ITSELF, memoised: #awaiting_opening_balance? is asked once per account this screen
  # renders, and every account but main gets a `false` from the first half of that predicate before
  # this one is ever reached.
  #
  # `Category.opening_balance`, NOT a hand-rolled `exists?(name: …)`: that scope is CASE-INSENSITIVE,
  # matching `Category`'s own uniqueness validation, so a user who already has a category spelled
  # "opening balance" reads as latched here exactly as it would refuse a second `create!` — one rule,
  # asked the one place it lives.
  #
  # `defined?` rather than `||=`: the open latch (no such category yet) is `false`, the common case
  # for as long as onboarding is unfinished, and `||=` would re-run the EXISTS on every hit.
  def opening_balance_recorded?
    return @opening_balance_recorded if defined?(@opening_balance_recorded)

    @opening_balance_recorded = user.categories.opening_balance.exists?
  end

  # ONE CLOCK FOR THE SCREEN, on its category arm — no account list, because there is one root and
  # one distribution per period to compare against.
  def distribution_clock
    @distribution_clock ||= DistributionClock.new(user: user, today: today)
  end

  def compute_fix_candidates(category)
    amount = fix_amount_for(category)
    return [] unless amount.positive?

    fundable_by(category).select { |party| free_amount_for(party) >= amount }
  end

  # AVAILABLE, THEN THE HOLDERS IN FILL ORDER — `ReallocationPresenter#sources`' order, assembled
  # from the list Home already holds rather than re-queried.
  def parties = @parties ||= [ReallocationPresenter::ROOT, *categories]

  def fundable_by(category)
    parties.reject do |party|
      next true if party == category

      !root?(party) && status_for(party).needs_attention?
    end
  end

  def root?(party) = party.is_a?(ReallocationPresenter::Root)

  # AVAILABLE'S FREE MONEY IS `CategoryLedger#available`, NOT THIS SCREEN'S `#available`, and the
  # difference is the sweep. The headline is post-sweep because it describes the distribution this
  # screen is offering; a hand move happens NOW, out of money that is actually unclaimed today, which
  # is what the reallocation screen would then show and refuse against (`Allocation#source_must_hold_
  # it` reads the same figure). Offering a fix out of money that is still sitting in another category
  # would propose a move the write path rejects.
  def free_amount_for(party)
    return ledger.available if root?(party)

    (@free_amounts ||= {})[party.id] ||= calculator_for(party).free_amount
  end

  # ONE ReallocationPresenter FOR ONE ROW, and #source_for rather than #sources: the list reader would
  # build a Candidate — with its damage, four calculators deep — for every holder category the user
  # has, on a screen that renders one button.
  def build_fix(category)
    amount = fix_amount_for(category)
    return Fix.new(category: category, amount: amount, candidate: nil, covered: true) if covered_by_waterfall?(category)

    source = fix_candidates_for(category).first
    Fix.new(
      category: category,
      amount: amount,
      candidate: source && damage_reader(category, source, amount).source_for(source),
      covered: false
    )
  end

  # WHETHER THE NEXT DISTRIBUTION ALREADY SOLVES THIS, so the band does not talk the user into a move
  # they do not need to make. Ruling 4 said do not offer money to a bill that already has it; this is
  # the same principle one step out — do not offer money to a bill that is ABOUT to have it. The move
  # is not free: the source loses money it was holding for its own rule.
  #
  # READ OFF #waterfall, WHICH IS THE PROPOSAL THIS SCREEN IS ALREADY DERIVED FROM, and deliberately
  # not a fresh AllocationCalculator. Home no longer RENDERS the waterfall — the band that drew it
  # died with the attention band (answers-first §1: Home stops showing the system) — but the same
  # rows are still `#remaining_plan`'s and `#undistributed_period?`'s, and the sentence below is a
  # promise about the very distribution the strip's own button opens. A second reader here could
  # say "the next distribution funds this in full" beside a Distribute screen that funds none of it.
  #
  # NO ROW MEANS NOT COVERED, which is the safe direction: a category asking for nothing is rejected
  # from the rows, and that category is already handled one branch earlier by
  # HoldingStatus#funding_gap.
  def covered_by_waterfall?(category)
    row = waterfall_rows_by_category[category.id]

    row.present? && row.short.zero?
  end

  def waterfall_rows_by_category
    @waterfall_rows_by_category ||= waterfall.index_by { |row| row.category.id }
  end

  # THE SCREEN'S OWN LEDGER GOES WITH IT, and that is the whole of what `ledger:` is for. One of these
  # is built per problem row (see #build_fix), and each would otherwise open a CategoryLedger of its
  # own over the same holder categories, at the same moment, with no `as_of` on either.
  #
  # SHARING IS SAFE HERE BECAUSE HOME WRITES NOTHING. A ledger is a snapshot memoised at its first
  # read, so handing one across a write would hand out figures from before it; this presenter renders
  # a GET and the fix buttons are links.
  #
  # The two sets are identical by construction: both are `Category.in_fill_order` over the same user.
  # It would not cost accuracy if one were not — #terms_for hands back nil for a category the ledger
  # does not know and the calculator then runs its own aggregates — but #holding_of would raise, so
  # "identical" is worth stating rather than relying on.
  def damage_reader(category, source, amount)
    ReallocationPresenter.new(
      user: user, to_category: category, from_category: source, amount: amount, today: today, ledger: ledger
    )
  end

  # THE PROPOSAL THIS SCREEN RENDERS, AND IT IS THE OBJECT THE DISTRIBUTE BUTTON ACTS ON.
  #
  # HOME USED TO KEEP A HAND-COPIED WATERFALL — `#fill_waterfall`, plus `#required_for` and
  # `#ask_calculator_for` to feed it, plus `#total_swept` and an `available` expression, all of them
  # transcriptions of `AllocationCalculator`. They agreed, and they agreed by being watched: five
  # cross-screen pins in `spec/presenters/home_presenter_spec.rb` and `spec/system/home/fixes_spec.rb`
  # exist for no other reason than to catch the day they stopped. Consuming the class removes the
  # copy rather than the check — those pins now compare an object with itself and stay green, which
  # is what "structurally cannot drift" looks like from a spec's side.
  #
  # THE COST IS ONE EXTRA `CategoryLedger`, AND IT IS THE HONEST PRICE. This presenter keeps its own
  # ledger for the statuses, the free-money reads and the `ReallocationPresenter`s it builds; the
  # proposal builds a second over the same categories at the same moment, because `#share_ledger` is
  # `protected` — only another AllocationCalculator may hand one over, deliberately, since only
  # another instance can honestly promise it was constructed after the last write. Widening that
  # surface to save four grouped queries would trade the guarantee for the saving, and Home writes
  # nothing, so the two ledgers cannot disagree about anything. The alternative — keeping the copy —
  # costs the same queries AND the drift.
  #
  # NO `overrides:`: Home renders the proposal as it stands. The overrides are the distribution
  # screen's, where there are boxes to type them into.
  def proposal = @proposal ||= AllocationCalculator.new(user: user, today: today)

  # THE PLAIN CALCULATOR — what a category holds right now. #period_closed? and #free_amount_for
  # both ask it, once per rendered category, and each calculator is a set of aggregate queries plus
  # a per-rule sort, so the memo is what stops the screen building two for one category.
  #
  # THE AGGREGATES ARE ONE LEDGER'S SHARE OF FOUR. The memo only ever stopped this screen building
  # the same calculator twice; the ledger is what stops each category paying four aggregates of its
  # own.
  def calculator_for(category)
    (@calculators ||= {})[category.id] ||= category.holding_calculator(today: today, terms: ledger.terms_for(category))
  end

  # Keyed by the record, not by id: an unsaved rule has no id, and `nil` as a cache key would hand
  # every such rule the first one's calculator.
  def calculator_for_budget(budget)
    (@budget_calculators ||= {})[budget] ||= budget.calculator(today: today)
  end
end
