# frozen_string_literal: true

require "rails_helper"

# THE §6 IMPACT CARD'S SERVER HALF. The card answers "can I afford this" beside the amount box, and
# everything below is the half the browser cannot get wrong on its own: whether the category is
# holding money at all, what it holds, what the bar measures against, and — on edit — what the
# ledger has already counted.
#
# CONVERTED TO THE PURPOSE LEDGER (Task 6). Every fixture used to plant an envelope inside an
# account and fund it with a movement; a category holds its own money now (two-ledger spec §3), so
# the funding is an `Allocation` and the rule sits on the category. The figures are unchanged: the
# same $240 funded, the same $300-a-period claim, the same $185 left.
#
# EVERY EXPECTED FIGURE IS A PLANTED LITERAL and both sides of every equality are independent. A
# holding is asserted against the sum of the allocations and entries this file wrote, spelled out,
# and never against another reading of the same objects.
#
# EVERY FIXTURE IS BIWEEKLY and the anchor is a fixed date, so a monthly rule's amount and its
# per-period claim are never the same number — the mixed-unit slip has struck five times on this
# branch and a suite of per-period rules would pass with it in place. `today:` is passed explicitly
# rather than travelled to, so no example reads `Date.current` inside a frozen clock.
RSpec.describe EntryImpactPresenter do
  # Feb 6 is the anchor AND the day, so the boundaries are Feb 6 and Feb 20 and the period the card
  # reports runs to Feb 19 — the spec's own mockup date.
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

  # MONEY INTO A CATEGORY IS AN ALLOCATION OUT OF AVAILABLE — the same shape a distribution writes.
  # It moves nothing physical (§2), which is why no account appears in this file's fixtures at all
  # beyond the one every user must have.
  def fund(category, amount)
    create(:allocation, kind: :allocation, to_category: category, amount: amount, date: Date.new(2026, 2, 6))
  end

  def spend(category, amount, on: Date.new(2026, 2, 6))
    create(:entry, item: create(:item, category: category), amount: amount, date: on)
  end

  # $300 EVERY PERIOD — a rate rule, so its own amount IS its per-period claim.
  def rate(category, amount)
    create(:budget, :per_period_rate, pool: nil, category: category, amount: amount)
  end

  # $X A MONTH — its per-period claim under a biweekly user is `amount * 12 / 26`, nothing like its
  # own amount. This is the shape the bar's denominator lives or dies on.
  def monthly_rate(category, amount)
    create(:budget, :rate, pool: nil, category: category, amount: amount)
  end

  # A HOLDER WITH A TARGET AND NO RULE — `Category#savings?`, which is the card's goal question.
  def goal(name, target:, funded: 0)
    attrs = { funded_since: funded_since, target_amount: target }
    category = create(:category, :expense, user: user, name: name, **attrs)
    fund(category, funded) if funded.positive?
    category
  end

  def present(category, amount: nil, entry: nil)
    described_class.new(user: user, category: category, amount: amount, entry: entry, today: today)
  end

  describe "the envelope card" do
    before do
      fund(groceries, 240)
      rate(groceries, 300)
    end

    it "prints the holding the ledger has and what the typed amount would leave", :aggregate_failures do
      impact = present(groceries, amount: "55")

      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance_after).to eq(BigDecimal("185"))
      expect(impact.holding).to eq(groceries)
      expect(impact.noun).to eq("envelope")
    end

    it "leaves the holding where it is when nothing has been typed", :aggregate_failures do
      impact = present(groceries)

      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance_after).to eq(BigDecimal("240"))
      expect(impact.balance_after).not_to eq(BigDecimal("185"))
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
      expect(present(groceries).balance).to eq(BigDecimal("240"))
    end

    # `#pool` IS GONE with `Category#effective_pool`, which resolved which POOL a category's spending
    # reached. The question the card asks now is whether the CATEGORY holds it, and the answer is the
    # category itself or nothing at all.
    it "has no pool to name" do
      expect(present(groceries)).not_to respond_to(:pool)
    end
  end

  describe "the bar" do
    it "measures what would be left against what the category claims from a period", :aggregate_failures do
      fund(groceries, 240)
      rate(groceries, 300)

      # 185 of a 300-a-period claim.
      expect(present(groceries, amount: "55").denominator).to eq(BigDecimal("300"))
      expect(present(groceries, amount: "55").bar_percent).to eq(62)
      expect(present(groceries, amount: "180").bar_percent).to eq(20)
    end

    it "claims the PER-PERIOD share of a monthly rule and not its sticker price", :aggregate_failures do
      fund(groceries, 240)
      monthly_rate(groceries, 1_500)

      # $1,500 a month under a biweekly period is 1500 * 12 / 26.
      expect(present(groceries).denominator).to eq(BigDecimal("692.31"))
      expect(present(groceries).denominator).not_to eq(BigDecimal("1500"))
    end

    it "clamps full rather than overflowing when the category holds more than it claims", :aggregate_failures do
      fund(groceries, 600)
      rate(groceries, 300)

      expect(present(groceries).bar_percent).to eq(100)
      expect(present(groceries, amount: "450").bar_percent).to eq(50)
    end

    it "clamps empty rather than going negative when the category is overdrawn", :aggregate_failures do
      fund(groceries, 240)
      rate(groceries, 300)

      expect(present(groceries, amount: "400").balance_after).to eq(BigDecimal("-160"))
      expect(present(groceries, amount: "400").bar_percent).to eq(0)
    end

    # NO BAR AT ALL rather than an empty one: a full-length grey track under "$240.00 left" says
    # "nothing left" an inch beneath a figure saying otherwise.
    it "has no bar at all, and does not divide, on a category with no rules on it", :aggregate_failures do
      fund(groceries, 240)

      expect(present(groceries).bar?).to be(false)
      expect(present(groceries).denominator).to eq(0)
      expect(present(groceries).bar_percent).to eq(0)
      expect(present(groceries).balance).to eq(BigDecimal("240"))
    end

    it "has one the moment the category has something to claim", :aggregate_failures do
      fund(groceries, 240)
      rate(groceries, 300)

      expect(present(groceries).bar?).to be(true)
      expect(present(groceries).bar_percent).to eq(80)
    end

    it "has none on a card whose category is holding nothing" do
      unfunded = create(:category, :expense, user: user, name: "Shopping")

      expect(present(unfunded).bar?).to be(false)
    end
  end

  describe "the figures the browser re-reads" do
    it "writes four-figure money without a thousands separator", :aggregate_failures do
      fund(groceries, 1_500)
      rate(groceries, 1_200)

      expect(present(groceries).balance_param).to eq("1500.00")
      expect(present(groceries).denominator_param).to eq("1200.00")
      expect(present(groceries).balance_param).not_to include(",")
      expect(present(groceries).denominator_param).not_to include(",")
    end

    it "writes a negative holding signed, so the browser subtracts from the right number" do
      spend(groceries, 80)

      expect(present(groceries).balance_param).to eq("-80.00")
    end
  end

  describe "overdrawing" do
    before do
      fund(groceries, 40)
      rate(groceries, 300)
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

  describe "editing an entry the ledger has already counted" do
    let!(:existing) { spend(groceries, 45) }

    before do
      fund(groceries, 240)
      rate(groceries, 300)
    end

    # THE LEDGER SAYS $195 — $240 allocated in less the $45 already logged. The card must not.
    it "shows the world as if this entry were being decided now", :aggregate_failures do
      impact = present(groceries, amount: "45", entry: existing)

      expect(groceries.holding_calculator(today: today).balance).to eq(BigDecimal("195"))
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

    # RE-CATEGORISING: the entry's money drains Groceries, so Dining Out must not be credited with it.
    it "excludes nothing from a category the entry's money does not drain", :aggregate_failures do
      dining = create(:category, :expense, user: user, name: "Dining Out", funded_since: funded_since)
      fund(dining, 100)

      impact = present(dining, amount: "45", entry: existing)

      expect(impact.balance).to eq(BigDecimal("100"))
      expect(impact.balance_after).to eq(BigDecimal("55"))
    end

    # THE DATE IS THE SECOND HALF OF THE SAME TEST, and it is new with the re-anchored start-date
    # rule (§4). An entry dated BEFORE its category's `funded_since` drains AVAILABLE, not the
    # category — the ledger never counted it here — so removing it would credit the card with money
    # the category has never held. Both figures are the same because there is nothing to give back.
    it "excludes nothing for an entry dated before the category started holding money", :aggregate_failures do
      early = spend(groceries, 45, on: funded_since - 1.day)

      impact = present(groceries, amount: "45", entry: early)

      # The card describes the day the ENTRY is about, and on that day this category held nothing.
      expect(impact.unbudgeted?).to be(true)
      expect(impact.figures?).to be(false)
    end

    # AN EXPENSE ALREADY COUNTED AGAINST A GOAL, re-read on the edit form. Spending from a goal is
    # still spending against a goal, and the exclusion works the same way there.
    it "gives back an expense already counted against a goal rather than spending it twice", :aggregate_failures do
      vacation = goal("Vacation", target: 2_400, funded: 600)
      spent = spend(vacation, 150)

      impact = present(vacation, amount: "150", entry: spent)

      # Ledger: 600 allocated in − 150 spent. Without this entry: 600. Spending 150: 450.
      expect(vacation.holding_calculator(today: today).balance).to eq(BigDecimal("450"))
      expect(impact.balance).to eq(BigDecimal("600"))
      expect(impact.balance_after).to eq(BigDecimal("450"))
    end
  end

  # ONE SHAPE REACHES THIS CARD, AND IT IS A DATE AS MUCH AS A CATEGORY (Task 6). `#unbudgeted?` read
  # `pool.nil? || pool.pool_type_account?` — no envelope, or an envelope that was really an account,
  # and both meant "nothing reserves this money". Its successor is `Category#counts_spending_on?`,
  # which is the ledger's own rule: a category that has never been funded, and a funded one asked
  # about a day before it started holding, both send their spending to AVAILABLE.
  describe "a category that is not holding money" do
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

    # THE DATED ARM, and it is the new one: this category DOES hold money, and this receipt still
    # drains available because it predates the day it started. Both directions on one category, so
    # the example is about the date and nothing else.
    it "is the same card for a receipt dated before the category started holding", :aggregate_failures do
      fund(groceries, 240)
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

    it "is not what a holder gets", :aggregate_failures do
      fund(groceries, 240)

      expect(present(groceries, amount: "55").unbudgeted?).to be(false)
      expect(present(groceries, amount: "55").figures?).to be(true)
    end
  end

  describe "a savings goal" do
    # A GOAL IS `Category#savings?` — a holder, with a target, carrying NO refill rule (spec §3).
    # That is the app's DISPLAY question and deliberately not `HoldingCalculator#dateless_goal?`,
    # which asks the target alone because it is the FUNDING question. The card is a rendering, so it
    # asks the rendering question — and the two part company on exactly one shape, pinned below.
    let(:vacation) { goal("Vacation", target: 2_400, funded: 600) }

    before { vacation }

    it "takes the goal shape and measures against the target", :aggregate_failures do
      impact = present(vacation, amount: "150")

      expect(impact.goal?).to be(true)
      expect(impact.noun).to eq("goal")
      expect(impact.balance).to eq(BigDecimal("600"))
      expect(impact.balance_after).to eq(BigDecimal("450"))
      expect(impact.goal_target).to eq(BigDecimal("2400"))
    end

    it "measures its bar against the target, which no rule could ever be", :aggregate_failures do
      # 450 of 2,400. A goal with NO rule has no per-period claim at all, so under the envelope
      # denominator its bar could never move — which is the defect the target arm exists to fix.
      expect(present(vacation, amount: "150").denominator).to eq(BigDecimal("2400"))
      expect(present(vacation, amount: "150").bar_percent).to eq(19)
      expect(present(vacation, amount: "150").bar?).to be(true)
    end

    # BOTH DIRECTIONS ON THE SURVIVING ARM: a goal empties, and it says so in red once it is empty.
    it "goes negative and reports the overdraw like any other category", :aggregate_failures do
      impact = present(vacation, amount: "900")

      expect(impact.goal?).to be(true)
      expect(impact.balance_after).to eq(BigDecimal("-300"))
      expect(impact.overdrawn?).to be(true)
    end

    # THE ONE SHAPE THE DISPLAY QUESTION AND THE FUNDING QUESTION DISAGREE ON, pinned rather than
    # left latent. A goal that ALSO carries a refill rule is not `savings?` — a category the
    # waterfall tops up every period is being SPENT toward a rate rather than SAVED toward a figure
    # — so this card draws it as an envelope against its rule's claim, while `HoldingStatus` still
    # calls it `saving` on Home (it asks the target through `dateless_goal?`). Recorded here because
    # a divergence with a reason is a design and an undisclosed one is the next drift.
    it "is an envelope, not a goal, once a refill rule fills it", :aggregate_failures do
      rate(vacation, 500)

      expect(vacation.reload.savings?).to be(false)
      expect(present(vacation).goal?).to be(false)
      expect(present(vacation).goal_target).to be_nil
      expect(present(vacation).denominator).to eq(BigDecimal("500"))
    end

    it "is not a goal without a target, and falls back to the category's own claim", :aggregate_failures do
      vacation.update!(target_amount: nil)
      rate(vacation, 500)

      expect(present(vacation).goal?).to be(false)
      expect(present(vacation).goal_target).to be_nil
      expect(present(vacation).denominator).to eq(BigDecimal("500"))
    end

    it "is not a goal on an ordinary spending category", :aggregate_failures do
      fund(groceries, 240)

      expect(present(groceries).goal?).to be(false)
      expect(present(groceries).goal_target).to be_nil
    end

    # A TARGET ON A CATEGORY THAT HOLDS NOTHING IS NOT A GOAL either, because there is nothing for
    # it to be progress toward — `Category#savings?` carries `holder?` for exactly this reason, and
    # the card falls to the honest arm rather than drawing a bar against a target no money can reach.
    it "is not a goal on a category that has never been funded", :aggregate_failures do
      never = create(:category, :expense, user: user, name: "Someday", target_amount: 5_000)

      expect(present(never).goal?).to be(false)
      expect(present(never).unbudgeted?).to be(true)
    end
  end

  describe "an income category" do
    let(:paycheck) { create(:category, user: user, name: "Paycheck", category_type: :income, pool: checking) }

    # §6 leaves income out on purpose: it lands in available (§2), and how income meets categories
    # is the distribution screen's subject — a concept the daily screen deliberately does not
    # introduce.
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
      fund(groceries, 240)
      rate(groceries, 300)
    end

    it "reads a plain number, with or without cents", :aggregate_failures do
      expect(present(groceries, amount: "55").amount).to eq(BigDecimal("55"))
      expect(present(groceries, amount: "55.25").amount).to eq(BigDecimal("55.25"))
      expect(present(groceries, amount: ".5").amount).to eq(BigDecimal("0.5"))
    end

    # `parseFloat("10*5")` is 10 in the browser and Dentaku says 50 on save. Neither is a figure to
    # print, so the card holds still until the formula resolves.
    it "holds at the holding for a formula the browser cannot evaluate", :aggregate_failures do
      expect(present(groceries, amount: "10*5").amount).to eq(0)
      expect(present(groceries, amount: "10*5").balance_after).to eq(BigDecimal("240"))
      expect(present(groceries, amount: "10*5").balance_after).not_to eq(BigDecimal("190"))
    end

    it "holds at the holding for a figure the form could never save", :aggregate_failures do
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
