# frozen_string_literal: true

# ONE SUGGESTION THE USER HAS TOLD THE PANEL TO STOP SHOWING (Henry's ruling of 2026-08-20).
#
# THIS TABLE REVERSES §8's RECORDED DESIGN. `SuggestionEngine`'s own header said there was no
# table and no dismissed state, because "a dismissal is state, and the state it would hide is
# drift"; real use answered that a panel with no way to put a row down is a panel that gets
# ignored whole, which hides everything. The argument and the ruling are written out in
# `app/views/budget_page/_suggestions.html.erb`, beside the section they govern.
#
# NOT A COLUMN ON THE SUBJECT. A suggestion has no row of its own — it is a DERIVATION, which is
# the one thing about §8 that has not changed — so what is stored is the (user, kind, subject)
# pair the derivation would produce, and nothing else. An `Item` gains no `dismissed_at`, so a
# bill hidden as a dated bill is still free to be proposed as something else later.
#
# POLYMORPHIC because the four detectors have three different subjects between them: an Item for a
# dated bill, a Category for a rate, a Budget for drift and for a dead rule.
#
# THE UNIQUE INDEX IS THE REAL LATCH, not the validation in front of it: two clicks on one Hide
# button — a double-click, a resubmit before the redirect lands — must not write two rows that
# then need the "Show" button pressed twice.
class CreateSuggestionDismissals < ActiveRecord::Migration[8.1]
  def change
    create_table :suggestion_dismissals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :subject, type: :uuid, null: false, polymorphic: true
      t.string :kind, null: false
      t.timestamps
    end

    add_index :suggestion_dismissals,
              [:user_id, :kind, :subject_type, :subject_id],
              unique: true,
              name: "index_suggestion_dismissals_on_user_and_subject"
  end
end
