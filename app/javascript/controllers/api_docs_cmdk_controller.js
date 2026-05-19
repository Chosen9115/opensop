import { Controller } from "@hotwired/stimulus"

// API-docs command palette. Mirrors the standalone design's modal:
// - ⌘K (or Ctrl+K) opens; click on the topbar trigger also opens
// - Esc closes, ↑/↓ navigates, Enter opens the highlighted row
// - Filter is a case-insensitive substring match against label + kind + meta
//
// Markup contract:
//   <div data-controller="api-docs-cmdk"
//        data-api-docs-cmdk-data-value='[{...}]'>
//     <button data-action="click->api-docs-cmdk#open">…</button>
//     <div data-api-docs-cmdk-target="backdrop"
//          data-action="click->api-docs-cmdk#close" class="hidden">…</div>
//     <div data-api-docs-cmdk-target="dialog" class="hidden">
//       <input data-api-docs-cmdk-target="input"
//              data-action="input->api-docs-cmdk#filter" />
//       <div data-api-docs-cmdk-target="list"></div>
//     </div>
//   </div>
//
// Each item: { kind, label, href, meta }
//   - kind:  "doc" for guides, HTTP verb ("GET", "POST", …) for endpoints
//   - label: displayed in the middle column (mono for endpoints, plain for docs)
//   - href:  navigation target on Enter / click
//   - meta:  right-aligned secondary text (section name, endpoint title, …)
export default class extends Controller {
  static targets = ["backdrop", "dialog", "input", "list"]
  static values  = { data: Array }

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
    if ((e.metaKey || e.ctrlKey) && e.key.toLowerCase() === "k") {
      e.preventDefault()
      this._open ? this.close() : this.open()
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

  open(e) {
    if (e) e.preventDefault()
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
    if (!q) {
      this._items = this.dataValue.slice()
    } else {
      this._items = this.dataValue.filter(it => {
        const hay = (it.label + " " + (it.kind || "") + " " + (it.meta || "")).toLowerCase()
        return hay.includes(q)
      })
    }
    this._sel = 0
    this._render()
  }

  _move(d) {
    if (this._items.length === 0) return
    this._sel = Math.max(0, Math.min(this._items.length - 1, this._sel + d))
    this._render()
    this._scrollSelectedIntoView()
  }

  _select() {
    const it = this._items[this._sel]
    if (it && it.href) window.location = it.href
  }

  hover(e) {
    this._sel = Number(e.currentTarget.dataset.idx)
    this._render()
  }

  _scrollSelectedIntoView() {
    const row = this.listTarget.querySelector(`[data-idx='${this._sel}']`)
    if (row && row.scrollIntoView) row.scrollIntoView({ block: "nearest" })
  }

  _kindColor(kind) {
    switch (kind) {
      case "GET":    return "text-[#1f4ed8]"
      case "POST":   return "text-[#0f7a3d]"
      case "DELETE": return "text-[#b03333]"
      case "PATCH":  return "text-[#946700]"
      default:       return "text-[#5d6470]"
    }
  }

  _render() {
    if (this._items.length === 0) {
      this.listTarget.innerHTML =
        '<div class="px-4 py-6 text-[12px] text-[#9aa0a8] text-center">No results</div>'
      return
    }
    this.listTarget.innerHTML = this._items.map((it, idx) => {
      const selected = idx === this._sel
      const kindCls  = this._kindColor(it.kind)
      const labelCls = it.kind === "doc"
        ? "font-mono text-[12px] text-[#0f1115]"
        : "font-mono text-[12px] text-[#0f1115]"
      const rowCls = "flex items-center gap-3 px-4 h-9 cursor-pointer " +
        (selected ? "bg-[#f0f2f5]" : "hover:bg-[#f7f8fa]")
      return `
        <a href="${this._escape(it.href)}"
           data-action="mouseenter->api-docs-cmdk#hover"
           data-idx="${idx}"
           class="${rowCls}">
          <span class="font-mono text-[10px] font-semibold w-12 shrink-0 ${kindCls}">${this._escape(it.kind || "")}</span>
          <span class="${labelCls} flex-1 truncate">${this._escape(it.label)}</span>
          <span class="text-[12px] text-[#5d6470] shrink-0">${this._escape(it.meta || "")}</span>
        </a>`
    }).join("")
  }

  _escape(s) {
    return String(s).replace(/[<>&"']/g, c =>
      ({ "<": "&lt;", ">": "&gt;", "&": "&amp;", '"': "&quot;", "'": "&#39;" }[c])
    )
  }
}
