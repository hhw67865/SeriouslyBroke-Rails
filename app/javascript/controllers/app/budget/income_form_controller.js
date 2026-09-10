import { Controller } from "@hotwired/stimulus"

// The Measured card is the server's own answer to what is typed, asked for through the form's
// hidden Preview button and refreshed into its Turbo Frame.
export default class extends Controller {
  static targets = ["form", "preview", "previewButton"]

  // Long enough typing is one request rather than several; short enough the card stays caught up.
  static DEBOUNCE_MS = 400

  // The CSS animation's own duration, so the class comes off when the animation ends.
  static HIGHLIGHT_MS = 600

  disconnect() {
    this.cancel("previewTimer")
    this.cancel("highlightTimer")
  }

  changed() {
    if (!this.hasPreviewButtonTarget || !this.hasFormTarget) return

    this.cancel("previewTimer")
    this.previewTimer = setTimeout(() => {
      this.previewTimer = null
      this.formTarget.requestSubmit(this.previewButtonTarget)
    }, this.constructor.DEBOUNCE_MS)
  }

  // The class goes on the card INSIDE the frame Turbo just replaced, so the animation restarts
  // from nothing every time.
  highlight() {
    const card = this.hasPreviewTarget ? this.previewTarget.querySelector("[data-preview]") : null
    if (!card) return

    this.cancel("highlightTimer")
    card.classList.add("preview-refreshed")
    this.highlightTimer = setTimeout(() => {
      this.highlightTimer = null
      card.classList.remove("preview-refreshed")
    }, this.constructor.HIGHLIGHT_MS)
  }

  cancel(name) {
    if (this[name]) clearTimeout(this[name])
    this[name] = null
  }
}
