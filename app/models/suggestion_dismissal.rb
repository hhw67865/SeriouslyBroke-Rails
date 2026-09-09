# frozen_string_literal: true

# ONE SUGGESTION THIS USER HAS PUT DOWN (Henry's ruling of 2026-08-20). See the migration for why
# the table exists at all, and `app/views/budget_page/_suggestions.html.erb` for the design it
# reverses.
#
# THE ROW IS THE PAIR `SuggestionEngine` KEYS ON — kind and subject — and nothing else. There is no
# amount, no date and no snapshot of the sentence: a suggestion is a derivation, so a hidden one
# whose figures move is still the same hidden suggestion, and a hidden one that stops being
# detected simply stops being listed. That is the whole reason this can be a two-column fact.
#
# WHAT IT DOES NOT VALIDATE IS OWNERSHIP OF THE SUBJECT, and that line is drawn where
# `BudgetsController` draws it: whose record it is belongs to the controller, which looks the
# subject up through `current_user` and so cannot be handed a stranger's; what SHAPE the row may
# take is here. Duplicating the ownership question would give the invariant two places to be wrong
# and would make `SuggestionDismissal.create!` unusable for planting the very row the request spec
# needs to prove the engine's lookup is user-scoped.
class SuggestionDismissal < ApplicationRecord
  belongs_to :user
  belongs_to :subject, polymorphic: true

  # THE FOUR DETECTORS' NAMES, spelled as strings because that is what `subjects.kind` holds and
  # what the wire carries. Not an enum: `SuggestionEngine::Suggestion#kind` is a SYMBOL and the
  # engine's own `KIND_RANK` is the list of them, so an integer mapping here would be a third
  # spelling of a set that already has two.
  KINDS = ["dated_bill", "rate", "drift", "dead_rule"].freeze

  # THE THREE CLASSES A SUBJECT CAN BE, and this list is a security boundary rather than tidiness:
  # `subject_type` arrives off the wire, and a polymorphic type constantized from user input is how
  # a hidden button becomes a class loader. The controller refuses anything not named here before
  # it looks anything up.
  SUBJECT_TYPES = ["Item", "Category", "Budget"].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :subject_type, inclusion: { in: SUBJECT_TYPES }
  validates :subject_id, uniqueness: { scope: [:user_id, :kind, :subject_type] }

  # THE KEY THE ENGINE MATCHES ON, spelled once so the writer and the reader cannot disagree about
  # its shape. `subject.class.name` on the engine's side and `subject_type` here are the same
  # string for every subject this app has — none of the three is STI — and the comparison is made
  # against this method rather than against three loose values at each call site.
  def key = [kind, subject_type, subject_id]
end
