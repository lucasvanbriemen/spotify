const KARAOKE_DIR = new URL("../../app/javascript/karaoke/", import.meta.url)

export function resolve(specifier, context, nextResolve) {
  if (specifier.startsWith("karaoke/")) {
    const target = new URL(`${specifier.slice("karaoke/".length)}.js`, KARAOKE_DIR)
    return nextResolve(target.href, context)
  }

  return nextResolve(specifier, context)
}
