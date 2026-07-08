import { Controller } from "@hotwired/stimulus"

// Drives an on-screen calculator pad for a numeric/formula input. The pad
// starts hidden and is revealed with the toggle button. Each key inserts at
// the cursor so users can build expressions (e.g. 192.92-85.02). Reusable on
// any form: add data-controller="shared--calculator-pad", point the input at
// the "input" target, render shared/calculator_pad_toggle inside a relative
// wrapper around the input (with right padding for the button), and render
// the shared/calculator_pad partial below.
export default class extends Controller {
  static targets = ["input", "pad", "toggleButton"]

  toggle(event) {
    event.preventDefault()
    const show = this.padTarget.classList.contains("hidden")
    this.padTarget.classList.toggle("hidden", !show)
    this.padTarget.classList.toggle("grid", show)
    this.toggleButtonTarget.setAttribute("aria-expanded", String(show))
  }

  insert(event) {
    event.preventDefault()
    this.replaceSelection(event.currentTarget.dataset.value)
  }

  backspace(event) {
    event.preventDefault()
    const input = this.inputTarget
    const start = input.selectionStart ?? input.value.length
    const end = input.selectionEnd ?? input.value.length

    if (start === end) {
      // No selection: delete the character before the cursor.
      if (start === 0) return
      this.setValue(input.value.slice(0, start - 1) + input.value.slice(end), start - 1)
    } else {
      // Delete the highlighted selection.
      this.setValue(input.value.slice(0, start) + input.value.slice(end), start)
    }
  }

  clear(event) {
    event.preventDefault()
    this.setValue("", 0)
  }

  replaceSelection(text) {
    const input = this.inputTarget
    const start = input.selectionStart ?? input.value.length
    const end = input.selectionEnd ?? input.value.length
    this.setValue(input.value.slice(0, start) + text + input.value.slice(end), start + text.length)
  }

  setValue(value, caret) {
    const input = this.inputTarget
    input.value = value
    input.dispatchEvent(new Event("input", { bubbles: true }))
    input.focus()
    input.setSelectionRange(caret, caret)
  }
}
