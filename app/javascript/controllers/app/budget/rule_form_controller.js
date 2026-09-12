import { Controller } from "@hotwired/stimulus"

// The reveals and the preview, both enhancement — except the card, which exists only where this
// controller runs, and which it asks the SERVER for through the form's own hidden Preview button.
export default class extends Controller {
  static targets = [
    "form",
    "amount",
    "subject",
    "subjectName",
    "newItemName",
    "intervalField",
    "anchorField",
    "repeatsField",
    "keepsField",
    "preview",
    "previewButton"
  ]

  // Long enough that typing "1200" is one request rather than four, short enough that the card is
  // not visibly behind the box.
  static DEBOUNCE_MS = 400

  // The CSS animation's own duration (`.preview-refreshed`), so the class comes off at the moment
  // the animation ends rather than while it is still running.
  static HIGHLIGHT_MS = 600

  connect() {
    this.revealPreview()
    if (this.hasFormTarget) this.refresh()
  }

  disconnect() {
    this.cancelPreview()
    this.cancelHighlight()
  }

  // One handler for every control. The reveals and the item picker are instant — they are facts
  // about what is already on screen — and the preview is debounced, because it is a request.
  changed(event) {
    this.refresh()
    this.selectNewRowIfTyped(event)
    this.syncSubjectName()
    this.schedulePreview()
  }

  refresh() {
    this.revealFields()
  }

  // ---- the item picker --------------------------------------------------------------------------

  // Typing a name is choosing "a new item": the field's own radio need not be clicked first.
  selectNewRowIfTyped(event) {
    if (!this.hasNewItemNameTarget || event?.target !== this.newItemNameTarget) return

    const row = this.subjectTargets.find((radio) => radio.value === "new")
    if (row) row.checked = true
  }

  // The sentence names whichever row is checked, off the row's own label rather than the value —
  // "new" and a blank item id both need a name a raw value could not carry.
  syncSubjectName() {
    if (!this.hasSubjectNameTarget) return

    const checked = this.subjectTargets.find((radio) => radio.checked)
    if (checked) this.subjectNameTarget.textContent = checked.dataset.subjectName
  }

  // ---- the reveals -----------------------------------------------------------------------------

  get schedule() {
    const checked = this.formTarget.querySelector('input[name="rule[schedule]"]:checked')
    return checked ? checked.value : "per_period"
  }

  // The checkbox's own state. `:checked` on the element rather than its `value`, which is the
  // constant "1" a checkbox submits when it is on and says nothing at all when it is off.
  get repeats() {
    const box = this.field("repeats")
    return box ? box.checked : false
  }

  get keeps() {
    const box = this.field("keeps")
    return box ? box.checked : false
  }

  revealFields() {
    const dated = this.schedule === "by_date"

    this.toggle(this.optional("anchorField"), dated)
    this.toggle(this.optional("repeatsField"), dated)
    this.toggle(this.optional("intervalField"), dated && this.repeats)
    this.allowKeeps(!dated)
    this.allowCap(!dated && this.keeps)
  }

  // Disabled and cleared rather than hidden: a box left ticked under a date is a 422 about a
  // control the user cannot reach. Nothing is stashed — that would re-tick a box last seen empty.
  allowKeeps(allowed) {
    const field = this.optional("keepsField")
    if (!field) return

    const box = this.field("keeps")
    if (box) {
      box.disabled = !allowed
      if (!allowed) box.checked = false
    }

    field.classList.toggle("opacity-50", !allowed)
  }

  // "Stop at" is a detail of Keeps, not of the schedule alone: `RuleForm#schedule_columns` only
  // keeps a typed cap when `keeps?` is true, so a cap left fillable with the box unticked would be
  // silently dropped on save. Cleared the same way the keeps box is under a date.
  allowCap(allowed) {
    const cap = this.field("cap")
    if (!cap) return

    cap.disabled = !allowed
    if (!allowed) cap.value = ""
  }

  optional(name) {
    return this[`has${name[0].toUpperCase()}${name.slice(1)}Target`] ? this[`${name}Target`] : null
  }

  // Nothing happens when the state already matches, which is what keeps `connect()` from clearing a
  // prefilled date on a form the server rendered correctly in the first place.
  toggle(field, visible) {
    if (!field || field.hidden === !visible) return

    field.hidden = !visible
    // Radios are left alone: a `value` is what the control MEANS, not what somebody typed.
    const typed = "input:not([type=radio]):not([type=checkbox]):not([type=hidden])"
    field.querySelectorAll(typed).forEach((input) => {
      if (visible) {
        if (input.dataset.stashedValue !== undefined) {
          input.value = input.dataset.stashedValue
          delete input.dataset.stashedValue
        }
      } else {
        input.dataset.stashedValue = input.value
        input.value = ""
      }
    })
  }

  // ---- the preview -----------------------------------------------------------------------------

  // `requestSubmit(submitter)` is what carries the button's `formaction` and the rest; a bare
  // `submit()` would post the form to the SAVE, which is the one thing this must never do.
  schedulePreview() {
    if (!this.hasPreviewButtonTarget || !this.hasFormTarget) return

    this.cancelPreview()
    this.previewTimer = setTimeout(() => {
      this.previewTimer = null
      this.formTarget.requestSubmit(this.previewButtonTarget)
    }, this.constructor.DEBOUNCE_MS)
  }

  cancelPreview() {
    if (this.previewTimer) clearTimeout(this.previewTimer)
    this.previewTimer = null
  }

  // `hidden` on the frame is the server's way of saying "no JavaScript, no preview"; this is the
  // one place it is lifted.
  revealPreview() {
    if (this.hasPreviewTarget) this.previewTarget.hidden = false
  }

  // The class goes on the card INSIDE the frame, which Turbo has just replaced, so the animation
  // starts from nothing every time and needs no reflow trick to restart it.
  highlight() {
    const card = this.previewCard()
    if (!card) return

    this.cancelHighlight()
    card.classList.add("preview-refreshed")
    this.highlightTimer = setTimeout(() => {
      this.highlightTimer = null
      card.classList.remove("preview-refreshed")
    }, this.constructor.HIGHLIGHT_MS)
  }

  cancelHighlight() {
    if (this.highlightTimer) clearTimeout(this.highlightTimer)
    this.highlightTimer = null
  }

  previewCard() {
    if (!this.hasPreviewTarget) return null

    return this.previewTarget.querySelector("[data-preview]") || this.previewTarget
  }

  // ---- reading the form ------------------------------------------------------------------------

  // By the name the server gave it. The hidden twin is skipped because a Rails checkbox is TWO
  // inputs under one name, and a plain `querySelector` finds the one that is never checked.
  field(name) {
    const found = Array.from(this.formTarget.querySelectorAll(`[name="rule[${name}]"]`))

    return found.find((element) => element.type !== "hidden") || found[0] || null
  }
}
