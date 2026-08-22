# Inline SVG QR codes, rendered server-side.
#
# Server-side and inline on purpose: the karaoke screen is the one page a room
# full of phones needs to reach, and it must draw the code with no JS library,
# no network round trip and nothing to load from a CDN. rqrcode is pure Ruby, so
# this costs a deploy nothing.
module QrHelper
  # Recovers about 15% of a damaged symbol. The usual default, and more than
  # enough for a code on a screen that nothing is going to smudge — a higher
  # level only makes the grid denser, which is worse to scan from a sofa.
  QR_ERROR_CORRECTION = :m
  # The margin the QR spec requires around a symbol. A scanner uses it to find
  # the edges, so it is part of the code, not decoration. Expressed in modules
  # and folded into the viewBox rather than left to CSS padding: that way it
  # scales exactly with the code at any rendered size, instead of being a rem
  # value that happens to be four modules wide at one particular width.
  QR_QUIET_ZONE_MODULES = 4

  # `title` is what a screen reader announces; the code is an image of a URL,
  # so it needs one. Everything else is passed through as SVG attributes.
  #
  # Deliberately self-contained — its own white ground, its own black modules,
  # its own quiet zone — so no CSS can accidentally make it unscannable. A
  # scanner will usually cope with an inverted code, but "usually" is not what
  # you want when the fallback is a guest standing in front of the TV.
  def qr_code_svg(text, title:, **attrs)
    qr = RQRCode::QRCode.new(text.to_s, level: QR_ERROR_CORRECTION)
    quiet = QR_QUIET_ZONE_MODULES
    span = qr.qrcode.module_count + quiet * 2

    # module_size: 1 leaves the path in module units, so the viewBox is the
    # module grid itself and CSS only decides how large it is drawn.
    #
    # html_safe is sound here: the path comes out of the encoder as nothing but
    # M/h/v/z and digits. No caller input reaches it except through the QR
    # matrix itself.
    path = qr.as_svg(module_size: 1, offset: 0, standalone: false, use_path: true)

    tag.svg(
      safe_join([
        tag.title(title),
        tag.rect(width: span, height: span, fill: "#fff"),
        tag.g(path.html_safe, transform: "translate(#{quiet} #{quiet})", fill: "#000")
      ]),
      viewBox: "0 0 #{span} #{span}",
      xmlns: "http://www.w3.org/2000/svg",
      role: "img",
      # Without this the renderer antialiases every module edge, which is what
      # makes a small QR fail to scan.
      "shape-rendering": "crispEdges",
      **attrs
    )
  end
end
