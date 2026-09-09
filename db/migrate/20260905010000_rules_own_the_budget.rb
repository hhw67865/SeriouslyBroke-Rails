# frozen_string_literal: true

# THE TARGET MOVES ONTO THE RULE, AND EVERY RULE LEARNS WHAT KIND OF RULE IT IS (rules-own-the-budget
# spec §6, Henry's rulings of 2026-09-04).
#
# THE DATA HALF. `RulesOwnTheBudgetColumns` (20260905000000) added `budgets.carries_over`,
# `budgets.target_amount` and `budgets.rule_type` and did nothing else; this file fills them in from
# what the database already knows and takes `categories.target_amount` away. Two files rather than
# one because they are two different kinds of statement — a column added is a column dropped, while
# this `down` has to copy a figure back the other way and can only be written once the column it
# copies FROM exists — and because the first half had already run on the test database by the time
# this half was written. A migration edited after it has run cannot re-run; a second file keeps both
# environments migrated by the ordinary path.
#
# ---------------------------------------------------------------------------------------------
# WHAT MOVES, AND ONTO WHICH RULE
# ---------------------------------------------------------------------------------------------
#
# A GOAL WAS A CATEGORY WITH A FIGURE ON IT; IT IS A RULE THAT CARRIES ITS MONEY OVER AND NAMES A
# CEILING. `ClaimCalculator#shape` read `categories.target_amount` to decide which of §3's formulas a
# rule took, which made one rule's arithmetic a fact about a NEIGHBOURING record: two rules on one
# goal category both accrued toward the same figure, clearing the category's figure silently turned a
# saved-up fund into a use-it-or-lose-it rate, and no rule could say "build up without limit" at all.
#
# THE TARGET LANDS ON THE CATEGORY'S ITEM-LESS RULE — computed-claims §3.1's lane partition, the same
# arm `DropTheDistribution` put every converted set-aside on. An item-backed rule speaks for ONE
# item's spending, so a fund carved out for the flights line is not what the CATEGORY is building up.
# `CATEGORY_LANE` picks it, and it picks the OLDEST where a legacy database holds two: that is the
# rule whose accrual window reaches furthest back, and it is the same tie-break the earlier migration
# made, so the two files cannot disagree about which rule is the category's own.
#
# A TARGET CATEGORY WITH NO ITEM-LESS RULE GETS ONE MINTED, in §2.1 row 4's shape — amount zero,
# per-period, no anchor, no interval, carries over, the category's target. Every claim comes from a
# rule (§3.3), so a goal that has never had one has to BE one or its figure has nowhere to live once
# the column is gone.
#
# THE MINTED RULE IS BORN NO LATER THAN THE DAY ITS CATEGORY STARTED HOLDING MONEY, for
# `DropTheDistribution#birthday_for`'s reason: `ClaimCalculator#accrual_start` is `max(funded_since,
# the rule's birthday)`, so a rule minted TODAY starts its fund counting today while the category has
# been holding money since `funded_since` — and a set-aside the user later dates back into that
# history would land outside every period the walk visits. Midnight UTC on the funding day is on or
# before that day in every zone.
#
# ---------------------------------------------------------------------------------------------
# WHAT EVERY RULE'S TYPE IS ON THE MORNING AFTER THIS RUNS
# ---------------------------------------------------------------------------------------------
#
# `bill` FOR A DATED RULE, `usage` FOR EVERYTHING ELSE (spec §6.3). A rule with an `anchor_date` is a
# thing that falls due on a day — a premium, the rent, the tax estimate — which is what `bill` means;
# everything else keeps the column's own default. `usage` is the widest of the three ("a real need
# whose amount moves with how you live"), so a rule typed by nobody claims neither that it must be
# paid nor that it is discretionary. The Budget page prints the label and the give-way order reads
# it, so the default is visible to the user who has to correct it, and `RuleForm` is the door they
# correct it through.
#
# TYPED UNCONDITIONALLY RATHER THAN ONLY WHERE THE DEFAULT SURVIVES, and the reason is a fact about
# the sequence rather than a preference: `rule_type` is one day old when this runs, and the form that
# writes it ships in the same branch, so on any database this file can meet there is no user-chosen
# type for an unconditional UPDATE to overwrite. §6.3 is a sentence about every rule, and this is it.
#
# ---------------------------------------------------------------------------------------------
# WHAT "THE CLAIM IS IDENTICAL BEFORE AND AFTER" MEANS, AND WHY IT IS ASSERTED IN THE SPEC
# ---------------------------------------------------------------------------------------------
#
# It cannot be a comparison against the schema this file starts from, and saying why is the whole of
# the care here. `ClaimCalculator` ALREADY reads the rule (Task 1 moved it), so on the pre-migration
# schema a goal category's rule has no `target_amount` yet and reads as an UNCAPPED RATE rule —
# `:rate`, use-it-or-lose-it, built-up zero. Comparing against that would be pinning a figure the
# computed-claims era never produced and that no screen ever showed.
#
# THE FIGURE THAT MUST SURVIVE IS THE COMPUTED-CLAIMS ERA'S: what `ClaimCalculator` answered while
# `#shape` still read `categories.target_amount` — the §3.2 walk, capped at the CATEGORY's figure.
# `spec/migrations/rules_own_the_budget_spec.rb` re-derives each of those from §3's formula in a
# comment, plants it as a literal, and asserts the post-migration calculator against it. A migration
# cannot ask that question of itself: it would need two versions of one class in one process.
#
# WHAT THIS FILE VERIFIES INSTEAD, in SQL of its own: the PHYSICAL invariant (`pot + Σ accounts ==
# income − expenses`) per user, unchanged — this file writes no entry, no account movement and no
# pool at all, and a migration that cannot move a number is exactly the one that should be made to
# prove it; that every target that existed is now held by a building rule with the same figure; and
# that every row it wrote or touched is a shape `Budget` itself would accept (see #malformed_rules).
#
# ---------------------------------------------------------------------------------------------
# A RE-RUN RAISES, LOUDLY AND ON PURPOSE
# ---------------------------------------------------------------------------------------------
#
# `up` drops `categories.target_amount`, so a second run without the `down` reaches `#dated_targets`
# — the first statement past `#ledgers` — and gets `PG::UndefinedColumn` from Postgres itself.
# `DropTheDistribution`'s ruling, inherited: the alternative is a guard that turns a second run into
# a silent no-op, and a silent no-op is indistinguishable from a run that moved nothing because there
# was nothing to move. The whole of `up` is one transaction (the Migrator wraps it on PostgreSQL,
# DDL included), so there is never anything half-done to resume, and an operator re-running this file
# is on the wrong database and wants a stack trace rather than a shrug.
#
# ---------------------------------------------------------------------------------------------
# THE `down` RESTORES THE COLUMN AND THE FIGURE, AND LEAVES THE RULE'S COLUMNS WHERE THEY ARE
# ---------------------------------------------------------------------------------------------
#
# `spec/support/schema_rewind.rb` names this file, so four migration specs travel back through it to
# reach the world their own subjects were written for — `CategoriesHoldTheMoney#down` REMOVES
# `categories.target_amount` and `DropTheDistribution#up` READS it, and neither can run against a
# schema this file has emptied. So the column comes back and every building rule's target is copied
# onto its category, which is the figure those files knew.
#
# THE THREE RULE COLUMNS ARE NOT TOUCHED, because `RulesOwnTheBudgetColumns#down` owns them: a `down`
# that dropped a column it did not add would make `db:rollback STEP=1` and `STEP=2` disagree about
# what the schema is. A rolled-back database therefore carries the figure in BOTH places for as long
# as it stays there, which is the honest state of a half-rewound sequence and is exactly what the
# round-trip example asserts by diffing `db/schema.rb` after `rollback` + `migrate`.
class RulesOwnTheBudget < ActiveRecord::Migration[8.1]
  # The integers as the schema holds them at THIS moment in the sequence, written out rather than
  # read off the app's enums — `DropTheDistribution`'s law: a migration whose meaning changes when a
  # model does is a migration that rewrites history.
  PER_PERIOD = 1 # budgets.basis
  MONTHLY = 0 # budgets.basis
  BILL = 0 # budgets.rule_type
  USAGE = 1 # budgets.rule_type
  EXPENSE = 0 # categories.category_type
  ACCOUNT = 0 # pools.pool_type
  INCOME = 1 # categories.category_type

  # Refusing the INPUT — raised before the first write.
  class PreflightFailed < StandardError; end

  # Refusing its own OUTPUT — raised after the last write and before the drop, inside the Migrator's
  # transaction, so a database whose rules stopped being shapes the app accepts is never committed.
  class VerificationFailed < StandardError; end

  # ** THE CATEGORY'S OWN LANE — ONE RULE PER CATEGORY, CHOSEN THE SAME WAY TWICE. ** `DISTINCT ON`
  # with the oldest first, so a lane resolves identically on every run and a diff of two runs against
  # one backup is a usable audit.
  #
  # ** IT IS NOT WHAT HANDLES A DUPLICATE LANE — `#duplicate_lanes` REFUSES THAT OUTRIGHT. ** This
  # `DISTINCT ON` would silently pick the older of two catch-all rules and leave the younger beside
  # it, and picking one of a user's two rules is a decision about their money rather than a tie-break.
  # The clause stays because the preflight arm is what makes it single-valued: with the refusal in
  # front of it, every group this selects from has exactly one row, and the `ORDER BY` is what says
  # so out loud rather than leaving a reader to assume it.
  CATEGORY_LANE = <<~SQL.squish
    SELECT DISTINCT ON (category_id) id FROM budgets
     WHERE item_id IS NULL ORDER BY category_id, created_at, id
  SQL

  # THE DROP IS LAST AND #verify! IS SECOND TO LAST, AND BOTH POSITIONS ARE LOAD-BEARING. #verify!
  # READS `categories.target_amount` — proving every figure reached a rule is what makes "nothing was
  # lost" a measured fact rather than an intention — so it cannot run after the column is gone. And
  # the whole of `up` is one transaction, so a raise from it rolls the mint, the move and the typing
  # back together.
  def up
    before = ledgers
    preflight!
    receipts = { moved: move_the_targets, minted: mint_the_missing_rules }
    verify!(before, receipts.merge(bill: type_the_rules))
    remove_column :categories, :target_amount
  end

  # SHAPE AND FIGURE, NOT HISTORY. A rule this file minted stays where it is and every rule keeps the
  # type it was given: those are the app's rows now, and a `down` that deleted them would take a
  # user's own edits with them. What comes back is the column four older migration specs read and
  # the number it held.
  # NO `DISTINCT ON` TIE-BREAK ON THE COPY-BACK, and it needs none: `#duplicate_lanes` refuses a
  # category with two item-less rules before `up` writes anything, so no database this `down` can
  # meet has two building rules on one category for the UPDATE to pick between.
  def down
    add_column :categories, :target_amount, :money, scale: 2

    execute(<<~SQL.squish)
      UPDATE categories c
         SET target_amount = b.target_amount, updated_at = NOW()
        FROM budgets b
       WHERE b.category_id = c.id
         AND b.item_id IS NULL
         AND b.carries_over
         AND b.target_amount IS NOT NULL
    SQL
  end

  private

  # -----------------------------------------------------------------------------------------------
  # The refusals
  # -----------------------------------------------------------------------------------------------

  # ** FIVE ARMS, AND EVERY ONE OF THEM RUNS BEFORE THE FIRST WRITE. ** Two of these started life on
  # the OTHER side of the run — as disjuncts of `#malformed_rules`, which fires after every statement
  # has already gone in — and that placement was wrong twice over. It reports a shape this file could
  # have seen coming under the generic sentence "a shape the app would refuse", and it makes the
  # operator read a `VerificationFailed` rollback where the honest message is "this database is not
  # convertible yet". `CategoriesHoldTheMoney`'s two classes exist for exactly that split: "is this
  # database convertible" and "did the conversion go wrong" need different work from whoever reads
  # the message.
  def preflight!
    failures = dated_targets + unfundable_targets + unusable_targets +
               duplicate_lanes + meaningless_zero_rules
    return if failures.empty?

    raise PreflightFailed, failures.join("; ")
  end

  # ** A CATEGORY WITH TWO ITEM-LESS RULES, NAMED BEFORE ANYTHING MOVES. **
  # `Budget#category_may_hold_one_item_less_rule` is younger than the data it guards, so a real
  # database can carry two catch-all rules on one category — `SuggestionEngine
  # #attributable_rate_rules` keeps its own `rules.one?` guard for the same reason.
  #
  # ** THIS RUN CANNOT HEAL IT AND MUST NOT PRETEND TO. ** `CATEGORY_LANE` would hand the target to
  # the OLDER of the two and leave the younger beside it, so the category would come out of this
  # migration with one catch-all holding a fund and another claiming the same lane — a pair
  # `#malformed_rules` then refuses at the far end of the run, under a sentence that names neither
  # rule as the other's twin. Which of the two the user meant is a decision about their money: the
  # older one is where the fund would land, the younger one may be the one they actually edit.
  #
  # BOTH IDS ARE NAMED, because "keep one" is not actionable without them. The pair is reported once,
  # not once per row: `string_agg` over the category's item-less rules, ordered so two runs against
  # one backup produce the same message.
  def duplicate_lanes
    template = "%<extra>s has two rules with no item (%<id>s) — they share one lane, so the " \
               "category's target has no single rule to move onto; keep one"
    named(<<~SQL.squish, template)
      SELECT string_agg(b.id::text, ', ' ORDER BY b.created_at, b.id) AS id, c.name AS extra, u.email
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE b.item_id IS NULL
       GROUP BY c.id, c.name, u.email
      HAVING COUNT(*) > 1
       ORDER BY u.email, c.name
    SQL
  end

  # ** A TARGET OF ZERO OR LESS, WHICH THE DATABASE WOULD OTHERWISE REFUSE WITHOUT NAMING ANYONE. **
  # `Category#target_is_a_goal` said "a goal of zero is already met and a negative one is money the
  # budget owes its owner", and `update_column` walks past it — `spec/requests/budget_page_spec.rb`
  # planted exactly that row to make a category already-invalid — so a legacy figure of `0` is a
  # shape a restore can be carrying.
  #
  # WITHOUT THIS ARM IT REACHES `budgets_positive_target_amount` (`RulesOwnTheBudgetColumns`' CHECK,
  # which is that same sentence re-stated on the new owner) and comes back as a `PG::CheckViolation`
  # naming a constraint, a table and nothing else: no owner, no category, no figure. Refused here it
  # names all three, and the fix is the one the message states.
  def unusable_targets
    template = "%<extra>s names a target of %<id>s, which is not a goal — a target of zero is " \
               "already met and a negative one is money the budget owes its owner"
    named(<<~SQL.squish, template)
      SELECT c.target_amount::text AS id, c.name AS extra, u.email
        FROM categories c
        JOIN users u ON u.id = c.user_id
       WHERE c.target_amount IS NOT NULL
         AND c.target_amount <= 0::money
       ORDER BY u.email, c.name
    SQL
  end

  # ** A TARGET CATEGORY WHOSE CATCH-ALL RULE HAS A DUE DATE. ** `Budget#build_up_must_be_valid`
  # refuses `carries_over` on a rule with an `anchor_date` — a dated rule's build-up is already
  # defined BY its date, and `ClaimCalculator#shape` would have two answers to "what becomes of money
  # this period did not spend" — so the target cannot move onto it. There is no second rule to put it
  # on either: the category's lane is that one rule, and minting a second item-less rule beside it is
  # the shape `#category_may_hold_one_item_less_rule` refuses.
  #
  # REFUSED RATHER THAN GUESSED, because both ways out are decisions about the user's money: either
  # the goal is really a dated bill and the target is redundant, or the rule should never have had a
  # date. An operator picks one and re-runs.
  def dated_targets
    template = "%<extra>s's catch-all rule (%<id>s) has a due date, so the category's target " \
               "cannot move onto it — a dated rule's build-up is defined by its date"
    named(<<~SQL.squish, template)
      SELECT b.id::text AS id, c.name AS extra, u.email
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE c.target_amount IS NOT NULL
         AND b.anchor_date IS NOT NULL
         AND b.id IN (#{CATEGORY_LANE})
       ORDER BY u.email, c.name
    SQL
  end

  # ** A TARGET ON A CATEGORY THAT CANNOT HOLD MONEY AT ALL. ** `Category#only_expenses_hold_money`
  # refuses the pair today, so this arm is about a database older than that validation or one whose
  # `category_type` was flipped afterwards — and it has to be refused rather than skipped, because
  # `Budget#category_must_be_an_expense` would refuse the rule that has to carry the figure. Skipping
  # it would drop the column with the number still on it.
  #
  # `<> EXPENSE` RATHER THAN `= INCOME`, matching the enum from the other side than
  # `#category_must_be_an_expense` does: this clause is about which categories a rule may be MINTED
  # on, and a third type added later is one nothing here knows how to fund.
  def unfundable_targets
    template = "%<extra>s (%<id>s) carries a target but is not an expense category, and only an " \
               "expense category may hold a rule to move it onto"
    named(<<~SQL.squish, template)
      SELECT c.id::text AS id, c.name AS extra, u.email
        FROM categories c
        JOIN users u ON u.id = c.user_id
       WHERE c.target_amount IS NOT NULL
         AND c.category_type <> #{EXPENSE}
       ORDER BY u.email, c.name
    SQL
  end

  # ** A $0 RULE THAT WILL STILL BE A $0 RULE AFTER THE TARGETS HAVE MOVED, WHICH IS A SHAPE THE APP
  # REFUSES (Task 1's carry). ** `Budget#set_aside_only?` is the one exemption from `amount > 0`, and
  # since Task 1 it names all three of the RULE's own columns: carries over, names a target, has no
  # due date. `DropTheDistribution#mint_rule` wrote its zeroes against the CATEGORY's target — legal
  # at its own moment in the sequence, refused by the model from the day the columns landed — so
  # every one of those rows is a row this file has to repair, and #move_the_targets does exactly
  # that: they are item-less rules on categories that name a figure.
  #
  # WHAT IS LEFT AFTER THAT REPAIR IS A RULE THAT DEMANDS NOTHING AND BUILDS TOWARD NOTHING, and
  # there is no honest guess to make about it. Inventing a target would be inventing the user's goal;
  # giving it an amount would be inventing a standing contribution they never declared. The two ways
  # out are a decision about money — name the goal, or delete the rule — so the row is named and the
  # run refuses.
  #
  # THE SECOND DISJUNCT IS #move_the_targets' OWN PREDICATE, restated: a rule is repaired by this run
  # exactly when it is the category's chosen lane and the category names a figure.
  def meaningless_zero_rules
    template = "the $0 rule on %<extra>s (%<id>s) names no target and would build toward nothing " \
               "— give it a target or delete it"
    named(<<~SQL.squish, template)
      SELECT b.id::text AS id, c.name AS extra, u.email
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE b.amount = 0::money
         AND NOT (b.anchor_date IS NULL
                  AND ((b.carries_over AND b.target_amount IS NOT NULL)
                    OR (c.target_amount IS NOT NULL AND b.id IN (#{CATEGORY_LANE}))))
       ORDER BY u.email, c.name
    SQL
  end

  # `%<extra>s` is optional in the template, so one helper serves an arm that names a second fact and
  # one that does not — `DropTheDistribution#named`, and `format` ignores a surplus key under the
  # `%<name>s` spelling where `%{}` would raise.
  def named(sql, template)
    select_all(sql).map do |row|
      "#{row["email"]}: #{format(template, id: row["id"], extra: row["extra"])}"
    end
  end

  # -----------------------------------------------------------------------------------------------
  # The move
  # -----------------------------------------------------------------------------------------------

  # ** THE TARGET ONTO THE RULE, IN ONE STATEMENT, WITH THE OWNERS COUNTED BY THE SAME STATEMENT. **
  # A data-modifying CTE is what keeps the receipt and the write one fact: an `UPDATE` followed by a
  # `SELECT COUNT` would be counting rows by a predicate the update is no longer scoped by, and a
  # second run of that predicate is a second chance to write it differently.
  #
  # `carries_over` AND THE FIGURE TOGETHER, because they are one declaration: §2.1's building shape is
  # "unspent money survives the boundary, and here is where it stops". Setting the figure without the
  # flag would be `#build_up_must_be_valid`'s second refusal — a cap on money that resets.
  def move_the_targets
    tally(<<~SQL.squish)
      WITH moved AS (
        UPDATE budgets b
           SET carries_over = TRUE, target_amount = c.target_amount, updated_at = :now
          FROM categories c
         WHERE c.id = b.category_id
           AND c.target_amount IS NOT NULL
           AND b.id IN (#{CATEGORY_LANE})
        RETURNING c.user_id
      )
      SELECT u.email, COUNT(*) AS n FROM moved JOIN users u ON u.id = moved.user_id
       GROUP BY u.email
    SQL
  end

  # ** THE TARGET-ONLY SHAPE (§2.1 row 4), FOR A GOAL THAT HAS NO RULE AT ALL. ** Amount zero, no
  # anchor, no interval, per-period basis, no item, carries over, the category's figure.
  # `Budget#set_aside_only?` is the predicate that permits the zero and it names all three of those
  # columns; `#shape_must_be_valid` is what forces the basis, since a MONTHLY rule with neither an
  # anchor nor an interval is refused outright.
  #
  # `rule_type` IS WRITTEN EXPLICITLY RATHER THAN LEFT TO THE COLUMN DEFAULT. A default is a fact
  # about the schema on the day this runs, and #type_the_rules below states §6.3's sentence about
  # every other row; a minted row that read its type from somewhere else would be the one row in the
  # table whose type this file did not decide.
  #
  # See the header for `created_at`: a rule minted today would start its category's fund counting
  # today, and the goal has been holding money since `funded_since`.
  def mint_the_missing_rules
    tally(<<~SQL.squish)
      WITH minted AS (
        INSERT INTO budgets (id, category_id, item_id, amount, basis, anchor_date, interval_months,
                             carries_over, target_amount, rule_type, created_at, updated_at)
        SELECT gen_random_uuid(), c.id, NULL, 0::money, #{PER_PERIOD}, NULL, NULL,
               TRUE, c.target_amount, #{USAGE},
               COALESCE(c.funded_since::timestamp, :now), :now
          FROM categories c
         WHERE c.target_amount IS NOT NULL
           AND NOT EXISTS (SELECT 1 FROM budgets b
                            WHERE b.category_id = c.id AND b.item_id IS NULL)
        RETURNING category_id
      )
      SELECT u.email, COUNT(*) AS n
        FROM minted
        JOIN categories c ON c.id = minted.category_id
        JOIN users u ON u.id = c.user_id
       GROUP BY u.email
    SQL
  end

  # ** `bill` WHERE THERE IS A DATE, AND THE REST KEEP THE COLUMN'S `usage` (§6.3). ** Only the
  # anchored rows are counted, because only the anchored rows are WRITTEN: an anchorless rule is
  # `usage` because the column's default made it so before this statement ran, and counting it as
  # something this migration did would be claiming a write that never happened. See #report for the
  # figure that IS this run's usage.
  def type_the_rules
    bills = tally(<<~SQL.squish)
      WITH typed AS (
        UPDATE budgets SET rule_type = #{BILL}, updated_at = :now
         WHERE anchor_date IS NOT NULL
        RETURNING category_id
      )
      SELECT u.email, COUNT(*) AS n
        FROM typed
        JOIN categories c ON c.id = typed.category_id
        JOIN users u ON u.id = c.user_id
       GROUP BY u.email
    SQL

    bills
  end

  # Email -> count, from a statement that already grouped by email. `Hash.new(0)` so the report can
  # ask every user for every figure without four `dig`s and a nil guard per line.
  def tally(sql)
    counts = Hash.new(0)
    select_all(ActiveRecord::Base.sanitize_sql_array([sql, { now: now }])).each do |row|
      counts[row["email"]] = row["n"].to_i
    end
    counts
  end

  # -----------------------------------------------------------------------------------------------
  # The verification, and the receipt
  # -----------------------------------------------------------------------------------------------

  def verify!(before, receipts)
    failures = drift(before) + targets_left_behind + malformed_rules
    raise VerificationFailed, failures.join("; ") if failures.any?

    report(before, receipts)
  end

  # EVERY USER, ON BOTH SIDES, AND THE COMPARISON IS AGAINST THE PRE-MIGRATION FIGURE rather than
  # against bank truth alone — `DropThePoolLayer#verify!`'s reason: a change that moved money from
  # one term into the other by the same amount would satisfy "physical == bank" and still be wrong.
  def drift(before)
    after = ledgers
    before.flat_map do |id, was|
      now_figures = after[id]
      next ["#{was[:email]}: vanished from the users table"] if now_figures.nil?

      [:physical, :bank].filter_map do |side|
        next if was[side] == now_figures[side]

        "#{was[:email]}: #{side} was #{was[side].to_f}, is #{now_figures[side].to_f}"
      end
    end
  end

  # ** EVERY FIGURE THAT EXISTED IS HELD BY A RULE, ASKED WHILE THE COLUMN IS STILL THERE TO ASK. **
  # This is the one statement that makes "nothing was lost" a fact: the column is dropped in the next
  # line, and a target that reached no rule would leave with it and nobody would ever know it had
  # been there. The comparison is on the FIGURE and not merely on the rule's existence, so a move
  # that landed the wrong number is caught by the same clause as one that landed none.
  def targets_left_behind
    template = "%<extra>s's target (%<id>s) reached no rule"
    named(<<~SQL.squish, template)
      SELECT c.target_amount::text AS id, c.name AS extra, u.email
        FROM categories c
        JOIN users u ON u.id = c.user_id
       WHERE c.target_amount IS NOT NULL
         AND NOT EXISTS (SELECT 1 FROM budgets b
                          WHERE b.category_id = c.id
                            AND b.item_id IS NULL
                            AND b.carries_over
                            AND b.target_amount = c.target_amount)
       ORDER BY u.email, c.name
    SQL
  end

  # ** `Budget`'s VALIDATIONS, RESTATED IN SQL — CLAUSE FOR CLAUSE, AND NO CLAUSE MORE. ** Every
  # disjunct below names the model method it mirrors:
  #
  #   * `carries_over AND anchor_date IS NOT NULL` — `#build_up_must_be_valid`, first clause;
  #   * `target_amount IS NOT NULL AND NOT carries_over` — its second (a cap on money that resets);
  #     (`validates :target_amount, numericality: { greater_than: 0 }` is DELIBERATELY NOT here: the
  #     only non-positive figure that could reach a rule is a category's, `#unusable_targets` refuses
  #     that before the first write, and `budgets_positive_target_amount` stands behind both — a
  #     disjunct this file cannot reach reads as a check somebody is relying on);
  #   * `amount = 0 AND NOT (carries_over AND target_amount IS NOT NULL AND anchor_date IS NULL)` —
  #     `#set_aside_only?` and the two `amount` numericality rules it gates;
  #   * the two basis clauses — `#shape_must_be_valid`, both branches: a per-period rule carries
  #     neither anchor nor interval, and an anchorless MONTHLY rule needs an interval of exactly 1;
  #   * `category_type = INCOME` — `#category_must_be_an_expense`, which asks `category&.income?`
  #     rather than `!expense?` for the reason stated at the model;
  #   * the gated `EXISTS` — `#category_may_hold_one_item_less_rule`, INCLUDING its
  #     `return if item_id.present?`, which is what makes the mint's own arithmetic checkable.
  #
  # `rule_type` PRESENCE IS DELIBERATELY NOT RESTATED: the column is `NOT NULL` with a default, so
  # Postgres already says the same sentence more strongly than a disjunct could, and a clause that
  # can never match reads as a check somebody is relying on.
  #
  # ** SCOPED TO THE POPULATION THIS FILE IS ANSWERABLE FOR, WHICH IS NOT EVERY ROW IN THE TABLE. **
  # `DropTheDistribution#malformed_minted_rules` learned this the hard way from the other side: a
  # verifier stricter than the model aborted a whole migration over a row the app accepts, and being
  # wrong in that direction is the one nobody can work around. The scope here is the rules this run
  # wrote to or created — those that carry over, name a target, or demand nothing — which is exactly
  # the set whose shape is this file's responsibility. A legacy rule it never touched is left to the
  # form that will next open it.
  def malformed_rules
    named(<<~SQL.squish, "the rule on %<extra>s is a shape the app would refuse (%<id>s)")
      SELECT b.id::text AS id, c.name AS extra, u.email
        FROM budgets b
        JOIN categories c ON c.id = b.category_id
        JOIN users u ON u.id = c.user_id
       WHERE (b.carries_over OR b.target_amount IS NOT NULL OR b.amount = 0::money)
         AND ((b.carries_over AND b.anchor_date IS NOT NULL)
           OR (b.target_amount IS NOT NULL AND NOT b.carries_over)
           OR (b.amount = 0::money
               AND NOT (b.carries_over AND b.target_amount IS NOT NULL AND b.anchor_date IS NULL))
           OR (b.basis = #{PER_PERIOD}
               AND (b.anchor_date IS NOT NULL OR b.interval_months IS NOT NULL))
           OR (b.basis = #{MONTHLY} AND b.anchor_date IS NULL
               AND (b.interval_months IS NULL OR b.interval_months <> 1))
           OR c.category_type = #{INCOME}
           OR (b.item_id IS NULL
               AND EXISTS (SELECT 1 FROM budgets o
                            WHERE o.category_id = b.category_id
                              AND o.item_id IS NULL AND o.id <> b.id)))
       ORDER BY u.email, c.name
    SQL
  end

  # ** ONE LINE PER USER THIS RUN WROTE SOMETHING FOR, plus the totals and the invariant. ** A
  # per-user receipt is what lets an operator match this run against the screens afterwards; a total
  # alone says only that something happened.
  #
  # ** EVERY FIGURE IS A COUNT OF ROWS THIS RUN WROTE, WHICH IS NARROWER THAN IT FIRST READ. ** The
  # usage figure was a CENSUS — `SELECT COUNT(*) … WHERE rule_type = usage` after the typing — so a
  # user whose rules this migration barely touched read "0 typed bill, 9 typed usage" about nine rows
  # it had not written a byte of. `usage` is the column's DEFAULT (§6.3), so an anchorless rule was
  # already `usage` before the UPDATE ran: the only rows this file typed usage are the ones it
  # MINTED, which is why the two are one clause here rather than two figures that happen to agree.
  #
  # PLURALS, because a receipt is read by a person: "1 targets moved" is the kind of line that makes
  # a reader wonder what else the file is careless about.
  def report(before, receipts)
    receipts.values.flat_map(&:keys).uniq.sort.each do |email|
      say "#{email}: #{count(receipts[:moved][email], "target")} moved onto rules; " \
          "#{count(receipts[:minted][email], "rule")} minted and typed usage; " \
          "#{count(receipts[:bill][email], "rule")} typed bill"
    end
    say "#{count(total(receipts[:moved]), "target")} moved onto rules; " \
        "#{count(total(receipts[:minted]), "rule")} minted and typed usage; " \
        "#{count(total(receipts[:bill]), "rule")} typed bill; " \
        "every other rule kept the column's usage default"
    before.each_value { |was| say "#{was[:email]}: physical #{was[:physical].to_f} == bank #{was[:bank].to_f}, unchanged" }
  end

  def total(counts) = counts.values.sum

  def count(number, noun) = "#{number} #{noun.pluralize(number)}"

  # -----------------------------------------------------------------------------------------------
  # The physical invariant, before and after
  # -----------------------------------------------------------------------------------------------

  # `DropTheDistribution#ledgers`, verbatim and for its reason: read straight from the tables rather
  # than through `AccountLedger`, because asking a reader to referee a migration of its own tables
  # means a wrong term answers wrong on both sides of the comparison.
  def ledgers
    select_all("SELECT id, email FROM users ORDER BY created_at, id").to_h do |row|
      [row["id"], { email: row["email"], physical: physical_total(row["id"]), bank: bank_total(row["id"]) }]
    end
  end

  # `pot + Σ accounts`. Every account movement has both ends inside the user's own accounts, so the
  # two sums cancel and this equals bank truth — which is the invariant, said as an expression rather
  # than asserted.
  def physical_total(user_id)
    decimal(<<~SQL.squish, user_id)
      SELECT COALESCE((SELECT SUM(CASE WHEN c.category_type = #{INCOME}
                                       THEN e.amount::numeric ELSE -e.amount::numeric END)
                         FROM entries e
                         JOIN items i ON i.id = e.item_id
                         JOIN categories c ON c.id = i.category_id
                        WHERE c.user_id = :uid), 0)
           + COALESCE((SELECT SUM(m.amount::numeric) FROM account_movements m
                        WHERE m.to_pool_id IN (SELECT id FROM pools
                                                WHERE user_id = :uid AND pool_type = #{ACCOUNT})), 0)
           - COALESCE((SELECT SUM(m.amount::numeric) FROM account_movements m
                        WHERE m.from_pool_id IN (SELECT id FROM pools
                                                  WHERE user_id = :uid AND pool_type = #{ACCOUNT})), 0)
    SQL
  end

  def bank_total(user_id)
    decimal(<<~SQL.squish, user_id)
      SELECT COALESCE(SUM(CASE WHEN c.category_type = #{INCOME}
                               THEN e.amount::numeric ELSE -e.amount::numeric END), 0)
        FROM entries e
        JOIN items i ON i.id = e.item_id
        JOIN categories c ON c.id = i.category_id
       WHERE c.user_id = :uid
    SQL
  end

  # `BigDecimal(...to_s)` rather than the adapter's cast, for `CategoriesHoldTheMoney#decimal`'s
  # reason: `select_value` hands back a String for some numeric results and a BigDecimal for others
  # depending on the OID, and a money comparison must not depend on which.
  def decimal(sql, user_id)
    BigDecimal(select_value(ActiveRecord::Base.sanitize_sql_array([sql, { uid: user_id }])).to_s)
  end

  # ONE INSTANT FOR THE WHOLE RUN, memoised: it stamps every row this file writes, so two readings of
  # the clock would leave one statement's rows dated after another's for no reason a reader could
  # explain.
  def now = @now ||= Time.current
end
