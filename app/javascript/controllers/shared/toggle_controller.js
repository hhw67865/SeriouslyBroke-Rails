import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["thumb"]
  static values = { on: String, off: String }

  toggle() {
    this.element.classList.toggle("bg-brand")
    this.element.classList.toggle("bg-gray-300")
    this.thumbTarget.classList.toggle(this.onValue)
    this.thumbTarget.classList.toggle(this.offValue)
  }
}
