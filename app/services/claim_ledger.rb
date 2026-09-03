# frozen_string_literal: true

# EVERY CLAIM A USER HAS, AND WHAT IS LEFT OVER (computed-claims spec §2) — the batched door onto
# `ClaimCalculator`, and the one place `free` is defined.
#
#     free = min( pot , total_money − Σ claims )        where total_money = pot + Σ accounts
#
# THAT IS A DEFINITION AND NOT A PARTITION, which is the whole of what changed. The purpose side used
# to conserve — `available + Σ holdings == total` — because money was MOVED into envelopes; claims are
# DERIVED, so nothing is conserved and `free` is simply what the total is not spoken for by. The
# PHYSICAL invariant (`pot + Σ accounts == income − expenses`) is untouched and this class cannot see
# it: `AccountLedger` owns it, and nothing here writes anything at all.
#
# THE CAP AT `pot` IS THE ANSWERS-FIRST RULING (§3 of that spec, kept): money sitting in a savings
# account is not free to spend out of checking this afternoon, so however little is claimed, `free`
# never promises more than the pot actually holds. `#free_cap_bound?` is the reader that says which of
# the two terms is doing the work, because "you have $1,800 free" means two different things depending
# on the answer and the hero has to say which.
#
# ** THREE STATEMENTS FOR A WHOLE USER, AND THEY ARE THE `terms:` SEAM IN THE SHAPE §3.3 NEEDS. **
# `CategoryLedger` batches SUMS because a holding is one number; a claim is a WALK over periods, so
# what a screen can share is the ROWS — `[owner's calendar day, amount]` pairs, grouped by the lane
# they belong to. Two lanes and one delta table make three:
#
#   1. spending on the ITEMS that item-backed rules name, grouped by item;
#   2. spending on the CATEGORIES of the rules that name no item, grouped by category;
#   3. every adjustment on every one of the user's rules, grouped by rule.
#
# Both spending statements reproduce `ClaimCalculator#query_spending` line for line — the same
# `CategoryLedger::ENTRY_CATEGORY_ID` gate, the same `ENTRY_LOCAL_DAY` re-zoning, the same one-day
# slack on the window — and `claim_ledger_spec` pins the two against each other figure for figure on
# one fixture, so a divergence is a failing example rather than a screen quietly reading a different
# number than the category page beside it.
#
# A SNAPSHOT, STALE AFTER A WRITE, on `CategoryLedger`'s rule: anything that writes entries or
# adjustments must build a fresh ledger afterwards.
class ClaimLedger
  # A CLAIM ASKED OF A LEDGER BUILT OVER A DIFFERENT USER'S RULES. Zero would be a wrong money figure
  # wearing the face of a right one — a rule whose envelope has been spent flat — and this ledger is
  # built over the user's WHOLE rule set, so anything missing from it is a caller bug.
  # `CategoryLedger::UnknownCategory`'s reasoning, and its shape.
  class UnknownRule < StandardError; end

  attr_reader :user, :today

  def initialize(user, today: Date.current)
    @user = user
    @today = today
  end

  # EVERY RULE THIS USER OWNS, through the one scope that decides what that means (`Budget.for_user`).
  # The preload is `HoldingCalculator#rules`': `:item` is what a rule's lane is read off and the owner
  # walk goes through the category, so without them a claim costs two lookups per rule.
  def rules
    @rules ||= Budget.for_user(user).includes(:item, category: :user).to_a
  end

  def claim_of(rule) = calculator_for(rule).claim

  # THE CALCULATOR ITSELF, so a screen that needs the built-up, the due date and the per-period share
  # of the same rule (§3.4's row vocabulary) asks one object rather than four readers here.
  def calculator_for(rule)
    calculators.fetch(rule) do
      raise UnknownRule, "#{rule.category&.name} is not one of #{user.email}'s rules"
    end
  end

  def total_claims
    @total_claims ||= calculators.values.sum(0.to_d, &:claim)
  end

  # WHAT THE USER PHYSICALLY HAS, across every account — the pot plus the mirrors. Summed over ALL of
  # the accounts rather than "the pot plus the others", because `AccountLedger#balance_of(main)` IS
  # the pot: one expression, no main/other split to get wrong.
  def total_money
    @total_money ||= user.pools.accounts.sum(0.to_d) { |account| account_ledger.balance_of(account) }
  end

  delegate :pot, to: :account_ledger

  # MONEY WITH NO JOB — and BELOW ZERO IT IS A SIGNAL, NEVER A REFUSAL (§4). Nothing here clamps: a
  # negative `free` is exactly the fact the trouble strip exists to report, and hiding it behind a
  # `max(0, …)` would leave the app telling a user they have nothing free when what is true is that
  # they are $120 short.
  def free = [pot, total_money - total_claims].min

  # WHICH TERM IS DOING THE WORK. True when the money is spoken for by WHERE IT IS rather than by
  # what it is for — the claims leave room, but the room is in a savings account rather than in
  # checking. False when the claims themselves are the binding constraint, which is the state §4's
  # per-day pace is about.
  def free_cap_bound? = pot < total_money - total_claims

  private

  def account_ledger = @account_ledger ||= AccountLedger.new(user)

  def calculators
    @calculators ||= rules.index_with do |rule|
      ClaimCalculator.new(
        rule, today: today, spending: spending_for(rule), adjustments: adjustments_for(rule)
      )
    end
  end

  # THE EARLIEST DAY ANY OF THESE RULES CAN BE MOVED BY — the open of the first period the widest walk
  # visits, which is what keeps one statement from pulling a decade of entries nothing will read.
  #
  # ASKED OF THROWAWAY CALCULATORS HANDED EMPTY ROWS, and the empties are the point: `#window_start`
  # is a calendar question, and a probe that could reach the database would run the very per-rule
  # queries this class exists to replace. It cannot — an empty array is an answer (see
  # `ClaimCalculator#spending_rows`), so a probe is provably query-free.
  def window_start
    @window_start ||= probes.map(&:window_start).min || user.period_containing(today).first
  end

  def probes
    @probes ||= rules.map { |rule| ClaimCalculator.new(rule, today: today, spending: [], adjustments: []) }
  end

  # ONE DAY OF SLACK, for `ClaimCalculator#query_spending`'s reason: the bound is a UTC instant and the
  # day it protects is the owner's, and no zone on earth is more than 14 hours out.
  #
  # THE PARENTHESES ARE LOAD-BEARING: an endless range written bare at the end of an endless method
  # swallows the NEXT `def` as its upper bound, and what follows is a class whose later methods
  # silently do not exist. (Measured: every example in this file failed with `undefined method
  # 'spending_for'`.)
  def window = ((window_start - 1).beginning_of_day..)

  def spending_for(rule)
    rows = rule.item_id.present? ? item_spending[rule.item_id] : category_spending[rule.category_id]
    Array(rows).map { |_key, day, amount| [day, amount] }
  end

  def adjustments_for(rule)
    Array(adjustment_rows[rule.id]).map { |_key, date, amount| [user.local_day(date), amount.to_d] }
  end

  # STATEMENT 1 — the item lanes. Narrowed to the items rules actually name, so a category full of
  # items costs nothing for the one rule that anchors on a single bill.
  def item_spending
    @item_spending ||= begin
      ids = rules.filter_map(&:item_id)
      ids.empty? ? {} : draining.where(item_id: ids).pluck(:item_id, CategoryLedger::ENTRY_LOCAL_DAY, :amount).group_by(&:first)
    end
  end

  # STATEMENT 2 — the category lanes, for the rules that name no item. The WHERE and the GROUP BY are
  # the same expression, `CategoryLedger#grouped_entries`' own discipline: a row can only be counted
  # for the category the funding rule itself assigns it to.
  def category_spending
    @category_spending ||= begin
      ids = rules.reject { |rule| rule.item_id.present? }.filter_map(&:category_id)
      if ids.empty?
        {}
      else
        draining.where("#{CategoryLedger::ENTRY_CATEGORY_ID} IN (:ids)", ids: ids)
          .pluck(CategoryLedger::ENTRY_CATEGORY_ID, CategoryLedger::ENTRY_LOCAL_DAY, :amount).group_by(&:first)
      end
    end
  end

  # STATEMENT 3 — every delta on every one of these rules.
  def adjustment_rows
    @adjustment_rows ||= begin
      ids = rules.map(&:id)
      ids.empty? ? {} : Adjustment.where(rule_id: ids).dated_within(window).pluck(:rule_id, :date, :amount).group_by(&:first)
    end
  end

  # THE SPENDING LANE, SHARED BY BOTH STATEMENTS — `Entry.draining`'s scope widened from one category
  # to "any category this entry could drain", which is what `ENTRY_CATEGORY_ID IS NOT NULL` says: the
  # income arm, the never-funded arm and the before-funding arm all answer NULL, so what is left is
  # exactly the spending that counts against some envelope.
  def draining
    Entry.expenses
      .joins(*CategoryLedger::ENTRY_CATEGORY_JOINS)
      .where("#{CategoryLedger::ENTRY_CATEGORY_ID} IS NOT NULL")
      .where(entries: { date: window })
  end
end
