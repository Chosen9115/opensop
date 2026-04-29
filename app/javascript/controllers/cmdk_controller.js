import { Controller } from "@hotwired/stimulus"

// Command palette ("Cmdk"). Opens an overlay where the user can search
// processes / instances / nav items, arrow-key through results, and press
// Enter to navigate.
//
// Markup contract:
//   <div data-controller="cmdk" data-cmdk-data-value='[...]'>
//     <button data-action="click->cmdk#open">…</button>          (optional external trigger)
//     <div data-cmdk-target="backdrop" data-action="click->cmdk#close">…</div>
//     <div data-cmdk-target="dialog">
//       <input data-cmdk-target="input" data-action="input->cmdk#filter" />
//       <div data-cmdk-target="list"></div>
//     </div>
//   </div>
//
// Dataset format passed via data-cmdk-data-value:
//   [{ label: "Dashboard",      kind: "Navigate", href: "/dashboard" },
//    { label: "linkedin-intent", kind: "Process",  href: "/processes/linkedin-intent" },
//    { label: "69e4a644…",       kind: "Instance", href: "/instances/abc…" }]
export default class extends Controller {
  static targets = ["trigger", "backdrop", "dialog", "input", "list"]
  static values = { data: Array }

  connect() {
    this._open = false
    this._items = []
    this._sel = 0
    this._onKey = this._onKey.bind(this)
    document.addEventListener("keydown", this._onKey)
  }

  disconnect() {
    document.removeEventListener("keydown", this._onKey)
  }

  _onKey(e) {
    if ((e.metaKey || e.ctrlKey) && e.key === "k") {
      e.preventDefault()
      this.open()
    } else if (this._open && e.key === "Escape") {
      e.preventDefault()
      this.close()
    } else if (this._open && (e.key === "ArrowDown" || e.key === "ArrowUp")) {
      e.preventDefault()
      this._move(e.key === "ArrowDown" ? 1 : -1)
    } else if (this._open && e.key === "Enter") {
      e.preventDefault()
      this._select()
    }
  }

  open() {
    this._open = true
    this.backdropTarget.classList.remove("hidden")
    this.dialogTarget.classList.remove("hidden")
    this._items = this.dataValue.slice()
    this._sel = 0
    this._render()
    setTimeout(() => this.inputTarget.focus(), 10)
  }

  close() {
    this._open = false
    this.backdropTarget.classList.add("hidden")
    this.dialogTarget.classList.add("hidden")
    this.inputTarget.value = ""
  }

  filter() {
    const q = this.inputTarget.value.toLowerCase().trim()
    this._items = q
      ? this.dataValue.filter(i => (i.label + " " + (i.kind || "")).toLowerCase().includes(q))
      : this.dataValue.slice()
    this._sel = 0
    this._render()
  }

  _move(d) {
    this._sel = Math.max(0, Math.min(this._items.length - 1, this._sel + d))
    this._render()
  }

  _select() {
    const i = this._items[this._sel]
    if (i && i.href) window.location = i.href
  }

  _render() {
    if (this._items.length === 0) {
      this.listTarget.innerHTML = '<div class="px-4 py-3 text-[12px] text-fg-muted text-center">No results</div>'
      return
    }
    // Group results by kind, preserving order, and mark the selected row.
    const groups = {}
    this._items.forEach((it, idx) => {
      const k = it.kind || ""
      ;(groups[k] = groups[k] || []).push({ ...it, _idx: idx })
    })
    this.listTarget.innerHTML = Object.entries(groups).map(([kind, items]) =>
      `<div class="px-3 pt-2 pb-1 pp-section-title">${this._escape(kind)}</div>` +
      items.map(it => `
        <a href="${it.href}" data-action="mouseenter->cmdk#hover" data-idx="${it._idx}"
           class="flex items-center gap-2 px-3 py-1.5 text-[12px] cursor-pointer ${it._idx === this._sel ? 'bg-bg-hover' : 'hover:bg-bg-hover'}">
          <span class="font-mono">${this._escape(it.label)}</span>
          <span class="ml-auto pp-tag">${this._escape(it.kind || '')}</span>
        </a>`
      ).join('')
    ).join('')
  }

  hover(e) {
    this._sel = Number(e.currentTarget.dataset.idx)
    this._render()
  }

  _escape(s) {
    return String(s).replace(/[<>&]/g, c => ({ "<": "&lt;", ">": "&gt;", "&": "&amp;" }[c]))
  }
}
