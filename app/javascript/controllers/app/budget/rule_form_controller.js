import { Controller } from "@hotwired/stimulus"

// THE RULE FORM'S FOUR JOBS, AND ONLY ONE OF THEM IS NOW A GATE (two-shapes spec §5 and §12).
//
// The server renders every control with the `hidden` state the current choice implies and validates
// whatever comes back, so a browser with no JavaScript still gets a form that SAVES and a legible
// 422 if the answers do not hang together. What this adds is that the page keeps up with the person
// filling it in:
//
//   * "By a date" reveals the due date and the "repeats" checkbox, and the checkbox reveals the
//     interval. "Every period" hides all three, and it is what enables the "keeps" box — a dated
//     rule never keeps (§12), so under "By a date" the box is cleared and disabled.
//   * A chip fills every blank it has a measurement for, and reads "✓ Using this" while the blanks
//     still match it.
//   * Any change re-submits the form to `BudgetsController#preview`, debounced, so the card beside
//     it is always describing what is on screen — with a brief highlight on arrival, because the
//     card is inches from the box and a figure that changes silently is a change nobody looks for.
//
// ** AND THE ONE GATE: THE PREVIEW CARD ONLY EXISTS WHERE THIS CONTROLLER RUNS (§12). ** The card's
// frame is rendered `hidden` and `connect()` is what reveals it. The "Preview" button that used to
// make the card work without JavaScript is deleted, so a card left visible would be one nothing
// could refresh — a confident sentence about a rule the user has since changed. No preview is the
// honest state; the form itself is unaffected.
//
// ** THE PREVIEW IS NOT COMPUTED HERE, AND THAT IS THE WHOLE DESIGN (§5). ** Every figure on the
// card is `ClaimCalculator`'s — the same reader Home and the Budget page print — so the browser's
// job is to ASK for it, not to work it out. This controller presses the form's own Preview button
// (`requestSubmit`, with that button as the submitter), which means the request carries exactly the
// fields a save would carry, through the `formaction` the server wrote. There is no second URL, no
// hand-built payload, and nothing here that can describe the rule differently from the save.
//
// ** THE ITEM FILTER IS DELETED WITH THE OWNER PICKER (§5). ** "Pays" used to list every item the
// user owns, each stamped with its category, hidden and disabled as the category select moved. The
// form is per category now — `category.items` is the whole select — so there is nothing to filter
// between and no `categoryValue` to filter by.
//
// ** A HIDDEN FIELD IS CLEARED, AND ITS VALUE IS PUT BACK WHEN IT RETURNS. ** A hidden input still
// submits, so a user who typed a due date and then chose "per period" would send a date the form no
// longer shows — and `RuleForm` refuses a due date on a per-period rule rather than laundering it
// away, so the refusal would be about a control that is not on screen. Stashing on the element keeps
// a toggle back and forth from costing the user their typing.
export default class extends Controller {
  static targets = [
    "form",
    "amount",
    "item",
    "intervalField",
    "anchorField",
    "repeatsField",
    "keepsField",
    "preview",
    "previewButton"
  ]

  // HOW LONG THE FORM WAITS BEFORE ASKING THE SERVER AGAIN. Long enough that typing "1200" is one
  // request rather than four, short enough that the card is not visibly behind the box.
  static DEBOUNCE_MS = 400

  // HOW LONG THE REFRESHED CARD WEARS ITS RING, and it is the CSS animation's own duration
  // (`.preview-refreshed` in `animations.css`). Two spellings of one number, so the class is taken
  // off the element at the moment the animation ends rather than while it is still running or long
  // after it has finished.
  static HIGHLIGHT_MS = 600

  // EVERY BLANK A CHIP CAN FILL, keyed by the `data-prefill-*` attribute that carries it. The list
  // is `BudgetsController::BUDGET_FIELDS` minus the owner, which no control on this form sets — a
  // chip naming a category is naming the one the page is already about.
  static FIELDS = ["amount", "itemId", "ruleType", "schedule", "repeats", "keeps", "intervalMonths", "anchorDate"]

  // ** THE CARD IS REVEALED HERE AND NOWHERE ELSE (§12). ** Before the reveals, so the first thing
  // the user sees is a card describing a form that has already been put into the state its answers
  // imply. No refresh is asked for: the server rendered this card with this form.
  connect() {
    this.revealPreview()
    if (this.hasFormTarget) this.refresh()
  }

