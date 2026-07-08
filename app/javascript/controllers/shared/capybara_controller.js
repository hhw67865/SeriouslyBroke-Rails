import { Controller } from "@hotwired/stimulus"

const NEXT_SPAWN_KEY = "capybara-next-spawn-at"
const GREETED_KEY = "capybara-greeted"
const MIN_DELAY_MS = 2 * 60 * 1000
const MAX_DELAY_MS = 5 * 60 * 1000
const SPECIAL_CHANCE = 0.15
const BONUS_CHANCE = 0.3

// Spawns occasional animated capybaras while ming mode is on. The next
// spawn time lives in sessionStorage so Turbo navigations don't reset
// the 2-5 minute clock.
export default class extends Controller {
  static values = {
    run: String,
    sit: String,
    sleep: String,
    melon: String,
    bath: String,
    box: String
  }

  connect() {
    if (this.prefersReducedMotion) return

    this.scheduleNext()
    this.maybeGreet()
  }

  disconnect() {
    clearTimeout(this.spawnTimer)
    clearTimeout(this.bonusTimer)
    this.activeCapybara?.remove()
    this.activeCapybara = null
  }

  spawn(behavior = null) {
    if (this.activeCapybara || this.prefersReducedMotion) return

    behavior ||= this.pickBehavior()
    const builders = {
      walk: this.buildWalk,
      peek: this.buildPeek,
      sleep: this.buildSleep,
      special: this.buildSpecial
    }
    const capybara = builders[behavior].call(this)

    // The wrapper's entrance/exit animation uses `forwards` and ends;
    // inner animations are infinite and never fire animationend.
    capybara.addEventListener("animationend", (event) => {
      if (event.target !== capybara) return
      capybara.remove()
      this.activeCapybara = null
    })

    this.activeCapybara = capybara
    this.element.appendChild(capybara)
  }

  scheduleNext() {
    let nextAt = Number(sessionStorage.getItem(NEXT_SPAWN_KEY))
    if (!nextAt || nextAt <= Date.now()) {
      nextAt = Date.now() + this.randomBetween(MIN_DELAY_MS, MAX_DELAY_MS)
      sessionStorage.setItem(NEXT_SPAWN_KEY, nextAt)
    }
    this.spawnTimer = setTimeout(() => {
      sessionStorage.removeItem(NEXT_SPAWN_KEY)
      this.spawn()
      this.scheduleNext()
    }, nextAt - Date.now())
  }

  maybeGreet() {
    if (sessionStorage.getItem(GREETED_KEY)) return

    sessionStorage.setItem(GREETED_KEY, "true")
    if (Math.random() < BONUS_CHANCE) {
      this.bonusTimer = setTimeout(() => this.spawn(), this.randomBetween(5000, 15000))
    }
  }

  pickBehavior() {
    if (Math.random() < SPECIAL_CHANCE) return "special"

    return ["walk", "peek", "sleep"][Math.floor(Math.random() * 3)]
  }

  buildWalk() {
    const leftToRight = Math.random() < 0.5
    // The run sprite faces left, so mirror it when walking left-to-right
    return this.buildCapybara(this.runValue, {
      wrapperClasses: leftToRight ? "capybara--walk" : "capybara--walk capybara--rtl",
      mirrored: leftToRight,
      bodyClass: "capybara__body--waddle"
    })
  }

  buildPeek() {
    const edge = ["right", "bottom"][Math.floor(Math.random() * 2)]
    const capybara = this.buildCapybara(this.sitValue, {
      wrapperClasses: `capybara--peek-${edge}`
    })
    if (edge === "bottom") {
      capybara.style.left = `${this.randomBetween(15, 75)}%`
    } else {
      capybara.style.bottom = `${this.randomBetween(15, 60)}%`
    }
    return capybara
  }

  buildSleep() {
    const capybara = this.buildCapybara(this.sleepValue, {
      wrapperClasses: "capybara--rest capybara--rest-slow",
      bodyClass: "capybara__body--doze"
    })
    capybara.classList.add(Math.random() < 0.5 ? "capybara--corner-left" : "capybara--corner-right")
    for (let i = 0; i < 3; i++) {
      const z = document.createElement("span")
      z.className = "capybara__zzz"
      z.textContent = "z"
      z.style.animationDelay = `${i}s`
      capybara.appendChild(z)
    }
    return capybara
  }

  buildSpecial() {
    const sources = [this.melonValue, this.bathValue, this.boxValue]
    const capybara = this.buildCapybara(sources[Math.floor(Math.random() * sources.length)], {
      wrapperClasses: "capybara--rest"
    })
    capybara.classList.add(Math.random() < 0.5 ? "capybara--corner-left" : "capybara--corner-right")
    return capybara
  }

  buildCapybara(src, { wrapperClasses, mirrored = false, bodyClass = "" }) {
    const wrapper = document.createElement("div")
    wrapper.className = `capybara ${wrapperClasses}`

    const flip = document.createElement("span")
    flip.className = mirrored ? "capybara__flip capybara__flip--mirrored" : "capybara__flip"

    const img = document.createElement("img")
    img.src = src
    img.alt = ""
    img.className = bodyClass ? `capybara__body ${bodyClass}` : "capybara__body"

    flip.appendChild(img)
    wrapper.appendChild(flip)
    return wrapper
  }

  randomBetween(min, max) {
    return min + Math.random() * (max - min)
  }

  get prefersReducedMotion() {
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches
  }
}
