# frozen_string_literal: true

require "rails_helper"

# THE §6 IMPACT CARD'S SERVER HALF. The card answers "can I afford this" beside the amount box, and
# everything below is the half the browser cannot get wrong on its own: whether any rule claims this
# spending at all, what the category claims, what the bar measures against, and — on edit — what the
# claim has already counted.
#
# ** CONVERTED ONTO COMPUTED CLAIMS (computed-claims spec §3). ** Every fixture used to plant an
# `Allocation` — money MOVED into a category — and read the holding back. Nothing moves (§5), so
# every `fund(...)` in this file is gone and the money is written the way the model actually puts it
# there: a rule that claims a rate, a rule that accrues toward a target, or a dated adjustment
# (§3.3). THE FIGURES ARE THE SAME FIGURES wherever the shape allows it — the same $240 claimed, the
# same $300-a-period rule, the same $185 left — re-derived from §3's formulas rather than carried:
#
#   * `$240 held` became `$300 a period with $60 of it spent` — `claim = max(0, 300 − 60)`.
#   * `$600 in a fund` became `a $600-a-period rule on a $2,400 target, one period walked` —
#     `built_up = min(0 + 600, 2400)`.
#   * `$600 held against a $300 claim` became `$300 a period with a +$300 adjustment` —
#     `claim = max(0, 300 + 300 − 0)`, which is §3.3's delta doing what an allocation used to.
#
# ── DELETED, EACH BECAUSE THE SHAPE IT ASSERTED CANNOT HAPPEN NOW:
#
#   * "writes a negative holding signed, so the browser subtracts from the right number" — a holding
#     was a signed sum and could go below zero; §3.1 and §3.2 both clamp a claim at zero, so
#     `#balance` has no negative to sign. CONVERTED rather than dropped: "never writes a negative
#     figure at all" asserts the clamp in its place, on the same overspent fixture.
#   * "is still a goal once a refill rule fills it" — it planted a goal with NO rule and then added
#     one, to show the classification did not change. A category with no rule claims nothing at all
#     now (every claim comes from a rule, §3.3), and since rules-own-the-budget §5 it is not a fund
#     either: the classifier IS the rule. Both facts survive as their own examples, "is not a fund
#     while nothing builds up here" and "is a fund on the one reader every screen now asks".
#
# ── NEW, AND EACH PINS ONE HALF OF #balance's GIVE-BACK RULING (see that method's comment):
#   "gives the whole entry back through the clamp when the envelope is overspent", "gives nothing
#   back for a receipt from a period the rate claim never saw", "caps the give-back at what the
#   rules could hold", "gives nothing back when an accruing rule is spent past what it had".
#
# EVERY EXPECTED FIGURE IS A PLANTED LITERAL and both sides of every equality are independent. A
# claim is asserted against the arithmetic §3 does on the rules and entries this file wrote, spelled
# out, and never against another reading of the same objects.
#
# EVERY FIXTURE IS BIWEEKLY and the anchor is a fixed date, so a monthly rule's amount and its
# per-period claim are never the same number — the mixed-unit slip has struck five times on this
# branch and a suite of per-period rules would pass with it in place. `today:` is passed explicitly
# rather than travelled to, so no example reads `Date.current` inside a frozen clock.
RSpec.describe EntryImpactPresenter do
  # Feb 6 is the anchor AND the day, so the boundaries are Feb 6 and Feb 20 and the period the card
  # reports runs to Feb 19 — the spec's own mockup date. The period before it is Jan 23 – Feb 5,
  # which is what the back-dated example below reaches into.
  let(:today) { Date.new(2026, 2, 6) }
  let(:user) do
    create(:user, period_cadence: :biweekly, period_anchor_date: Date.new(2026, 2, 6), typical_income: 2_400)
  end
  let(:checking) { create(:pool, :account, user: user, name: "Checking") }

  # THE DAY THE CATEGORY STARTED HOLDING MONEY, a LITERAL rather than `1.year.ago`: this file's
  # clock is fixed at Feb 2026, and a wall-clock funding date would slide past it in a real year
  # (CLAUDE.md's third flake cause). Every entry below is dated Feb 6, comfortably after it.
  let(:funded_since) { Date.new(2025, 1, 1) }
  let(:groceries) do
    create(:category, :expense, user: user, name: "Groceries", funded_since: funded_since)
  end

  # ** THE DAY AN ACCRUING RULE WAS BORN, AND IT IS NOT BOOKKEEPING (§3.2, Henry's ruling of
  # 2026-09-03). ** A rule accrues from the LATER of its category's funding date and its own
  # creation, so a rule the factory writes a moment ago — at the real wall clock, months after this
  # file's `today` — walks NO periods at all and holds nothing. Born on the day the current period
  # opens, every accruing fixture here walks exactly ONE period and its built-up is one period's
  # accrual, which is what makes the literals below readable.
  #
  # IRRELEVANT TO A RATE RULE, which walks only the period containing `today` whatever its birthday,
  # and passed anyway so no fixture depends on which shape it happens to be.
  def born = Time.utc(2026, 2, 6, 9, 0)

  def spend(category, amount, on: today)
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # $X EVERY PERIOD — a rate rule, so its own amount IS its per-period claim (§3.1), and the claim it
  # produces is that amount less whatever has been spent on the category this period.
  def rate(category, amount)
    create(:budget, :per_period_rate, category: category, amount: amount, created_at: born)
  end

  # $X A MONTH — its per-period claim under a biweekly user is `amount * 12 / 26`, nothing like its
  # own amount. This is the shape the bar's denominator lives or dies on.
  def monthly_rate(category, amount)
    create(:budget, :rate, category: category, amount: amount, created_at: born)
  end

  # A ONE-TIME BILL — an anchor and no interval (`Budget#cadence`'s `:one_off`). Its standing cost is
  # `ClaimCalculator#standing_ask`: the amount over the periods from the accrual start's period
  # through the one the anchor falls in, which is the only shape whose denominator this card cannot
  # read off the rule's own columns.
  def one_off(category, amount, anchor:)
    create(
      :budget,
      category: category,
      amount: amount,
      interval_months: nil,
      anchor_date: anchor,
      created_at: born
    )
  end

  # A DATED, SIGNED DELTA ON A RULE'S ACCRUAL (§3.3). Dated at `today` by default, because the delta
  # only counts in the period it falls in and this file's clock is not the wall clock.
  def adjust(rule, amount, on: today)
    create(:adjustment, rule: rule, amount: amount, date: on)
  end

  # A CATEGORY WHOSE MONEY BUILDS UP, WITH THE FIGURE ON THE RULE (rules-own-the-budget spec §5).
  # `accrues:` is the per-period rule that feeds it — every claim comes from a rule (§3.3).
  #
  # ** THE CATEGORY'S OWN `target_amount` IS NO LONGER WRITTEN, AND THAT IS THE POINT OF THIS TASK.
  # ** The helper used to set the same number on both records because the card's `#goal?` and
  # `#goal_target` read the CATEGORY while the walk read the rule. Both readers are the rule's now
  # (`#building?`, `#building_target`), so a fixture still writing the column would let a reader
  # that had quietly stayed behind go on passing — and the column is dropped by Task 4 anyway.
  def fund(name, target:, accrues: 0)
    category = create(:category, :expense, user: user, name: name, funded_since: funded_since)
    building(category, accrues, target: target) if accrues.positive?
    category
  end

  # THE RULE A FUND ACCRUES BY: per-period, unspent money builds up, capped at the rule's figure.
  def building(category, amount, target:)
    create(:budget, :capped, category: category, amount: amount, target_amount: target, created_at: born)
  end

  def present(category, amount: nil, entry: nil, on: today)
    described_class.new(user: user, category: category, amount: amount, entry: entry, today: on)
  end

  describe "the envelope card" do
    # $300 a period with $60 of it already spent: `claim = max(0, 300 − 60)` = $240, the mockup's
    # own figure, planted the way the model actually produces it.
    before do
      rate(groceries, 300)
      spend(groceries, 60)
    end

    it "prints what the category claims and what the typed amount would leave", :aggregate_failures do
      impact = present(groceries, amount: "55")

      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance_after).to eq(BigDecimal("185"))
      expect(impact.holding).to eq(groceries)
      expect(impact.noun).to eq("envelope")
    end

    it "leaves the claim where it is when nothing has been typed", :aggregate_failures do
      impact = present(groceries)

      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance_after).to eq(BigDecimal("240"))
      expect(impact.balance_after).not_to eq(BigDecimal("185"))
    end

    # THE FIGURE IS `Category#claim`'S, and the two are asserted against each other here so a
    # presenter that quietly started summing rules of its own would fail rather than agree with
    # itself. The literal is what keeps this from being `x == x`.
    it "reads the category's own claim and not a second sum of its rules", :aggregate_failures do
      expect(groceries.claim(today: today)).to eq(BigDecimal("240"))
      expect(present(groceries).balance).to eq(groceries.claim(today: today))
    end

    it "answers in BigDecimal, whatever the amount arrived as", :aggregate_failures do
      expect(present(groceries, amount: "55").balance_after).to be_a(BigDecimal)
      expect(present(groceries).balance_after).to be_a(BigDecimal)
      expect(present(groceries, amount: 55).amount).to be_a(BigDecimal)
      expect(present(groceries).denominator).to be_a(BigDecimal)
    end

    # `#direction` IS GONE (plan 3, task 5) — with no savings category there is one sign, so the
    # method was the constant -1 and `data-direction` was a constant handed to the browser. The
    # claim it carried is asserted here as arithmetic instead, both ways.
    it "subtracts an expense and never adds it", :aggregate_failures do
      expect(present(groceries, amount: "55").balance_after).to eq(BigDecimal("185"))
      expect(present(groceries, amount: "55").balance_after).not_to eq(BigDecimal("295"))
      expect(present(groceries, amount: "55")).not_to respond_to(:direction)
    end

    it "runs the bar to the day before the next period boundary" do
      expect(present(groceries).period_ends_on).to eq(Date.new(2026, 2, 19))
    end

    it "states no date at all for a user who has declared no period", :aggregate_failures do
      user.update!(period_cadence: nil, period_anchor_date: nil)

      expect(present(groceries).period_ends_on).to be_nil
      expect(present(groceries).balance).to be_a(BigDecimal)
    end

    # `#pool` IS GONE with `Category#effective_pool`, which resolved which POOL a category's spending
    # reached. `#calculator` went with `HoldingCalculator` (computed-claims §6): there is no object
    # holding a balance for this card to read one off. The question is what the RULES claim, and the
    # answer comes from the category itself.
    it "has neither a pool nor a holding calculator to name", :aggregate_failures do
      expect(present(groceries)).not_to respond_to(:pool)
      expect(present(groceries)).not_to respond_to(:calculator)
    end
  end

  describe "the bar" do
    it "measures what would be left against what the category claims from a period", :aggregate_failures do
      rate(groceries, 300)
      spend(groceries, 60)

      # 185 of a 300-a-period claim.
      expect(present(groceries, amount: "55").denominator).to eq(BigDecimal("300"))
      expect(present(groceries, amount: "55").bar_percent).to eq(62)
      expect(present(groceries, amount: "180").bar_percent).to eq(20)
    end

    it "claims the PER-PERIOD share of a monthly rule and not its sticker price", :aggregate_failures do
      monthly_rate(groceries, 1_500)

      # $1,500 a month under a biweekly period is 1500 * 12 / 26.
      expect(present(groceries).denominator).to eq(BigDecimal("692.31"))
      expect(present(groceries).denominator).not_to eq(BigDecimal("1500"))
    end

    # ** A CLAIM ABOVE THE RULE'S OWN RATE IS AN ADJUSTMENT'S DOING (§3.3), and that is how a
    # category comes to hold more than it claims from a period now that nothing is allocated in.
    # `claim = max(0, 300 + 300 − 0)` = $600 against a $300 denominator.
    it "clamps full rather than overflowing when the category claims more than a period's rate", :aggregate_failures do
      adjust(rate(groceries, 300), 300)

      expect(present(groceries).balance).to eq(BigDecimal("600"))
      expect(present(groceries).bar_percent).to eq(100)
      expect(present(groceries, amount: "450").bar_percent).to eq(50)
    end

    it "clamps empty rather than going negative when the category is overdrawn", :aggregate_failures do
      rate(groceries, 300)
      spend(groceries, 60)

      expect(present(groceries, amount: "400").balance_after).to eq(BigDecimal("-160"))
      expect(present(groceries, amount: "400").bar_percent).to eq(0)
    end

    # ** A CATEGORY WITH NO RULES CLAIMS NOTHING, HOWEVER MUCH HAS BEEN SPENT AGAINST IT (§3.4). **
    # It used to hold whatever had been allocated in, which is why this example planted $240 and
    # asserted it; every claim comes from a rule now, so the honest figure is zero and there is
    # still no bar — an empty grey track beside a real figure would say "nothing left" an inch
    # under a figure saying otherwise.
    #
    # SINCE FIX ROUND 1 (M2) THERE IS NO CARD FOR THE BAR TO BE MISSING FROM: this category is
    # UNBUDGETED, so the whole figures block is gated off and the honest sentence is what renders.
    # The bar's own arithmetic is asserted anyway, because `#bar_fraction` is public and divides.
    it "has no bar at all, and does not divide, on a category with no rules on it", :aggregate_failures do
      spend(groceries, 60)

      expect(present(groceries).unbudgeted?).to be(true)
      expect(present(groceries).balance).to eq(0)
      expect(present(groceries).bar?).to be(false)
      expect(present(groceries).denominator).to eq(0)
      expect(present(groceries).bar_percent).to eq(0)
    end

    it "has one the moment the category has something to claim", :aggregate_failures do
      rate(groceries, 300)
      spend(groceries, 60)

      expect(present(groceries).bar?).to be(true)
      expect(present(groceries).bar_percent).to eq(80)
    end

    it "has none on a card whose category claims nothing at all" do
      unfunded = create(:category, :expense, user: user, name: "Shopping")

      expect(present(unfunded).bar?).to be(false)
    end

    # ** A SETTLED ONE-TIME BILL STILL GIVES THE BAR SOMETHING TO MEASURE AGAINST (fix wave 2 —
    # LOW-2). ** The denominator is `Σ ClaimCalculator#standing_ask`, and for one wave it was §3.2's
    # catch-up share — which is ZERO once a one-off has been paid — so the track under an envelope
    # that had drawn one all along simply stopped rendering the afternoon the bill cleared. $600 due
    # Mar 6, born Feb 6: three biweekly periods (Feb 6, Feb 20, Mar 6), so $200 a period whatever
    # has been spent. The $0 is asserted as an absence so a denominator that fell back to zero
    # cannot pass.
    it "draws a bar for a category whose only rule is a one-time bill already paid", :aggregate_failures do
      repairs = create(:category, :expense, user: user, name: "Repairs", funded_since: funded_since)
      one_off(repairs, 600, anchor: today + 28.days)
      spend(repairs, 600)
      card = present(repairs)

      expect(card.balance).to eq(0)
      expect(card.denominator).to eq(BigDecimal("200"))
      expect(card.denominator).not_to eq(0)
      expect(card.bar?).to be(true)
    end
  end

  describe "the figures the browser re-reads" do
    it "writes four-figure money without a thousands separator", :aggregate_failures do
      # `claim = max(0, 1200 + 300 − 0)` = $1,500 against a $1,200-a-period denominator.
      adjust(rate(groceries, 1_200), 300)

      expect(present(groceries).balance_param).to eq("1500.00")
      expect(present(groceries).denominator_param).to eq("1200.00")
      expect(present(groceries).balance_param).not_to include(",")
      expect(present(groceries).denominator_param).not_to include(",")
    end

    # ** THE SUCCESSOR TO "writes a negative holding signed". ** A holding could go below zero and
    # the browser had to be handed the sign; §3.1 clamps a rate claim at `max(0, …)`, so $360 of
    # spending against a $300 rule leaves $0 and not -$60. The MINUS still reaches the user — it is
    # the right-hand figure, which #balance_after computes unclamped — and this is the left one.
    it "never writes a negative figure, because a claim is clamped at zero", :aggregate_failures do
      rate(groceries, 300)
      spend(groceries, 360)

      expect(present(groceries).balance_param).to eq("0.00")
      expect(present(groceries).balance_param).not_to eq("-60.00")
      expect(present(groceries, amount: "10").balance_after).to eq(BigDecimal("-10"))
    end
  end

  describe "overdrawing" do
    # $300 a period with $260 spent: `claim = max(0, 300 − 260)` = $40, where $40 used to be
    # allocated in.
    before do
      rate(groceries, 300)
      spend(groceries, 260)
    end

    it "goes negative and says so", :aggregate_failures do
      impact = present(groceries, amount: "55")

      expect(impact.balance_after).to eq(BigDecimal("-15"))
      expect(impact.overdrawn?).to be(true)
    end

    it "is not overdrawn by an amount the category covers", :aggregate_failures do
      impact = present(groceries, amount: "25")

      expect(impact.balance_after).to eq(BigDecimal("15"))
      expect(impact.overdrawn?).to be(false)
    end

    it "reads level, not overdrawn, when the category is spent to the penny", :aggregate_failures do
      impact = present(groceries, amount: "40")

      expect(impact.balance_after).to eq(0)
      expect(impact.overdrawn?).to be(false)
    end
  end

  describe "editing an entry the claim has already counted" do
    # $60 of other spending plus the $45 being edited: `claim = max(0, 300 − 105)` = $195, and the
    # card must say $240 — the world WITHOUT this entry, which is `195 + 45`.
    let!(:existing) { spend(groceries, 45) }

    before do
      rate(groceries, 300)
      spend(groceries, 60)
    end

    it "shows the world as if this entry were being decided now", :aggregate_failures do
      impact = present(groceries, amount: "45", entry: existing)

      expect(groceries.claim(today: today)).to eq(BigDecimal("195"))
      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance_after).to eq(BigDecimal("195"))
    end

    # The same $45 typed as a NEW entry lands on different figures — which is the whole point of the
    # exclusion, and the pair is asserted together so neither can quietly become the other.
    it "differs from the same amount logged as a new entry", :aggregate_failures do
      creating = present(groceries, amount: "45")

      expect(creating.balance).to eq(BigDecimal("195"))
      expect(creating.balance_after).to eq(BigDecimal("150"))
    end

    it "moves the right-hand figure as the edited amount changes", :aggregate_failures do
      expect(present(groceries, amount: "100", entry: existing).balance_after).to eq(BigDecimal("140"))
      expect(present(groceries, amount: "10", entry: existing).balance_after).to eq(BigDecimal("230"))
    end

    # RE-CATEGORISING: the entry's money comes off Groceries' claim, so Dining Out must not be
    # credited with it.
    it "excludes nothing from a category the entry's money does not drain", :aggregate_failures do
      dining = create(:category, :expense, user: user, name: "Dining Out", funded_since: funded_since)
      rate(dining, 100)

      impact = present(dining, amount: "45", entry: existing)

      expect(impact.balance).to eq(BigDecimal("100"))
      expect(impact.balance_after).to eq(BigDecimal("55"))
    end

    # THE DATE IS THE SECOND HALF OF THE SAME TEST, and it is the re-anchored start-date rule (§4).
    # An entry dated BEFORE its category's `funded_since` moves no claim at all — the ledger's own
    # gate keeps it out of every lane — so there is nothing to give back and the card falls to the
    # honest arm, which is about the day the ENTRY is about.
    it "excludes nothing for an entry dated before the category started holding money", :aggregate_failures do
      early = spend(groceries, 45, on: funded_since - 1.day)

      impact = present(groceries, amount: "45", entry: early)

      expect(impact.unbudgeted?).to be(true)
      expect(impact.figures?).to be(false)
    end

    # AN EXPENSE ALREADY COUNTED AGAINST A FUND, re-read on the edit form. Spending from a fund is
    # still spending against a fund, and the give-back works the same way there.
    #
    # PLANTED: a $600-a-period rule on a $2,400 target, born as the period opened, so the walk
    # visits ONE period — `built_up = min(0 + 600, 2400) − 150` = $450. Without this entry: $600.
    it "gives back an expense already counted against a fund rather than spending it twice", :aggregate_failures do
      vacation = fund("Vacation", target: 2_400, accrues: 600)
      spent = spend(vacation, 150)

      impact = present(vacation, amount: "150", entry: spent)

      expect(vacation.claim(today: today)).to eq(BigDecimal("450"))
      expect(impact.balance).to eq(BigDecimal("600"))
      expect(impact.balance_after).to eq(BigDecimal("450"))
    end
  end

  # ** THE GIVE-BACK'S OWN RULING (see EntryImpactPresenter#balance). ** A holding was a signed sum
  # and adding an entry back to it was exactly invertible; a claim is clamped, at zero by §3.1/§3.2
  # and at the target by §3.2, and a clamp is not invertible. Each example below is one arm of the
  # ruling with the arithmetic written out, and each asserts the figure the naive give-back would
  # have produced as well as the right one, so an implementation that reverted could not pass.
  describe "the give-back through a clamp" do
    it "gives the whole entry back through the clamp when the envelope is overspent", :aggregate_failures do
      rate(groceries, 300)
      spend(groceries, 60)
      overdrew = spend(groceries, 300)

      impact = present(groceries, amount: "300", entry: overdrew)

      # The claim itself is clamped flat: `max(0, 300 − 360)` = $0. The give-back is applied to the
      # figure BEFORE that clamp — `max(0, −60 + 300)` = $240 — which is what the envelope had
      # before this receipt, and $240 → −$60 is what the receipt does to it.
      expect(groceries.claim(today: today)).to eq(0)
      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance_after).to eq(BigDecimal("-60"))
      # Adding back AFTER the clamp would have said $300, an envelope that never held that much.
      expect(impact.balance).not_to eq(BigDecimal("300"))
    end

    # ** A RATE CLAIM IS USE-IT-OR-LOSE-IT AND SEES ONE PERIOD (§3.1). ** Feb 5 is the last day of
    # the period before this one, so the $45 is not in the figure at all and there is nothing of it
    # to give back. Under the old cumulative holding it was, which is why this gate is new.
    it "gives nothing back for a receipt from a period the rate claim never saw", :aggregate_failures do
      rate(groceries, 300)
      spend(groceries, 60)
      last_period = spend(groceries, 45, on: today - 1)

      impact = present(groceries, amount: "45", entry: last_period)

      expect(groceries.claim(today: today)).to eq(BigDecimal("240"))
      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance).not_to eq(BigDecimal("285"))
    end

    # ** A RECEIPT DATED LATER THIS PERIOD IS IN THE CLAIM, AND WAS SUBTRACTED TWICE (fix wave —
    # MED-1). ** The period runs Feb 6 – Feb 19 and `today` is Feb 6, so Feb 10 is four days out and
    # squarely inside it. `ClaimCalculator#spent_within` is `period.cover?(day)` with NO today bound,
    # so the claim already counts the $50: `max(0, 300 − 50)` = $250, asserted below. The card asked
    # `#countable_span` — which closes at TODAY because it answers where a typed ADJUSTMENT may be
    # dated — decided the claim had not counted it, gave nothing back, and printed $250 for a world
    # that already had the entry in it. Editing it to $60 then read $190.
    #
    # THE TRUTH IS $300 AND $240, and both wrong figures are asserted alongside so a revert cannot
    # pass. A future-dated entry inside the period is an ordinary thing to type: a bill paid in
    # advance, a receipt logged for the weekend.
    it "gives back an entry dated later in the same period", :aggregate_failures do
      rate(groceries, 300)
      later = spend(groceries, 50, on: Date.new(2026, 2, 10))

      impact = present(groceries, amount: "60", entry: later)

      expect(groceries.claim(today: today)).to eq(BigDecimal("250"))
      expect(impact.balance).to eq(BigDecimal("300"))
      expect(impact.balance).not_to eq(BigDecimal("250"))
      expect(impact.balance_after).to eq(BigDecimal("240"))
      expect(impact.balance_after).not_to eq(BigDecimal("190"))
    end

    # THE OTHER DIRECTION, and it is the boundary the fix must not have swallowed: Feb 20 opens the
    # NEXT period, which a use-it-or-lose-it rate claim does not walk. Nothing of it is in the figure,
    # so nothing of it comes back and the card reads the claim unchanged.
    it "gives nothing back for a receipt dated into the next period", :aggregate_failures do
      rate(groceries, 300)
      beyond = spend(groceries, 50, on: Date.new(2026, 2, 20))

      impact = present(groceries, amount: "60", entry: beyond)

      expect(groceries.claim(today: today)).to eq(BigDecimal("300"))
      expect(impact.balance).to eq(BigDecimal("300"))
      expect(impact.balance_after).to eq(BigDecimal("240"))
    end

    # ** THE CLAMP AT THE OTHER END (§3.2: the built-up is capped at the target). ** A $600-a-period
    # rule on a $600 target, born Feb 6, with $150 spent on Feb 6, asked on Feb 20 — the second
    # period of the walk:
    #
    #   Feb 6–19  planned min(600, gap 600) = 600 · accrued min(0 + 600, 600) = 600 · spent 150 → 450
    #   Feb 20–…  planned min(600, gap 150) = 150 · accrued min(450 + 150, 600) = 600 · spent 0 → 600
    #
    # The fund has refilled to its target, so giving the old $150 back would print $750 of a $600
    # fund. The ceiling is what the rules could hold at most, and it is $600.
    it "caps the give-back at what the rules could hold", :aggregate_failures do
      vacation = fund("Vacation", target: 600, accrues: 600)
      spent = spend(vacation, 150)
      later = Date.new(2026, 2, 20)

      impact = present(vacation, amount: "150", entry: spent, on: later)

      expect(vacation.claim(today: later)).to eq(BigDecimal("600"))
      expect(impact.balance).to eq(BigDecimal("600"))
      expect(impact.balance).not_to eq(BigDecimal("750"))
      expect(impact.balance_after).to eq(BigDecimal("450"))
    end

    # ** THE ONE ARM THAT UNDERSTATES, AND IT IS THE DELIBERATE DIRECTION. ** §3.2 clamps an
    # accruing rule's built-up inside EVERY period of the walk, so the figure before that clamp is
    # gone by the time the walk returns and there is no `accrued − spent` to add the entry back to.
    # Planted: a $600-a-period rule on a $600 target with $750 spent — `min(0 + 600, 600) − 750` is
    # −$150 before the clamp and $0 after it, and `over?` is the calculator's own reader for it.
    #
    # THE TRUTH IS $600 AND THIS CARD SAYS $0. That is the cost, stated: on a card answering "can I
    # afford this", understating a fund already spent past zero is the safe direction, and the
    # alternative — adding the $750 back to a zero — would offer $750 that is provably not there.
    it "gives nothing back when an accruing rule is spent past what it had", :aggregate_failures do
      vacation = fund("Vacation", target: 600, accrues: 600)
      overdrew = spend(vacation, 750)

      impact = present(vacation, amount: "750", entry: overdrew)

      expect(vacation.claim(today: today)).to eq(0)
      expect(impact.balance).to eq(0)
      expect(impact.balance).not_to eq(BigDecimal("750"))
    end

    # ** AN UNCAPPED FUND HAS NO TARGET TO BE THE CEILING (rules-own-the-budget spec §2.1 row 2; fix
    # round 1 — MED). ** `#most_it_could_claim` read `ClaimCalculator#target` for every accruing rule
    # and that reader is NIL for a building rule naming no figure, so `BigDecimal + nil` raised a
    # TypeError on the entry form the moment a category held an emergency fund. `#ceiling_for` is
    # what answers now, and the arm it takes for this shape is `built_up + this period's rate`: the
    # most the rule COULD hold on the day the card is drawn, since nothing but this period's own
    # share can be added before the next boundary and there is no cap that could take it higher.
    #
    # BY HAND, on a $600-a-period fund born as the period opened with $150 spent on it:
    #   walk      planned 600 (uncapped: `gap` is unbounded) · accrued 600 · spent 150 → built 450
    #   ceiling   450 + 600 = 1,050
    #   balance   (pre-clamp 450 + the $150 given back).clamp(0, 1,050) = **$600.00**
    # The give-back is not clipped, which is the point: the ceiling is real and it is above the
    # figure, so the card states what the rule actually had before this receipt.
    it "gives an uncapped fund's spending back against a ceiling of its own", :aggregate_failures do
      emergency = create(:category, :expense, user: user, name: "Emergency", funded_since: funded_since)
      create(:budget, :building, category: emergency, amount: 600, created_at: born)
      drawn = spend(emergency, 150)

      impact = present(emergency, amount: "150", entry: drawn)

      expect(emergency.claim(today: today)).to eq(BigDecimal("450"))
      expect(impact.balance).to eq(BigDecimal("600"))
      expect(impact.balance_after).to eq(BigDecimal("450"))
    end
  end

  # TWO SHAPES REACH THIS CARD, AND ONE OF THEM IS A DATE. `#unbudgeted?` read
  # `pool.nil? || pool.pool_type_account?` — no envelope, or an envelope that was really an account,
  # and both meant "nothing reserves this money". Its successors are `Category#counts_spending_on?`
  # (the ledger's own rule: a category that has never been funded, and a funded one asked about a
  # day before it started holding, both leave their spending to FREE money, §2) and
  # `Category#budgeted?` (fix round 1 — M2: a category with no rule claims nothing at all, §3.4).
  describe "a category no rule claims" do
    let(:unfunded) { create(:category, :expense, user: user, name: "Shopping") }

    it "is told the truth rather than shown an envelope", :aggregate_failures do
      impact = present(unfunded, amount: "55")

      expect(impact.render?).to be(true)
      expect(impact.unbudgeted?).to be(true)
      expect(impact.figures?).to be(false)
      expect(impact.holding).to be_nil
    end

    it "cannot overdraw anything, and does not raise being asked" do
      expect(present(unfunded, amount: "55").overdrawn?).to be(false)
    end

    # THE DATED ARM, and it is the new one: this category DOES carry a rule, and this receipt still
    # comes out of free money because it predates the day the category started holding. Both
    # directions on one category, so the example is about the date and nothing else.
    it "is the same card for a receipt dated before the category started holding", :aggregate_failures do
      rate(groceries, 300)
      before_it_started = create(
        :entry,
        item: create(:item, category: groceries),
        amount: 55,
        date: funded_since - 1.day
      )

      expect(present(groceries, amount: "55").unbudgeted?).to be(false)
      expect(present(groceries, amount: "55", entry: before_it_started).unbudgeted?).to be(true)
    end

    # `#contribution?` IS GONE (plan 3, task 5). It split this card into a spending arm and a
    # contribution arm ("No goal — this contribution has nowhere to land", pointing at /pools/new);
    # only the spending arm is reachable now, so the method and the second arm went together.
    it "has no contribution arm to choose between", :aggregate_failures do
      expect(present(unfunded)).not_to respond_to(:contribution?)
      expect(present(unfunded).unbudgeted?).to be(true)
    end

    it "is not what a category with a rule gets", :aggregate_failures do
      rate(groceries, 300)

      expect(present(groceries, amount: "55").unbudgeted?).to be(false)
      expect(present(groceries, amount: "55").figures?).to be(true)
    end

    # ** THE RULE ARM (fix round 1 — M2), AND IT IS THE SHAPE THE CARD USED TO PAINT RED. **
    # Groceries here is FUNDED and carries no rule, so `#holding` is the category and the old
    # `#unbudgeted? = holding.nil?` said "budgeted": the card drew an envelope claiming $0.00, a
    # `balance_after` of −$55, `#overdrawn?` true and the danger-red overdraw notice — for a
    # category Home's "This period" was calling unbudgeted an inch away and printing `spent $X`
    # against with no bar.
    #
    # EVERY ARM OF THE ENVELOPE IS ASSERTED OFF, not just the predicate: `#figures?` is what the
    # view gates the whole figures block on, and `#overdrawn?` is what painted it.
    it "is unbudgeted when it is funded but carries no rule at all", :aggregate_failures do
      impact = present(groceries, amount: "55")

      expect(groceries.reload.counts_spending_on?(today)).to be(true)
      expect(impact.holding).to eq(groceries)
      expect(impact.unbudgeted?).to be(true)
      expect(impact.figures?).to be(false)
      expect(impact.overdrawn?).to be(false)
      expect(impact.bar?).to be(false)
    end

    # ** ONE SPELLING, SHARED WITH HOME. ** `Category#budgeted?` is what
    # `HomePresenter::PeriodRow#budgeted?` asks too, so the two screens cannot answer differently
    # about one category. Both directions on ONE category, so the example is about the rule and
    # nothing else.
    it "asks the same predicate Home's period rows ask", :aggregate_failures do
      expect(groceries.budgeted?).to be(false)
      expect(present(groceries, amount: "55").unbudgeted?).to be(true)

      rate(groceries, 300)

      expect(groceries.reload.budgeted?).to be(true)
      expect(present(groceries.reload, amount: "55").unbudgeted?).to be(false)
    end
  end

  describe "a fund" do
    # ** A FUND IS `Category#building_rule` (rules-own-the-budget spec §5/§7): the item-less rule
    # whose unspent money carries. ** It replaces `Category#saving_toward_a_target?`, which read a
    # figure on the CATEGORY — a column no claim formula consults, since `ClaimCalculator#shape`
    # answers `:building` off the rule's own `carries_over` and caps at the rule's `target_amount`.
    # The card, the categories index, the categories page and the dashboard's savings strip all read
    # the same rule, so a fund is a fund on every one of them.
    #
    # $600 of a $2,400 target: a $600-a-period building rule born as the period opened, one period
    # walked.
    let(:vacation) { fund("Vacation", target: 2_400, accrues: 600) }

    before { vacation }

    it "takes the fund shape and measures against the rule's target", :aggregate_failures do
      impact = present(vacation, amount: "150")

      expect(impact.building?).to be(true)
      expect(impact.noun).to eq("fund")
      expect(impact.balance).to eq(BigDecimal("600"))
      expect(impact.balance_after).to eq(BigDecimal("450"))
      expect(impact.building_target).to eq(BigDecimal("2400"))
    end

    it "measures its bar against the target, which no rule could ever be", :aggregate_failures do
      # 450 of 2,400. Measured against the $600-a-period rule instead, the bar would read 75% of a
      # fund that is a quarter full — which is the defect the target arm exists to fix.
      expect(present(vacation, amount: "150").denominator).to eq(BigDecimal("2400"))
      expect(present(vacation, amount: "150").bar_percent).to eq(19)
      expect(present(vacation, amount: "150").bar?).to be(true)
    end

    # BOTH DIRECTIONS ON THE SURVIVING ARM: a fund empties, and it says so in red once it is empty.
    it "goes negative and reports the overdraw like any other category", :aggregate_failures do
      impact = present(vacation, amount: "900")

      expect(impact.building?).to be(true)
      expect(impact.balance_after).to eq(BigDecimal("-300"))
      expect(impact.overdrawn?).to be(true)
    end

    # ** THE CARD READS THE RULE THE WALK READS, AND UNTIL THIS TASK IT DID NOT. ** The claim came
    # from `carries_over` + the rule's `target_amount` while the NOUN and the BAR came from
    # `categories.target_amount` — two records, one question, and after Task 4 drops the column the
    # second answer would have been nil for every fund in the app. Asserted here as the identity it
    # is: the rule the category hands back IS the rule the figures are computed from.
    it "is a fund on the one reader every screen now asks", :aggregate_failures do
      expect(vacation.reload.building_rule).to eq(vacation.budgets.sole)
      expect(present(vacation).building?).to be(true)
      expect(present(vacation).building_target).to eq(BigDecimal("2400"))
      expect(present(vacation).denominator).to eq(BigDecimal("2400"))
    end

    # ** AN UNCAPPED FUND IS STILL A FUND (rules-own-the-budget spec §2.1 row 2), AND THAT IS THE
    # SHAPE THE OLD PREDICATE COULD NOT SEE. ** `#saving_toward_a_target?` was a question about a
    # FIGURE, so an emergency fund that names none read as an envelope: the noun was wrong and the
    # trailing phrase said "left" over money the rule carries from period to period. The noun is now
    # a question about the SHAPE and only the denominator falls back — to `Σ standing_ask`, the
    # $600-a-period rule, which is the same figure an envelope's bar uses and the only honest one
    # left when there is no ceiling.
    it "keeps the fund shape when the rule names no figure", :aggregate_failures do
      vacation.budgets.sole.update!(target_amount: nil)

      expect(present(vacation.reload).building?).to be(true)
      expect(present(vacation.reload).noun).to eq("fund")
      expect(present(vacation.reload).building_target).to be_nil
      expect(present(vacation.reload).denominator).to eq(BigDecimal("600"))
    end

    # ** A CATEGORY WITH NO RULE AT ALL IS NOT A FUND, AND IT NEVER HAD BEEN ONE (fix round 1 — M2).
    # ** It claims nothing (§3.3: every claim comes from a rule), so the card has no figures to
    # print — and now it has no NOUN either, which is the change: under the old predicate a figure
    # on the category made this a "goal" whose card was suppressed by `#figures?` alone. Home calls
    # exactly this category unbudgeted, and the two agree at both readers.
    it "is not a fund while nothing builds up here", :aggregate_failures do
      empty = fund("Someday", target: 5_000)

      expect(empty.building_rule).to be_nil
      expect(present(empty).building?).to be(false)
      expect(present(empty).balance).to eq(0)
      expect(present(empty).unbudgeted?).to be(true)
      expect(present(empty).figures?).to be(false)
      expect(present(empty, amount: "150").overdrawn?).to be(false)
    end

    # ** THE FUND FED ONLY BY HAND (§2.1 row 4) IS A FUND FROM THE DAY ITS RULE IS WRITTEN. ** Amount
    # zero, capped at $5,000: it accrues only by positive adjustments, so its claim is $0.00 — and
    # unlike the ruleless category above it HAS a rule, so the card draws figures, a noun and an
    # empty track against a real ceiling. This is the row that used to be invisible: `#savings?`
    # required no rule and `#saving_toward_a_target?` required a category figure, and the shape that
    # actually holds the money satisfied neither.
    it "is a fund from the moment a hand-fed rule names it", :aggregate_failures do
      someday = create(:category, :expense, user: user, name: "Someday", funded_since: funded_since)
      create(:budget, :hand_fed, category: someday, target_amount: 5_000, created_at: born)

      impact = present(someday.reload)

      expect(impact.building?).to be(true)
      expect(impact.building_target).to eq(BigDecimal("5000"))
      expect(impact.balance).to eq(0)
      expect(impact.figures?).to be(true)
      expect(impact.bar?).to be(true)
      expect(impact.bar_percent).to eq(0)
    end

    # THE OTHER DIRECTION ON THE SHAPE: the same money, the same category, a rule that RESETS. It is
    # an envelope, and the card says "left".
    it "is not a fund where the rule's unspent money resets", :aggregate_failures do
      rate(groceries, 300)

      expect(present(groceries).building?).to be(false)
      expect(present(groceries).noun).to eq("envelope")
      expect(present(groceries).building_target).to be_nil
    end

    # AN ITEM-BACKED BUILDING RULE IS NOT THE CATEGORY'S OWN LANE (§3.1's partition): money set
    # aside for one item does not make the whole category a fund, which is why
    # `Category#building_rule` reads the ITEM-LESS rule.
    it "is not a fund where the only building rule pays one item", :aggregate_failures do
      item = create(:item, category: groceries)
      create(:budget, :capped, category: groceries, item: item, amount: 100, target_amount: 900, created_at: born)

      expect(present(groceries.reload).building?).to be(false)
      expect(present(groceries.reload).noun).to eq("envelope")
    end

    # A BUILDING RULE ON A CATEGORY THAT HOLDS NOTHING IS NOT A FUND ON THIS CARD either, because
    # `#holding` is nil — no receipt on that day can move any claim — and the card falls to the
    # honest arm rather than drawing a bar against a target nothing counts toward.
    it "is not a fund on a category that has never been funded", :aggregate_failures do
      never = create(:category, :expense, user: user, name: "Never")
      create(:budget, :capped, category: never, amount: 100, target_amount: 5_000, created_at: born)

      expect(present(never.reload).building?).to be(false)
      expect(present(never.reload).unbudgeted?).to be(true)
    end
  end

  # ** WHAT ONE CARD COSTS, AND WHY THE EDIT PATH IS PINNED SEPARATELY (fix round 1 — L5). **
  # `#balance` asks `#own_contribution` first, which reaches `#claim_calculators`; where one of its
  # three gates then closes, the give-back is zero and `#balance` falls through to `#claim`. That
  # reader used to be `holding.claim(today:)` — the MODEL's own door — which built a SECOND
  # `ClaimCalculator` per rule and asked the database again through it. It reads off the calculators
  # already in hand now.
  #
  # ** THE COST IS ONLY VISIBLE ON GATE 3, AND THE MEASUREMENT IS WHAT SAYS SO. ** A calculator is
  # lazy, so building one costs nothing on its own: gate 2 (`#countable_span`) is pure calendar
  # arithmetic, and where it closes the first set is never asked a question that queries — two
  # objects, one set of statements, before the fix and after it. Gate 3 asks `#over?`, which walks,
  # and THAT is where the second set used to pay for a second spending query. Measured on the
  # accruing-and-overspent fixture: 5 statements before, 4 after.
  #
  # STRICT EQUALITY, not `be <=`: a card that quietly starts costing one more query is exactly the
  # thing a `<=` bound waves through, and the whole point of this block is that reading the claim
  # twice is invisible to every other example in this file.
  describe "what one card costs" do
    def count_statements(&block)
      statements = 0
      counter = ->(*, payload) { statements += 1 unless payload[:name].to_s.match?(/SCHEMA|TRANSACTION/) }
      ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
      statements
    end

    # A CATEGORY NOTHING HAS TOUCHED YET, so the `budgets` association is unloaded and every
    # statement the CARD needs falls inside the measured block. The `let` instances are shared across
    # calls in one example and would answer the second measurement out of their own caches.
    #
    # CALLED OUTSIDE `#count_statements`, ALWAYS: it is a `find`, so building the presenter inside
    # the block adds a statement that is the SPEC's rather than the card's — measured, and it is
    # exactly the off-by-one this block would otherwise pin as the truth.
    def fresh(category) = user.categories.find(category.id)

    # THE ENTRY AS THE CONTROLLER HANDS IT OVER — found, with nothing preloaded. The `spend` helper
    # returns a record whose `item` is already in memory, and reading the card off THAT would hide
    # the one query the edit path genuinely costs more than the new one.
    def found(entry) = user.entries.find(entry.id)

    # THE READERS THE VIEW ASKS, in the order `entries/_impact.html.erb` asks them.
    def read_the_card(impact)
      impact.render? && impact.unbudgeted?
      impact.building? && impact.noun
      [
        impact.balance,
        impact.balance_after,
        impact.overdrawn?,
        impact.bar?,
        impact.bar_percent,
        impact.period_ends_on,
        impact.balance_param,
        impact.denominator_param
      ]
    end

    # THE NEW-ENTRY CARD, AS THREE NAMED STATEMENTS. Pinned absolutely as well as relatively: the
    # comparisons below would both pass on a card that had grown on every path at once.
    #
    #   1. `#unbudgeted?` → `Category#budgeted?`, which LOADS the association the readers after it
    #      use (see that method for the measurement behind the `load`);
    #   2-3. one `ClaimCalculator` per rule, asking its adjustments and its spending lane.
    it "costs three statements for a new entry's card" do
      rate(groceries, 300)
      spend(groceries, 60)
      card = present(fresh(groceries), amount: "45")

      expect(count_statements { read_the_card(card) }).to eq(3)
    end

    # THE ORDINARY EDIT — the give-back applies, so `#claim` is never reached at all. One statement
    # more than the new card, and it is the edited entry's own `item`, which `#counted_by_holding?`
    # reads to ask whose category it drains.
    it "costs one statement more on an edit whose give-back applies", :aggregate_failures do
      rate(groceries, 300)
      spend(groceries, 60)
      counted = found(spend(groceries, 45))
      new_card = present(fresh(groceries), amount: "45")
      edit_card = present(fresh(groceries), amount: "45", entry: counted)

      creating = count_statements { read_the_card(new_card) }
      editing = count_statements { read_the_card(edit_card) }

      expect(editing).to eq(creating + 1)
      expect(editing).to eq(4)
    end

    # ** THE PATH THAT PAID TWICE — GATE 3. ** A $600-a-period rule on a $600 target with $750 spent
    # is `over?`, so the give-back is dropped (see "gives nothing back when an accruing rule is spent
    # past what it had") and `#balance` falls through to `#claim`. `#over?` has already walked, and
    # asking the MODEL for the claim built a fresh calculator that walked again — a second spending
    # query for the same rule, on the same afternoon, for the same figure. FIVE statements before the
    # fix and four after, which is the same four the ordinary edit above costs.
    it "reads the claim once where an over-fulfilled accruing rule closes the give-back", :aggregate_failures do
      vacation = fund("Vacation", target: 600, accrues: 600)
      overdrew = found(spend(vacation, 750))
      new_card = present(fresh(vacation), amount: "750")
      edit_card = present(fresh(vacation), amount: "750", entry: overdrew)

      creating = count_statements { read_the_card(new_card) }
      editing = count_statements { read_the_card(edit_card) }

      expect(creating).to eq(3)
      expect(editing).to eq(creating + 1)
      expect(editing).to eq(4)
    end

    # ** THE BAR'S DENOMINATOR BUILT A SECOND CALCULATOR PER ONE-OFF RULE (fix wave 2 — MED-B). **
    # `#steady_claim` was `holding.budgets.sum { |b| b.steady_ask(user, today:) }`, and `#steady_ask`'s
    # one-off branch BUILDS a `ClaimCalculator` — one more per rule than `#claim_calculators` already
    # holds, which is the defect fix round 1's L5 closed on the edit path.
    #
    # MEASURED, AND THE FIGURE IS SMALLER THAN THE FINDING GUESSED. Against the wave that read
    # `#planned_this_period` this fixture costs FOUR statements and the fix takes it to three — one
    # repeat, not two, because both calculators are built over the SAME `holding.budgets` instances,
    # so the second one finds `rule.adjustments` already loaded and only its bare `Entry` spending
    # scope runs again. Against the code as it now stands the second calculator costs NOTHING
    # (`#standing_ask` reads no rows), so this example pins the count that stays right either way and
    # the ONE-DOOR argument is what the fix is really for. `#standing_ask` off the calculators in hand
    # is the same figure — asserted here too, so a cheaper card that stopped answering could not pass.
    it "costs no extra statement for a one-time bill's denominator", :aggregate_failures do
      repairs = create(:category, :expense, user: user, name: "Repairs", funded_since: funded_since)
      one_off(repairs, 600, anchor: today + 28.days)
      spend(repairs, 60)
      card = present(fresh(repairs), amount: "45")

      expect(count_statements { read_the_card(card) }).to eq(3)
      expect(card.denominator).to eq(BigDecimal("200"))
    end
  end

  describe "an income category" do
    let(:paycheck) { create(:category, user: user, name: "Paycheck", category_type: :income) }

    # §6 leaves income out on purpose: it lands in the account, and what happens to it there is the
    # hero's subject — a concept the daily screen deliberately does not introduce.
    it "gets no card at all", :aggregate_failures do
      expect(present(paycheck, amount: "2400").render?).to be(false)
      expect(present(paycheck, amount: "2400").figures?).to be(false)
      expect(present(paycheck, amount: "2400").overdrawn?).to be(false)
    end

    it "unlike an expense category, which always gets one" do
      expect(present(groceries, amount: "2400").render?).to be(true)
    end

    it "unlike no category at all, which has nothing to say yet" do
      expect(present(nil).render?).to be(false)
    end
  end

  describe "what counts as a typed amount" do
    before do
      rate(groceries, 300)
      spend(groceries, 60)
    end

    it "reads a plain number, with or without cents", :aggregate_failures do
      expect(present(groceries, amount: "55").amount).to eq(BigDecimal("55"))
      expect(present(groceries, amount: "55.25").amount).to eq(BigDecimal("55.25"))
      expect(present(groceries, amount: ".5").amount).to eq(BigDecimal("0.5"))
    end

    # `parseFloat("10*5")` is 10 in the browser and Dentaku says 50 on save. Neither is a figure to
    # print, so the card holds still until the formula resolves.
    it "holds at the claim for a formula the browser cannot evaluate", :aggregate_failures do
      expect(present(groceries, amount: "10*5").amount).to eq(0)
      expect(present(groceries, amount: "10*5").balance_after).to eq(BigDecimal("240"))
      expect(present(groceries, amount: "10*5").balance_after).not_to eq(BigDecimal("190"))
    end

    it "holds at the claim for a figure the form could never save", :aggregate_failures do
      expect(present(groceries, amount: "-10").amount).to eq(0)
      expect(present(groceries, amount: "1,500").amount).to eq(0)
      expect(present(groceries, amount: "abc").amount).to eq(0)
      expect(present(groceries, amount: "").amount).to eq(0)
      expect(present(groceries, amount: nil).amount).to eq(0)
    end

    it "takes a BigDecimal straight from the record on edit", :aggregate_failures do
      expect(present(groceries, amount: BigDecimal("55.25")).amount).to eq(BigDecimal("55.25"))
      expect(present(groceries, amount: BigDecimal("-55")).amount).to eq(0)
    end

    # THE CLIENT'S COPY OF THIS RULE, PINNED AT THE SOURCE. The card's whole client/server agreement
    # rests on the browser and Ruby agreeing about what a number is, and the two spellings cannot be
    # one literal across two languages — so the source is read and compared.
    #
    # THE ANCHORS DIFFER ON PURPOSE and that is the point of comparing the BODY rather than the whole
    # pattern. JavaScript's `$` without `m` is already end-of-string; RUBY'S IS NOT — `^`/`$` are
    # line anchors there — so `\A…\z` is the spelling that means the same thing.
    it "is the same rule the browser applies", :aggregate_failures do
      js = Rails.root.join("app/javascript/controllers/app/entry/impact_controller.js").read
      client_pattern = js[%r{static TYPED_AMOUNT = /(.+)/}, 1]
      server_pattern = described_class::TYPED_AMOUNT.source

      expect(client_pattern).to eq("^\\d*\\.?\\d+$")
      expect(server_pattern).to eq("\\A\\d*\\.?\\d+\\z")
      expect(client_pattern[1..-2]).to eq(server_pattern[2..-3])
    end

    # `\A…\z` EARNING ITS KEEP. `#strip` takes the trailing newline off "55\n" — as the browser's
    # `.trim()` does — so that shape never separates the two anchorings. An EMBEDDED one does:
    # `"5\n5"` survives `strip`, matches Ruby's line-anchored `$` on its first line, and is NaN to
    # `Number`. `\z` refuses it, which is the answer the browser already gives.
    it "refuses an embedded newline, which Ruby's line-anchored `$` would have waved through", :aggregate_failures do
      expect(present(groceries, amount: "5\n5").amount).to eq(0)
      expect("5\n5".match?(/^\d*\.?\d+$/)).to be(true)
      expect(present(groceries, amount: "55\n").amount).to eq(BigDecimal("55"))
    end
  end
end
