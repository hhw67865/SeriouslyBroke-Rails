# frozen_string_literal: true

# THE "YOU CHANGED A RULE HERE AFTER DISTRIBUTING" FIXTURE, IN ONE PLACE.
#
# Spec §8's rough edge is asserted on FOUR screens — the Budget page's rule list, Home's category
# rows, the category page's budget block and its pool card — because each renders the clause
# through a different reader. The fixture behind all four is one recipe, and it was hand-rolled
# four times: two of the copies drifted, and BOTH drifts were the same wall-clock flake.
#
# WHAT THE RECIPE IS. The clause compares `budgets.updated_at` against the movement's `created_at`,
# so both have to be written the way the app writes them — never `update_column`, never a
# hand-set `date` standing in for a timestamp (a period marker compared to a timestamp is a unit
# mismatch; see `DistributionClock`). Three controlled moments, in order:
#
#   3 hours ago   the envelope and its rule are created
#   2 hours ago   the distribution moves money into it
#   1 hour ago    the rule is raised
#
# and the movement is DATED on today, which is a period marker rather than a timestamp.
#
# WHY IT KEEPS BREAKING, AND THE ONE LINE THAT FIXES IT. `Date.current` read INSIDE a `travel_to`
# is the travelled day: two or three hours back, between midnight and 03:00 UTC, that is
# YESTERDAY. A movement dated a day early falls in the previous period, `DistributionClock` —
# correctly bounded to the period the page renders — does not see it as this period's
# distribution, and every positive example fails for the first hours of every UTC day against an
# app that is working perfectly. That is exactly the flake commit 437eabd diagnosed, in two files
# whose comments already SWORE the date was captured at real now.
#
# The second half of that lesson is why `before { today }` is here and is not decoration: `let` is
# LAZY, so a `let(:today) { Date.current }` first read from inside a `travel_to` resolves to the
# travelled day no matter what its comment claims. The `before` forces it at real now, outside
# every block below. A shared context is the only version of this that a fifth screen cannot get
# wrong by copying.
#
# Assertions stay in the files that own their screens; only the clock does not.
RSpec.shared_context "with a rule changed after the money went out" do
  include ActiveSupport::Testing::TimeHelpers

  # THE PERIOD DAY every date in the fixture is derived from — resolved ONCE, at real now.
  let(:today) { Date.current }

  before { today }

  # The envelope and its rule are written here, three hours back, so the rule's `updated_at` is
  # unambiguously older than the distribution's `created_at`.
  def before_distributing(&) = travel_to(3.hours.ago, &)

  # ── `#distribute` IS DELETED (Task 6) with `DistributionClock`'s `account_ids:` surface. It wrote
  # a `PoolMovement` with `kind: :allocation` from an account into an envelope, which was what the
  # pool-era arm read; there is one root and one distribution per period now (two-ledger spec §2), so
  # every screen that prints this clause reads `Allocation.distributed` through `#allocate` below.

  # THE PURPOSE-LEDGER TWIN (two-ledger spec §2), for the screens that have moved. An allocation
  # names no account — it moves money between the user's one root and a category — so there is no
  # `from:` to say and `DistributionClock`'s category arm reads `Allocation.distributed` rather
  # than `PoolMovement.distributed`. Everything else about the recipe is unchanged, which is the
  # whole reason this lives here: the three controlled moments and the `today` resolved at real now
  # are what the two arms have in common and what kept being got wrong when they were hand-rolled.
  def allocate(category, amount)
    travel_to(2.hours.ago) do
      create(:allocation, kind: :allocation, to_category: category, amount: amount, date: today)
    end
  end

  # The edit the clause is about. Anything written in here is newer than the distribution.
  def after_distributing(&) = travel_to(1.hour.ago, &)
end
