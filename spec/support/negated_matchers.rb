# frozen_string_literal: true

# `not_change`, so that "nothing at all was written" can be said as ONE compound expectation.
#
# RSpec's `expect { }.not_to change(…)` takes a single matcher, and a block can only be run once —
# so pinning that a refused write left THREE tables alone otherwise needs three requests, and three
# requests is three different chances for one of them to have written something. The negated
# matcher lets the one request be checked against every table it could have touched:
#
#   expect { accept }.to not_change(Pool, :count).and not_change(Budget, :count)
#
# `RSpec/ChangeByZero` asks for exactly this spelling over `change(…).by(0)`, and it is the better
# one: `by(0)` reads as an assertion about a delta, and the fact being asserted is that there was
# no write at all.
RSpec::Matchers.define_negated_matcher :not_change, :change
