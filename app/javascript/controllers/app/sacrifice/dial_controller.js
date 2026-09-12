import { Controller } from "@hotwired/stimulus"

// The what-if dial: arithmetic over figures the server already printed, in per-period units
// throughout (`Rule#ask`, never `rule.amount`) and in integer cents, never float dollars.
export default class extends Controller {
  static targets = ["row", "amount", "toggle", "rowFrees", "freed", "verdict", "save", "edit", "undo"]
  // Dollars on the attribute (that is what the server prints), cents inside — see #cents.
  static values = { gap: Number }

  // A rule row opens read-only: the input is live only after Edit, and Undo closes it again, so a
  // disabled input is a row the save will not carry. A savings target row has no Edit button — its
  // checkbox is the toggle instead, and its input is disabled exactly when the checkbox is
  // unticked, so an edited-but-unticked figure can never reach the server.
  connect() {
    this.rowTargets.forEach((row) => {
      if (this.fieldFor(row, "edit")) {
        this.close(row)
      } else if (this.fieldFor(row, "toggle")) {
        this.syncToggle(row)
      }
    })
    this.recompute()
  }

  edit(event) {
    const row = this.rowOf(event)
    const input = this.fieldFor(row, "amount")
    input.disabled = false
    this.fieldFor(row, "edit").hidden = true
    this.fieldFor(row, "undo").hidden = false
    input.focus()
    input.select()
  }

  undo(event) {
    const row = this.rowOf(event)
    this.close(row)
    this.recompute()
  }

  // The savings target row's checkbox: ticking arms the input for submission, unticking disarms
  // it, exactly as Edit/Undo do for a rule row's input.
  toggle(event) {
    this.syncToggle(this.rowOf(event))
    this.recompute()
  }

  syncToggle(row) {
    const toggle = this.fieldFor(row, "toggle")
    this.fieldFor(row, "amount").disabled = !toggle.checked
  }

  close(row) {
    const input = this.fieldFor(row, "amount")
    input.value = row.dataset.claim
    input.disabled = true
    this.fieldFor(row, "edit").hidden = false
    this.fieldFor(row, "undo").hidden = true
  }

  rowOf(event) {
    return event.target.closest(`[data-${this.identifier}-target="row"]`)
  }

  // Read out of the DOM every time: a cache would be one more description of "what is on screen",
  // free to disagree with the screen itself.
  recompute() {
    let freed = 0

    this.rowTargets.forEach((row) => {
      const rowFreed = this.freedBy(row)
      freed += rowFreed
      this.freesFieldFor(row).textContent = this.money(rowFreed)
    })

    this.freedTarget.textContent = this.money(freed)
    this.writeVerdict(this.cents(this.gapValue) - freed)
    this.saveTarget.disabled = freed === 0
  }

  // Cutting TO a figure. An amount row frees `claim - typed`; a percent row frees the difference
  // between its percent and the typed percent, of its item's typical income. Clamped into
  // [0, claim]. A rule row (no checkbox) frees nothing while its input is disabled; a savings
  // target row (no Edit button) frees nothing while its checkbox is unchecked.
  freedBy(row) {
    const toggle = this.fieldFor(row, "toggle")
    const input = this.fieldFor(row, "amount")
    if (toggle ? !toggle.checked : input.disabled) return 0

    const claim = this.cents(parseFloat(row.dataset.claim))
    const typed = parseFloat(input.value)
    const kept = row.dataset.kind === "percent"
      ? this.cents((Number.isFinite(typed) ? typed : 0) / 100 * parseFloat(row.dataset.income))
      : this.cents(typed)

    return Math.min(Math.max(claim - kept, 0), claim)
  }

  // Positive means still short, so this can say what the server's unwinnable statement says.
  // `Math.abs` and not `-remaining`: break-even is `-0`, which formats as "-$0.00".
  writeVerdict(remaining) {
    this.verdictTarget.textContent =
      remaining > 0
        ? `Still underwater ${this.money(remaining)} a period`
        : `Covered — ${this.money(Math.abs(remaining))} a period to spare`
    this.verdictTarget.classList.toggle("text-status-danger", remaining > 0)
    this.verdictTarget.classList.toggle("text-status-success", remaining <= 0)
  }

  // Scoped to the row, never `this.<name>Targets[index]`: a row with no amount field would slide
  // every later row's figure onto the wrong rule, silently.
  fieldFor(row, name) {
    return row.querySelector(`[data-${this.identifier}-target="${name}"]`)
  }

  freesFieldFor(row) {
    return this.fieldFor(row, "rowFrees")
  }

  // NaN in means zero out: `parseFloat("")` is NaN, which would poison the total into "$NaN", and
  // zero is the honest reading of a cleared box — #freedBy clamps it to the rule's own claim.
  cents(dollars) {
    return Number.isFinite(dollars) ? Math.round(dollars * 100) : 0
  }

  // Matching `number_to_currency`: a dial reading "1365" beside a server figure reading
  // "$1,365.00" is two vocabularies for one number.
  money(cents) {
    return new Intl.NumberFormat("en-US", { style: "currency", currency: "USD" }).format(cents / 100)
  }
}
