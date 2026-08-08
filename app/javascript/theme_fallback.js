// Stand-in for the shared ui-components "objects/theme" module (see
// config/importmap.rb) when that repo isn't checked out next to this app —
// e.g. local dev. application.js imports "objects/theme" unconditionally, so
// without a pin for it Turbo/Stimulus fail to boot entirely. Mirrors the one
// externally-visible effect other stylesheets depend on: a `data-theme`
// attribute on <html> reflecting the OS light/dark preference.
export default {
  init() {
    const media = window.matchMedia("(prefers-color-scheme: dark)")
    const apply = () => { document.documentElement.dataset.theme = media.matches ? "dark" : "light" }

    apply()
    media.addEventListener("change", apply)
  }
}