  disconnect() {
    this.cancelPreview()
    this.cancelHighlight()
  }

  // ONE HANDLER FOR EVERY CONTROL. The reveals and the chip states are instant — they are facts
  // about what is already on screen — and the preview is debounced, because it is a request.
  changed() {
    this.refresh()
    this.schedulePreview()
  }

  refresh() {
    this.revealFields()
    this.markChips()
  }

  // ---- the reveals -----------------------------------------------------------------------------

  get schedule() {
    const checked = this.formTarget.querySelector('input[name="budget[schedule]"]:checked')
    return checked ? checked.value : "per_period"
  }

  // THE CHECKBOX'S OWN STATE. `:checked` on the element rather than its `value`, which is the
  // constant "1" a checkbox submits when it is on and says nothing at all when it is off.
  get repeats() {
    const box = this.field("repeats")
    return box ? box.checked : false
  }

  revealFields() {
    const dated = this.schedule === "by_date"

    this.toggle(this.optional("anchorField"), dated)
    this.toggle(this.optional("repeatsField"), dated)
    this.toggle(this.optional("intervalField"), dated && this.repeats)
    this.allowKeeps(!dated)
  }

  // ** THE KEEPS BOX IS DISABLED AND CLEARED UNDER "By a date", NOT HIDDEN (§12). ** Hiding it would
  // take the one control that says what happens to unspent money off the screen on the shape where
  // that question is most likely to be asked; disabled-and-unchecked ANSWERS it — a dated rule's
  // build-up is defined by its date. Unticking is not cosmetic: the browser submits the state of the
  // control, and `Budget#keeps_unspent_never_dates` refuses the pair, so a box left ticked under a
  // date would be a 422 about a control the user cannot reach.
  //
  // NOTHING IS STASHED, deliberately, unlike `#toggle`'s typed inputs: the box is a two-state
  // answer to a question this schedule does not ask, and a value silently restored on the way back
  // would re-tick a box the user last saw empty.
  allowKeeps(allowed) {
    const field = this.optional("keepsField")
    if (!field) return

    const box = this.field("keeps")
    if (!box) return

    box.disabled = !allowed
    if (!allowed) box.checked = false
    field.classList.toggle("opacity-50", !allowed)
  }

  optional(name) {
    return this[`has${name[0].toUpperCase()}${name.slice(1)}Target`] ? this[`${name}Target`] : null
  }

