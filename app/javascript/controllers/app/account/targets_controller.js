import { Controller } from "@hotwired/stimulus"

// Target rows on the account form: add a row from the template, remove one (tick its _destroy and
// hide it), show the figure field the chosen source implies, and say what percent of typical
// income a fixed amount is.
export default class extends Controller {
  static targets = ["template", "rows", "row", "source", "amountField", "percentField", "amount", "destroy", "hint"]
  static values = { typical: Number, index: Number }

  connect() {
    this.rowTargets.forEach((row) => this.syncRow(row))
  }

  add() {
    const html = this.templateTarget.innerHTML.replace(/NEW_TARGET/g, String(this.indexValue++))
    this.rowsTarget.insertAdjacentHTML("beforeend", html)
    this.syncRow(this.rowTargets[this.rowTargets.length - 1])
  }

  remove(event) {
    const row = event.target.closest("[data-target-row]")
    const destroy = row.querySelector("[data-app--account--targets-target='destroy']")
    if (destroy) destroy.checked = true
    row.hidden = true
  }

  switch(event) {
    this.syncRow(event.target.closest("[data-target-row]"))
  }

  hint(event) {
    this.writeHint(event.target.closest("[data-target-row]"))
  }

  // A hidden field is also disabled, so only the figure the source implies is submitted.
  syncRow(row) {
    const share = row.querySelector("[data-app--account--targets-target='source']").value !== ""
    const amountField = row.querySelector("[data-app--account--targets-target='amountField']")
    const percentField = row.querySelector("[data-app--account--targets-target='percentField']")
    amountField.hidden = share
    percentField.hidden = !share
    amountField.querySelector("input").disabled = share
    percentField.querySelector("input").disabled = !share
    this.writeHint(row)
  }

  writeHint(row) {
    const hint = row.querySelector("[data-app--account--targets-target='hint']")
    const share = row.querySelector("[data-app--account--targets-target='source']").value !== ""
    const amount = parseFloat(row.querySelector("[data-app--account--targets-target='amount']").value)
    if (share || !this.typicalValue || !Number.isFinite(amount) || amount <= 0) {
      hint.textContent = ""
      return
    }
    hint.textContent = `That's ${Math.round((amount / this.typicalValue) * 100)}% of what you typically bring in.`
  }
}
