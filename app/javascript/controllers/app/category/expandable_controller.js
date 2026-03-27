import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["button", "content", "icon"]

  connect() {
    this._label = this.buttonTarget.textContent.trim()
  }

  toggle() {
    this.contentTarget.classList.toggle("hidden")
    this.buttonTarget.textContent = this.contentTarget.classList.contains("hidden") ? this._label : "Hide"
    if (this.hasIconTarget) {
      this.iconTarget.classList.toggle("rotate-180")
    }
  }
}
