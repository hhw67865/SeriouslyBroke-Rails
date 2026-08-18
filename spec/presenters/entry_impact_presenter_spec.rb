# frozen_string_literal: true

require "rails_helper"

# THE §6 IMPACT CARD'S SERVER HALF. The card answers "can I afford this" beside the amount box, and
# everything below is the half the browser cannot get wrong on its own: which envelope, what is in
# it, what the bar measures against, and — on edit — what the ledger has already counted.
#
# EVERY EXPECTED FIGURE IS A PLANTED LITERAL and both sides of every equality are independent. A
# balance is asserted against the sum of the movements and entries this file wrote, spelled out, and
# never against another reading of the same objects.
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
  let(:groceries_pool) { create(:pool, :budget_pool, user: user, account: checking, name: "Groceries") }
  let(:groceries) { create(:category, user: user, name: "Groceries", category_type: :expense, pool: groceries_pool) }

  # Money INTO an envelope is a movement out of the account that holds it — the same shape a
  # distribution writes.
  def fund(pool, amount)
    create(:pool_movement, from_pool: checking, to_pool: pool, amount: amount, date: Date.new(2026, 2, 6))
  end

  def spend(category, amount)
    create(:entry, item: create(:item, category: category), amount: amount, date: Date.new(2026, 2, 6))
  end

  # $300 EVERY PERIOD — a rate rule, so its own amount IS its per-period claim.
  def rate(pool, amount)
    create(:pool_budget, :per_period_rate, pool: pool, amount: amount)
  end

  # $X A MONTH — its per-period claim under a biweekly user is `amount * 12 / 26`, nothing like its
  # own amount. This is the shape the bar's denominator lives or dies on.
  def monthly_rate(pool, amount)
    create(:pool_budget, :rate, pool: pool, amount: amount)
  end

  def present(category, amount: nil, entry: nil)
    described_class.new(user: user, category: category, amount: amount, entry: entry, today: today)
  end

  describe "the envelope card" do
    before do
      fund(groceries_pool, 240)
      rate(groceries_pool, 300)
    end

    it "prints the balance the ledger holds and what the typed amount would leave", :aggregate_failures do
      impact = present(groceries, amount: "55")

      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance_after).to eq(BigDecimal("185"))
      expect(impact.pool).to eq(groceries_pool)
      expect(impact.noun).to eq("envelope")
    end

    it "leaves the balance where it is when nothing has been typed", :aggregate_failures do
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
  end

  describe "the bar" do
    it "measures what would be left against what the envelope claims from a period", :aggregate_failures do
      fund(groceries_pool, 240)
      rate(groceries_pool, 300)

      # 185 of a 300-a-period claim.
      expect(present(groceries, amount: "55").denominator).to eq(BigDecimal("300"))
      expect(present(groceries, amount: "55").bar_percent).to eq(62)
      expect(present(groceries, amount: "180").bar_percent).to eq(20)
    end

    it "claims the PER-PERIOD share of a monthly rule and not its sticker price", :aggregate_failures do
      fund(groceries_pool, 240)
      monthly_rate(groceries_pool, 1_500)

      # $1,500 a month under a biweekly period is 1500 * 12 / 26.
      expect(present(groceries).denominator).to eq(BigDecimal("692.31"))
      expect(present(groceries).denominator).not_to eq(BigDecimal("1500"))
    end

    it "clamps full rather than overflowing when the envelope holds more than it claims", :aggregate_failures do
      fund(groceries_pool, 600)
      rate(groceries_pool, 300)

      expect(present(groceries).bar_percent).to eq(100)
      expect(present(groceries, amount: "450").bar_percent).to eq(50)
    end

    it "clamps empty rather than going negative when the envelope is overdrawn", :aggregate_failures do
      fund(groceries_pool, 240)
      rate(groceries_pool, 300)

      expect(present(groceries, amount: "400").balance_after).to eq(BigDecimal("-160"))
      expect(present(groceries, amount: "400").bar_percent).to eq(0)
    end

    # NO BAR AT ALL rather than an empty one: a full-length grey track under "$240.00 left" says
    # "nothing left" an inch beneath a figure saying otherwise.
    it "has no bar at all, and does not divide, on an envelope with no rules on it", :aggregate_failures do
      fund(groceries_pool, 240)

      expect(present(groceries).bar?).to be(false)
      expect(present(groceries).denominator).to eq(0)
      expect(present(groceries).bar_percent).to eq(0)
      expect(present(groceries).balance).to eq(BigDecimal("240"))
    end

    it "has one the moment the envelope has something to claim", :aggregate_failures do
      fund(groceries_pool, 240)
      rate(groceries_pool, 300)

      expect(present(groceries).bar?).to be(true)
      expect(present(groceries).bar_percent).to eq(80)
    end

    it "has none on a card with no envelope behind it" do
      on_the_buffer = create(:category, user: user, name: "Shopping", category_type: :expense, pool: checking)

      expect(present(on_the_buffer).bar?).to be(false)
    end
  end

  describe "the figures the browser re-reads" do
    it "writes four-figure money without a thousands separator", :aggregate_failures do
      fund(groceries_pool, 1_500)
      rate(groceries_pool, 1_200)

      expect(present(groceries).balance_param).to eq("1500.00")
      expect(present(groceries).denominator_param).to eq("1200.00")
      expect(present(groceries).balance_param).not_to include(",")
      expect(present(groceries).denominator_param).not_to include(",")
    end

    it "writes a negative balance signed, so the browser subtracts from the right number" do
      spend(groceries, 80)

      expect(present(groceries).balance_param).to eq("-80.00")
    end
  end

  describe "overdrawing" do
    before do
      fund(groceries_pool, 40)
      rate(groceries_pool, 300)
    end

    it "goes negative and says so", :aggregate_failures do
      impact = present(groceries, amount: "55")

      expect(impact.balance_after).to eq(BigDecimal("-15"))
      expect(impact.overdrawn?).to be(true)
    end

    it "is not overdrawn by an amount the envelope covers", :aggregate_failures do
      impact = present(groceries, amount: "25")

      expect(impact.balance_after).to eq(BigDecimal("15"))
      expect(impact.overdrawn?).to be(false)
    end

    it "reads level, not overdrawn, when the envelope is spent to the penny", :aggregate_failures do
      impact = present(groceries, amount: "40")

      expect(impact.balance_after).to eq(0)
      expect(impact.overdrawn?).to be(false)
    end
  end

  describe "editing an entry the ledger has already counted" do
    let!(:existing) do
      create(:entry, item: create(:item, category: groceries), amount: 45, date: Date.new(2026, 2, 6))
    end

    before do
      fund(groceries_pool, 240)
      rate(groceries_pool, 300)
    end

    # THE LEDGER SAYS $195 — $240 funded less the $45 already logged. The card must not.
    it "shows the world as if this entry were being decided now", :aggregate_failures do
      impact = present(groceries, amount: "45", entry: existing)

      expect(groceries_pool.calculator(today: today).balance).to eq(BigDecimal("195"))
      expect(impact.balance).to eq(BigDecimal("240"))
      expect(impact.balance_after).to eq(BigDecimal("195"))
    end

    # The same $45 typed as a NEW entry lands on different figures — which is the whole point of
    # the exclusion, and the pair is asserted together so neither can quietly become the other.
    it "differs from the same amount logged as a new entry", :aggregate_failures do
      creating = present(groceries, amount: "45")

      expect(creating.balance).to eq(BigDecimal("195"))
      expect(creating.balance_after).to eq(BigDecimal("150"))
    end

    it "moves the right-hand figure as the edited amount changes", :aggregate_failures do
      expect(present(groceries, amount: "100", entry: existing).balance_after).to eq(BigDecimal("140"))
      expect(present(groceries, amount: "10", entry: existing).balance_after).to eq(BigDecimal("230"))
    end

    # RE-CATEGORISING: the entry's money is in Groceries, so Dining Out must not be credited with it.
    it "excludes nothing from an envelope the entry's money is not in", :aggregate_failures do
      dining_pool = create(:pool, :budget_pool, user: user, account: checking, name: "Dining Out")
      dining = create(:category, user: user, name: "Dining Out", category_type: :expense, pool: dining_pool)
      fund(dining_pool, 100)

      impact = present(dining, amount: "45", entry: existing)

      expect(impact.balance).to eq(BigDecimal("100"))
      expect(impact.balance_after).to eq(BigDecimal("55"))
    end

    # THE TWO CROSS-SIGN EXAMPLES THAT STOOD HERE ARE DELETED (plan 3, task 5). Both planted a
    # SAVINGS entry and asserted that removing it took money OUT — the opposite sign from an
    # expense — and one of them re-categorised such an entry into an expense category to prove the
    # exclusion sign and the subtraction sign were read off different records. Neither entry is a
    # shape the app can hold: `#own_contribution` has one sign now, and the same-pool/other-pool
    # distinction it still makes is pinned by the two examples above.
    #
    # WHAT SURVIVES OF THEM is the edit case on a GOAL, which is the arm the brief keeps: an
    # expense entry already counted against a goal, re-read on the edit form.
    it "gives back an expense already counted against a goal rather than spending it twice", :aggregate_failures do
      vacation_pool = create(:pool, :savings_pool, user: user, account: checking, name: "Vacation", target_amount: 2_400)
      education = create(:category, user: user, name: "Education", category_type: :expense, pool: vacation_pool)
      fund(vacation_pool, 600)
      spent = create(:entry, item: create(:item, category: education), amount: 150, date: Date.new(2026, 2, 6))

      impact = present(education, amount: "150", entry: spent)

      # Ledger: 600 funded − 150 spent. Without this entry: 600. Spending 150: 450.
      expect(vacation_pool.calculator(today: today).balance).to eq(BigDecimal("450"))
      expect(impact.balance).to eq(BigDecimal("600"))
      expect(impact.balance_after).to eq(BigDecimal("450"))
    end
  end

  # ONE SHAPE REACHES THIS CARD NOW, WHERE TWO DID. `#unbudgeted?` reads
  # `pool.nil? || pool.pool_type_account?`, and the first arm used to be an ordinary saved
  # category that named no pool at all. Plan 3 requires a pool on every category, so the arm
  # survives only for a card with no CATEGORY selected yet (`pool` is `category&.effective_pool`),
  # which `#render?` already refuses to draw. The account-pointed shape is what a user actually
  # meets, and it was already asserted here beside the pool-less one.
  describe "a category funded by the buffer" do
    let(:on_the_buffer) { create(:category, user: user, name: "Shopping", category_type: :expense, pool: checking) }

    it "is told the truth rather than shown an envelope", :aggregate_failures do
      impact = present(on_the_buffer, amount: "55")

      expect(impact.render?).to be(true)
      expect(impact.unbudgeted?).to be(true)
      expect(impact.figures?).to be(false)
      expect(impact.pool).to eq(checking)
    end

    it "cannot overdraw anything, and does not raise being asked" do
      expect(present(on_the_buffer, amount: "55").overdrawn?).to be(false)
    end

    # `#contribution?` IS GONE (plan 3, task 5). It split this card into a spending arm and a
    # contribution arm ("No goal — this contribution has nowhere to land", pointing at /pools/new);
    # only the spending arm is reachable now, so the method and the second arm went together.
    it "has no contribution arm to choose between", :aggregate_failures do
      expect(present(on_the_buffer)).not_to respond_to(:contribution?)
      expect(present(on_the_buffer).unbudgeted?).to be(true)
    end

    it "is not what an enveloped category gets", :aggregate_failures do
      fund(groceries_pool, 240)

      expect(present(groceries, amount: "55").unbudgeted?).to be(false)
      expect(present(groceries, amount: "55").figures?).to be(true)
    end
  end

  describe "a savings goal" do
    let(:vacation_pool) do
      create(:pool, :savings_pool, user: user, account: checking, name: "Vacation", target_amount: 2_400)
    end
    # THE GOAL ARM IS KEYED ON THE POOL, NOT ON THE CATEGORY, which is why it survives task 5
    # intact: an EXPENSE category pointing at a savings goal is the demo's own shape (Vacation
    # Spending → Vacation to Europe), and spending from a goal is still spending against a goal.
    # The category planted here was a SAVINGS one and is an expense one now; the noun, the target
    # and the bar are unchanged, and only the sign of the arithmetic moved — which is the whole of
    # what the enum value carried.
    let(:vacation) { create(:category, user: user, name: "Vacation", category_type: :expense, pool: vacation_pool) }

    before { fund(vacation_pool, 600) }

    it "takes the goal shape and measures against the target", :aggregate_failures do
      impact = present(vacation, amount: "150")

      expect(impact.goal?).to be(true)
      expect(impact.noun).to eq("goal")
      expect(impact.balance).to eq(BigDecimal("600"))
      expect(impact.balance_after).to eq(BigDecimal("450"))
      expect(impact.goal_target).to eq(BigDecimal("2400"))
    end

    it "measures its bar against the goal and not against its rules", :aggregate_failures do
      # A $500-a-period rule would draw this bar FULL; the goal draws it at 450 of 2,400.
      rate(vacation_pool, 500)

      expect(present(vacation, amount: "150").denominator).to eq(BigDecimal("2400"))
      expect(present(vacation, amount: "150").denominator).not_to eq(BigDecimal("500"))
      expect(present(vacation, amount: "150").bar_percent).to eq(19)
    end

    # BOTH DIRECTIONS ON THE SURVIVING ARM: a goal empties, and it says so in red once it is empty.
    it "goes negative and reports the overdraw like any other pool", :aggregate_failures do
      impact = present(vacation, amount: "900")

      expect(impact.goal?).to be(true)
      expect(impact.balance_after).to eq(BigDecimal("-300"))
      expect(impact.overdrawn?).to be(true)
    end

    # `Pool` validates a savings pool's target as PRESENT, not as positive, so zero is the only
    # targetless savings pool the app can hold — and a bar measured against it would divide by
    # nothing. It falls back to the envelope's own claim rather than to a zero-length bar.
    it "is not a goal without a target, and falls back to the envelope's own bar", :aggregate_failures do
      vacation_pool.update!(target_amount: 0)
      rate(vacation_pool, 500)

      expect(present(vacation).goal?).to be(false)
      expect(present(vacation).goal_target).to be_nil
      expect(present(vacation).denominator).to eq(BigDecimal("500"))
    end

    it "is not a goal on a budget envelope", :aggregate_failures do
      fund(groceries_pool, 240)

      expect(present(groceries).goal?).to be(false)
      expect(present(groceries).goal_target).to be_nil
    end
  end

  describe "an income category" do
    let(:paycheck) { create(:category, user: user, name: "Paycheck", category_type: :income, pool: checking) }

    # §6 leaves income out on purpose: it lands in the account, and the account is the buffer —
    # a concept the daily screen deliberately does not introduce.
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
      fund(groceries_pool, 240)
      rate(groceries_pool, 300)
    end

    it "reads a plain number, with or without cents", :aggregate_failures do
      expect(present(groceries, amount: "55").amount).to eq(BigDecimal("55"))
      expect(present(groceries, amount: "55.25").amount).to eq(BigDecimal("55.25"))
      expect(present(groceries, amount: ".5").amount).to eq(BigDecimal("0.5"))
    end

    # `parseFloat("10*5")` is 10 in the browser and Dentaku says 50 on save. Neither is a figure to
    # print, so the card holds still until the formula resolves.
    it "holds at the balance for a formula the browser cannot evaluate", :aggregate_failures do
      expect(present(groceries, amount: "10*5").amount).to eq(0)
      expect(present(groceries, amount: "10*5").balance_after).to eq(BigDecimal("240"))
      expect(present(groceries, amount: "10*5").balance_after).not_to eq(BigDecimal("190"))
    end

    it "holds at the balance for a figure the form could never save", :aggregate_failures do
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
    # one literal across two languages — so the source is read and compared. A keystroke that reads
    # as $50 in Ruby and as nothing in JavaScript would show a figure that moves on submit.
    #
    # THE ANCHORS DIFFER ON PURPOSE and that is the point of comparing the BODY rather than the whole
    # pattern. JavaScript's `$` without `m` is already end-of-string; RUBY'S IS NOT — `^`/`$` are
    # line anchors there — so `\A…\z` is the spelling that means the same thing. Measured on the one
    # input where it bites (see the example below): `"5\n5"` matches `/^\d*\.?\d+$/` in Ruby on its
    # first line while `Number("5\n5")` is NaN, so the two halves would read the same keystrokes as
    # $5 and as nothing.
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
