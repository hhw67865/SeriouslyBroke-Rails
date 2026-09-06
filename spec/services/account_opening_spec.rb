# frozen_string_literal: true

require "rails_helper"

# ** THE ONE OBJECT THAT SAYS WHAT AN ACCOUNT HOLDS (account-openings spec §§2 and 4). **
#
# Henry, 2026-09-06: "Not many people are going to know how much TOTAL money they have and then
# divide it all off. Instead they just want to put in what their accounts are currently worth. The
# fact you have to get the ordering exactly right is bad user experience." — so every save here is
# SELF-CONTAINED, and the file's centrepiece is the order-independence example: three accounts saved
# in two different orders produce identical figures, to the cent.
#
# ** THE SECOND RULING IS THE CORRECTION (§1): "Corrections should be done on the same initial entry.
# Actual movements appear as adjustments based on time." ** Re-saving an account does not write a
# second entry — it recomputes the amount of the one that is already there and leaves its DATE where
# it was. What has flowed through the account since is subtracted, so the figure the user types is
# the figure the app shows afterwards, whatever happened in between.
#
# ** THE INVARIANT IS ASSERTED BY RAW SQL AROUND EVERY WRITE (§4). ** `pot + Σ other accounts` is
# `income − expenses`, always: an opening record moves money's LOCATION and its EXISTENCE together,
# and the one shape this object could get wrong — an entry without its movement, a movement without
# its entry — shows up there and nowhere else. `#open!` below wraps every save in it, so no example
# in this file can write without being checked.
RSpec.describe AccountOpening, type: :model do
  let(:user) { create(:user) }
  let!(:checking) { create(:pool, :account, user: user, name: "Checking") }
  let(:ally) { create(:pool, :account, user: user, name: "Ally") }

  before { user.update!(default_account: checking) }

  # THE PHYSICAL SIDE, SUMMED BY THE APP'S OWN READER. `AccountLedger` is the ONE spelling of balance
  # arithmetic (§4: it is untouched by this work), so the invariant reads the money through it and
  # the truth it is checked against through raw SQL — two different roads to one number.
  def total_money = user.pools.accounts.sum(0.to_d) { |account| AccountLedger.new(user).balance_of(account) }

  # RAW SQL, deliberately: a second reading of the same tables through the same ActiveRecord scopes
  # would agree with the ledger by construction and pin nothing.
  def net_entries_by_sql
    sql = <<~SQL.squish
      SELECT COALESCE(SUM(CASE WHEN c.category_type = 1 THEN e.amount::numeric ELSE -e.amount::numeric END), 0)
      FROM entries e
      INNER JOIN items i ON i.id = e.item_id
      INNER JOIN categories c ON c.id = i.category_id
      WHERE c.user_id = '#{user.id}'
    SQL
    ActiveRecord::Base.connection.select_value(sql).to_d
  end

  def expect_invariant
    expect(total_money).to eq(net_entries_by_sql)
  end

  # EVERY WRITE IN THIS FILE GOES THROUGH HERE, and the invariant is checked on both sides of it.
  def open!(account, balance)
    expect_invariant
    opening = described_class.new(user, account, balance: balance)
    result = opening.save
    expect_invariant
    [opening, result]
  end

  def balance_of(account) = AccountLedger.new(user).balance_of(account)

  def opening_entry_for(account) = Entry.find_by(opening_account_id: account.id)

  def opening_entries = Entry.where.not(opening_account_id: nil)

  def earn(amount, on: Date.new(2026, 8, 5))
    create(:entry, item: create(:item, category: create(:category, :income, user: user)), amount: amount, date: on)
  end

  def spend(amount, on: Date.new(2026, 8, 7))
    create(:entry, item: create(:item, category: create(:category, :expense, user: user)), amount: amount, date: on)
  end

  # ── THE FIRST SAVE ─────────────────────────────────────────────────────────────────────────────

  describe "the first save" do
    # MAIN'S OPENING IS ONE ENTRY AND NOTHING ELSE (§2, row 1): there is no movement, because there
    # is nowhere for the money to have come from — main IS where money enters this user's life.
    it "gives main one income entry in the opening category", :aggregate_failures do
      _opening, saved = open!(checking, "1200.50")

      entry = opening_entry_for(checking)
      expect(saved).to be(true)
      expect(entry.amount).to eq(1200.50)
      expect(entry.item.category.name).to eq(Category::OPENING_BALANCE_NAME)
      expect(entry.item.category).to be_income
      expect(entry.account_movements).to be_empty
      expect(balance_of(checking)).to eq(1200.50)
    end

    # ANOTHER ACCOUNT'S OPENING IS THE ENTRY *PLUS* THE MOVEMENT (§2, row 2), and the pair is what
    # makes order irrelevant: the entry brings the money into the user's world and the movement puts
    # it where they said it is, so MAIN IS LEFT EXACTLY WHERE IT WAS. A movement alone would drain
    # main by $500 for the crime of naming a savings account.
    it "gives another account an entry and one transfer out of main", :aggregate_failures do
      open!(ally, "500")

      entry = opening_entry_for(ally)
      movement = entry.account_movements.sole
      expect(entry.amount).to eq(500)
      expect(movement.from_pool).to eq(checking)
      expect(movement.to_pool).to eq(ally)
      expect(movement.amount).to eq(500)
      expect(movement).to be_kind_transfer
      expect(balance_of(ally)).to eq(500)
      expect(balance_of(checking)).to eq(0)
    end

    # THE OPENING DAY (§2): the day before the user's earliest entry, so the money is inside no
    # period anybody will ever read. Re-derived: the earliest entry here is 2026-08-05, so the
    # opening is dated 2026-08-04, and `pools.opened_on` says so.
    it "dates the record the day before the earliest entry", :aggregate_failures do
      earn(300, on: Date.new(2026, 8, 5))

      open!(checking, "1000")

      expect(checking.reload.opened_on).to eq(Date.new(2026, 8, 4))
      expect(opening_entry_for(checking).date.to_date).to eq(Date.new(2026, 8, 4))
    end

    # THE USER'S OWN TODAY for a user with no history at all — there is no earlier day to be the day
    # before.
    it "dates it today for a user with no entries" do
      open!(checking, "1000")

      expect(checking.reload.opened_on).to eq(user.today)
    end

    # ** ZERO IS AN ANSWER, AND IT IS A ROW (fix round — MED-4). ** The gate on the account's card is
    # the opening ENTRY's existence, so "this account holds nothing" has to be writable as something:
    # a zero-amount entry, carved out of `Entry`'s `amount > 0` for this row alone. It carries NO
    # movement — there is nothing to move, and `account_movements` refuses a zero at the database.
    # Written as an income `Opening Balance` rather than a shortfall: nothing is short.
    it "records an opening of zero as a zero-amount entry with no movement", :aggregate_failures do
      _opening, saved = open!(ally, "0")

      entry = opening_entry_for(ally)
      expect(saved).to be(true)
      expect(ally.reload.opened_on).to eq(user.today)
      expect(entry.amount).to eq(0)
      expect(entry.item.category.name).to eq(Category::OPENING_BALANCE_NAME)
      expect(entry.account_movements).to be_empty
      expect(balance_of(ally)).to eq(0)
    end

    # THE OPENING ENTRIES ARE NOT THE USER'S HISTORY, so they cannot be what the opening day is
    # measured from — each new account would otherwise open a day earlier than the last, walking
    # backwards forever. Re-derived: Ally opens on the user's today (no entries yet) and writes an
    # entry dated that day; HYSA, saved second, must open on the SAME day rather than the day before
    # Ally's.
    it "ignores other openings when it picks the day" do
      hysa = create(:pool, :account, user: user, name: "HYSA")

      open!(ally, "500")
      open!(hysa, "200")

      expect(hysa.reload.opened_on).to eq(user.today)
    end
  end

  # ── THE CORRECTION (§2: "edits the opening record in place — never a second entry") ─────────────

  describe "a correction" do
    it "recomputes the same entry rather than writing a second", :aggregate_failures do
      open!(checking, "1000")
      original = opening_entry_for(checking)

      open!(checking, "1500")

      expect(opening_entries.count).to eq(1)
      expect(opening_entry_for(checking).id).to eq(original.id)
      expect(opening_entry_for(checking).amount).to eq(1500)
      expect(balance_of(checking)).to eq(1500)
    end

    # THE DATE STAYS THE OPENING DAY (§2), even though the user has recorded older history since —
    # the record is about where the account STARTED, and moving it would rewrite when that was.
    # Re-derived: Checking opens on the user's today with no history; the entry planted afterwards is
    # dated a year earlier; the corrected record is still dated the original opening day.
    it "leaves the date on the opening day", :aggregate_failures do
      open!(checking, "1000")
      opened = checking.reload.opened_on
      earn(50, on: 1.year.ago.to_date)

      open!(checking, "1200")

      expect(checking.reload.opened_on).to eq(opened)
      expect(opening_entry_for(checking).date.to_date).to eq(opened)
    end

    # ** WHAT HAS FLOWED THROUGH SINCE IS SUBTRACTED (§2's formula for main). ** Re-derived: main
    # opened at $1,000, then $400 of income and $150 of spending were recorded, so the app already
    # shows $1,250. The user says main really holds $2,000 — so its opening must have been
    # 2000 − (400 − 150) = $1,750, and the balance afterwards is exactly the $2,000 typed.
    it "subtracts the income and expenses recorded since", :aggregate_failures do
      open!(checking, "1000")
      earn(400)
      spend(150)

      open!(checking, "2000")

      expect(opening_entry_for(checking).amount).to eq(1750)
      expect(balance_of(checking)).to eq(2000)
    end

    # THE SAME FORMULA'S MOVEMENT ARMS, on main: money moved OUT is added back, money moved IN is
    # taken off. Re-derived: main opened at $1,000, then $600 was really transferred to Ally, so main
    # shows $400. The user says main holds $900 → its opening must have been 900 + 600 = $1,500.
    it "adds back what main has really transferred away", :aggregate_failures do
      open!(checking, "1000")
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 600, date: Date.current, kind: :transfer)

      open!(checking, "900")

      expect(opening_entry_for(checking).amount).to eq(1500)
      expect(balance_of(checking)).to eq(900)
      expect(balance_of(ally)).to eq(600)
    end

    # ** THE OTHER ACCOUNT'S FORMULA (§2): `typed − Σ (other movements in − out)`. ** Re-derived:
    # Ally opened at $500, then $300 was really moved into it, so it shows $800. The user says Ally
    # holds $1,000 → its opening must have been 1000 − 300 = $700, and the ONE opening movement is
    # rewritten to $700 rather than joined by a second.
    it "rewrites the account's own opening movement, net of the real transfers since", :aggregate_failures do
      open!(ally, "500")
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 300, date: Date.current, kind: :transfer)

      open!(ally, "1000")

      entry = opening_entry_for(ally)
      expect(entry.amount).to eq(700)
      expect(entry.account_movements.sole.amount).to eq(700)
      expect(AccountMovement.where(to_pool: ally).count).to eq(2)
      expect(balance_of(ally)).to eq(1000)
    end

    # ** A USER'S OWN TRANSFER ON THE OPENING DAY IS NOT THE OPENING MOVEMENT. ** This is the shape
    # that decides the marker: "the movement dated the opening day from main to this account" would
    # match BOTH rows here and rewrite the wrong one (or refuse). The opening movement is the one
    # whose `source_entry` is the opening entry, and a user's own transfer names no entry at all.
    # Re-derived: Ally opens at $500 on the user's today; a real $100 transfer is made the SAME day,
    # so Ally shows $600; correcting to $500 must leave the $100 transfer alone and put the opening
    # back to 500 − 100 = $400.
    it "leaves a same-day transfer of the user's own untouched", :aggregate_failures do
      open!(ally, "500")
      own = create(
        :account_movement, from_pool: checking, to_pool: ally, amount: 100, date: user.today, kind: :transfer
      )

      open!(ally, "500")

      expect(own.reload.amount).to eq(100)
      expect(opening_entry_for(ally).account_movements.sole.amount).to eq(400)
      expect(balance_of(ally)).to eq(500)
    end

    # A PRE-EXISTING ACCOUNT — one that has been moved into for years and never said what it holds —
    # gets its first opening record on its first correction (§2's last sentence). Re-derived: $900
    # has been moved into Ally, so it shows $900; the user says it really holds $1,000, so the
    # opening it never had is $100.
    it "gives a pre-existing account its first record", :aggregate_failures do
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 900, date: Date.current, kind: :transfer)

      open!(ally, "1000")

      expect(opening_entry_for(ally).amount).to eq(100)
      expect(balance_of(ally)).to eq(1000)
    end

    # A CORRECTION DOWN TO WHAT THE APP ALREADY TRACKS LEAVES THE ROW STANDING AT ZERO, and its
    # MOVEMENT is what goes — the account is fed entirely by the transfers since, so the opening
    # itself is worth nothing. Re-derived: Ally opened at $500, $500 was really moved in, so it shows
    # $1,000; the user says $500 → the opening is 500 − 500 = $0.
    it "empties the record rather than deleting it when the correction comes out at zero", :aggregate_failures do
      open!(ally, "500")
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 500, date: Date.current, kind: :transfer)

      open!(ally, "500")

      entry = opening_entry_for(ally)
      expect(entry.amount).to eq(0)
      expect(entry.account_movements).to be_empty
      expect(Entry.where.not(opening_account_id: nil).count).to eq(1)
      expect(ally.reload.opened_on).to be_present
      expect(balance_of(ally)).to eq(500)
    end

    # ** THE HOUSEHOLD WHOSE FIGURE THE APP ALREADY HAS RIGHT, which is the case a delete-on-zero
    # would have made unanswerable. ** Re-derived: $2,000 of income lands in main and nothing else
    # happens, so main shows $2,000; the user types $2,000 → the opening is $0 — and the account has
    # ANSWERED, which is the only thing standing between them and a card that asks forever.
    it "counts as answered when the typed figure is what the app already shows", :aggregate_failures do
      earn(2_000)

      open!(checking, "2000")

      expect(opening_entry_for(checking).amount).to eq(0)
      expect(balance_of(checking)).to eq(2_000)
    end
  end

  # ── THE NEGATIVE RULE (§4) ─────────────────────────────────────────────────────────────────────

  describe "a negative balance" do
    # AN OVERDRAWN CHECKING ACCOUNT IS A FACT, so main takes it — and the money has to LEAVE the
    # user's world for the pot to read below zero, which is an EXPENSE entry. The `Opening Shortfall`
    # category is the expense-side twin of `Opening Balance`: one category cannot be both types at
    # once, and a user with an overdrawn main and a funded savings account needs both signs on the
    # same day.
    it "is allowed on main and lands as an expense entry", :aggregate_failures do
      _opening, saved = open!(checking, "-50")

      entry = opening_entry_for(checking)
      expect(saved).to be(true)
      expect(entry.amount).to eq(50)
      expect(entry.item.category.name).to eq(Category::OPENING_SHORTFALL_NAME)
      expect(entry.item.category).to be_expense
      expect(balance_of(checking)).to eq(-50)
    end

    # A MIRROR CANNOT BE OVERDRAWN BY CONSTRUCTION (§4): a non-main account holds what has been moved
    # into it, and nothing can move more out than main was able to send.
    it "is refused on any other account", :aggregate_failures do
      opening, saved = open!(ally, "-50")

      expect(saved).to be(false)
      expect(opening.errors.full_messages.to_sentence).to include("can't be negative")
      expect(opening_entry_for(ally)).to be_nil
      expect(ally.reload.opened_on).to be_nil
    end

    # THE COMPUTED amount may still come out negative for a non-main account — the TYPED figure is
    # what §4 refuses, and a user who says an account holds less than the app has moved into it is
    # stating a fact about untracked history, not an overdraft. Re-derived: $900 moved into Ally,
    # user says $400 → the opening is 400 − 900 = −$500, which is an expense entry and a transfer
    # BACK to main, so Ally reads the $400 typed.
    it "sends the money the other way when the correction computes negative", :aggregate_failures do
      create(:account_movement, from_pool: checking, to_pool: ally, amount: 900, date: Date.current, kind: :transfer)

      open!(ally, "400")

      entry = opening_entry_for(ally)
      movement = entry.account_movements.sole
      expect(entry.item.category).to be_expense
      expect(movement.from_pool).to eq(ally)
      expect(movement.to_pool).to eq(checking)
      expect(movement.amount).to eq(500)
      expect(balance_of(ally)).to eq(400)
    end

    # A SIGN FLIP REWRITES THE ONE ROW rather than leaving the old one behind: the entry moves to the
    # other opening category, and there is still exactly one opening entry for the account.
    it "moves the entry across categories when the sign flips", :aggregate_failures do
      open!(checking, "-50")
      original = opening_entry_for(checking)

      open!(checking, "300")

      expect(opening_entries.count).to eq(1)
      expect(opening_entry_for(checking).id).to eq(original.id)
      expect(opening_entry_for(checking).item.category.name).to eq(Category::OPENING_BALANCE_NAME)
      expect(balance_of(checking)).to eq(300)
    end
  end

  # ── ORDER INDEPENDENCE (§2, and the ruling that started this) ──────────────────────────────────

  describe "order independence" do
    # ** THE WHOLE POINT OF THE DESIGN, ASSERTED THE ONLY WAY IT CAN BE: twice. ** Two users, the same
    # three accounts and the same three figures, saved in opposite orders — main last for one and
    # main first for the other — and every figure that comes out is identical. Re-derived: nothing is
    # divided, so Checking reads its own $300, Ally its $500, HYSA its $200, and the money the user
    # has everywhere is $1,000.
    it "produces identical figures whichever order the accounts are saved in", :aggregate_failures do
      figures = ->(owner) { owner.pools.accounts.order(:name).map { |a| [a.name, AccountLedger.new(owner).balance_of(a)] } }

      one = setup_three
      save_three(one, ["Ally", "Checking", "HYSA"])
      two = setup_three
      save_three(two, ["HYSA", "Checking", "Ally"])

      expect(figures.call(one)).to eq(figures.call(two))
      expect(figures.call(one)).to eq([["Ally", 500.to_d], ["Checking", 300.to_d], ["HYSA", 200.to_d]])
      expect(AccountLedger.new(one).pot).to eq(AccountLedger.new(two).pot)
      expect(ClaimLedger.new(one).total_money).to eq(ClaimLedger.new(two).total_money)
      expect(ClaimLedger.new(one).total_money).to eq(1_000)
    end

    def setup_three
      owner = create(:user)
      checking = create(:pool, :account, user: owner, name: "Checking")
      create(:pool, :account, user: owner, name: "Ally")
      create(:pool, :account, user: owner, name: "HYSA")
      owner.update!(default_account: checking)
      owner
    end

    def save_three(owner, order)
      amounts = { "Checking" => "300", "Ally" => "500", "HYSA" => "200" }
      order.each do |name|
        account = owner.pools.accounts.find_by!(name: name)
        expect(described_class.new(owner, account, balance: amounts.fetch(name)).save).to be(true)
      end
    end
  end

  # ── THE REST OF THE REFUSALS ───────────────────────────────────────────────────────────────────

  describe "what it refuses" do
    it "refuses an unparsable figure", :aggregate_failures do
      opening, saved = open!(checking, "not a number")

      expect(saved).to be(false)
      expect(opening.errors.full_messages.to_sentence).to include("must be a number")
    end

    it "refuses a blank figure" do
      _opening, saved = open!(checking, "")

      expect(saved).to be(false)
    end

    # AN ACCOUNT THAT IS NOT THIS USER'S is a caller bug rather than a user error, and it is the same
    # refusal `AccountLedger` makes about the same question.
    it "refuses a stranger's account" do
      foreign = create(:pool, :account, user: create(:user))

      expect { described_class.new(user, foreign, balance: "10").save }.to raise_error(AccountLedger::NotAnAccount)
    end

    # NO MAIN ACCOUNT MEANS NO SOURCE for the transfer a non-main opening needs — inventing one would
    # move money the user never had. Main itself is still openable, which is how the state is left.
    # THE ACCOUNT IS MINTED FIRST, then main is cleared: the `:account` factory trait makes the first
    # account a user has their default, so creating one INSIDE the state this example is about would
    # quietly fill the hole it is testing.
    it "refuses another account while the user has no main one", :aggregate_failures do
      account = ally
      user.update!(default_account: nil)

      opening = described_class.new(user, account, balance: "10")

      expect(opening.save).to be(false)
      expect(opening.errors.full_messages.to_sentence).to include("main account")
    end
  end
end