  // Nothing happens when the state already matches, which is what keeps `connect()` from clearing a
  // prefilled date on a form the server rendered correctly in the first place.
  toggle(field, visible) {
    if (!field || field.hidden === !visible) return

    field.hidden = !visible
    // RADIOS ARE LEFT ALONE. A radio's `value` is what it MEANS, not what somebody typed, so
    // blanking one submits an empty choice rather than an untouched one.
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

  // ---- the chips -------------------------------------------------------------------------------

  // ** A CHIP FILLS THE BLANKS AND THEN ASKS THE SERVER. ** Nothing is saved and nothing is
  // validated here: the fields end up holding what the engine measured, the preview re-renders from
  // the server, and the user still presses Create.
  //
  // `change` IS DISPATCHED ON EVERY FIELD IT WRITES, because a value set by script fires no event of
  // its own — and the reveals, the chip states and the preview all hang off that event. It is
  // dispatched on the element rather than announced through a second channel so that a chip's fill
  // is indistinguishable from a person typing the same thing.
  useChip(event) {
    const chip = event.target.closest("[data-chip]")
    if (!chip) return

    this.constructor.FIELDS.forEach((field) => this.fill(field, chip.dataset[`prefill${this.capitalize(field)}`]))
    this.changed()
  }

  fill(name, value) {
    if (value === undefined) return

    const wire = this.snake(name)
    const field = this.field(wire)
    if (!field) return

    if (field.type === "checkbox") {
      field.checked = this.truthy(value)
    } else if (field.type === "radio") {
      this.chooseRadio(wire, value)
    } else {
      field.value = value
    }
    field.dispatchEvent(new Event("change", { bubbles: true }))
  }

  // ** THE CHIP READS "✓ Using this" WHILE THE BLANKS MATCH IT (§5). ** The comparison is against
  // what is IN the form rather than against a flag set when the button was pressed: a user who
  // accepts a chip and then edits the amount has stopped using it, and a chip that went on claiming
  // otherwise would be the page asserting something the fields contradict.
  markChips() {
    this.element.querySelectorAll("[data-chip]").forEach((chip) => {
      const button = chip.querySelector("[data-chip-button]")
      if (!button) return

      const using = this.matchesChip(chip)
      button.textContent = using ? button.dataset.usingLabel : button.dataset.defaultLabel
      button.setAttribute("aria-pressed", using ? "true" : "false")
      chip.toggleAttribute("data-chip-using", using)
    })
  }

  matchesChip(chip) {
    const claimed = this.constructor.FIELDS.filter((field) => chip.dataset[`prefill${this.capitalize(field)}`] !== undefined)
    if (claimed.length === 0) return false

    return claimed.every((field) => this.fieldMatches(field, chip.dataset[`prefill${this.capitalize(field)}`]))
  }

  fieldMatches(name, expected) {
    const field = this.field(this.snake(name))
    if (!field) return false
    if (field.type === "checkbox") return field.checked === this.truthy(expected)

    const current = this.currentValue(this.snake(name), field)
    // MONEY COMPARES AS A NUMBER. "600.0" off a record and "600.00" typed into the box are the same
    // amount, and a chip that unset itself the moment the browser reformatted its own value would be
    // worse than no state at all.
    if (this.numeric(current) && this.numeric(expected)) return Number(current) === Number(expected)

    return current === expected
  }

  // ---- the preview -----------------------------------------------------------------------------

  // THE FORM'S OWN PREVIEW BUTTON, PRESSED FOR THE USER. `requestSubmit(submitter)` is what carries
  // the button's `formaction`, `formmethod`, `formnovalidate` and `data-turbo-frame` — a bare
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

  // ** THE CARD EXISTS BECAUSE THIS RAN (§12). ** `hidden` on the frame is the server's way of
  // saying "no JavaScript, no preview"; this is the one place it is lifted.
  revealPreview() {
    if (this.hasPreviewTarget) this.previewTarget.hidden = false
  }

  // ** A BRIEF RING WHEN THE SERVER'S ANSWER LANDS (§12). ** Bound to `turbo:frame-load` on the
  // frame itself, so it fires exactly once per refresh and only on a refresh — the first render is
  // server-side and announces nothing.
  //
  // THE CLASS GOES ON THE CARD INSIDE THE FRAME, which Turbo has just REPLACED, so the animation
  // starts from nothing every time and no reflow trick is needed to restart it. The timer is only
  // housekeeping: it takes the class off an element that will usually be replaced before it is next
  // looked at.
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

  // BY THE NAME THE SERVER GAVE IT, not by a target per field. Seven targets for seven blanks would
  // be seven chances for a renamed control to stop being filled in silence; the wire name is the one
  // both halves already agree on, and a chip's own attributes are keyed to it.
  //
  // ** THE HIDDEN TWIN IS SKIPPED, AND THAT IS NOT A DEFENCE — IT IS THE CHECKBOX (measured). ** A
  // Rails checkbox is TWO inputs under one name: a hidden `value="0"` first, so an unticked box
  // still submits, then the box itself. A plain `querySelector` finds the hidden one, whose
  // `.checked` is false whatever the user did — so the interval field was hidden and CLEARED on
  // every render of a repeating bill's edit form, and ticking the box revealed nothing.
  field(name) {
    const found = Array.from(this.formTarget.querySelectorAll(`[name="budget[${name}]"]`))

    return found.find((element) => element.type !== "hidden") || found[0] || null
  }

  currentValue(name, field) {
    if (field.type === "radio") {
      const checked = this.formTarget.querySelector(`[name="budget[${name}]"]:checked`)
      return checked ? checked.value : ""
    }
    return field.value
  }

  chooseRadio(name, value) {
    const radio = this.formTarget.querySelector(`[name="budget[${name}]"][value="${value}"]`)
    if (radio) radio.checked = true
  }

  truthy(value) {
    return ["true", "1", "on", "yes"].includes(String(value).toLowerCase())
  }

  numeric(value) {
    return value !== "" && value !== null && Number.isFinite(Number(value))
  }

  capitalize(name) {
    return `${name[0].toUpperCase()}${name.slice(1)}`
  }

  // `itemId` → `item_id`: the data attribute arrives camel-cased by `dataset`, and the wire name is
  // the column's.
  snake(name) {
    return name.replace(/[A-Z]/g, (letter) => `_${letter.toLowerCase()}`)
  }
}
