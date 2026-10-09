// Desenha o ícone do app (1024×1024) e salva como PNG: swift scripts/make-icon.swift saida.png
import AppKit

let size: CGFloat = 1024
let output = CommandLine.arguments.dropFirst().first ?? "AppIcon.png"
// Bitmap com tamanho exato em pixels (lockFocus em tela Retina geraria 2048×2048).
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// Fundo: quadrado arredondado no formato dos ícones do macOS, com gradiente azul.
let inset: CGFloat = 100
let rect = NSRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 185, yRadius: 185)
NSGraphicsContext.current?.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
shadow.shadowBlurRadius = 24
shadow.shadowOffset = NSSize(width: 0, height: -10)
shadow.set()
NSGradient(starting: NSColor(red: 0.16, green: 0.45, blue: 1.0, alpha: 1),
           ending: NSColor(red: 0.05, green: 0.18, blue: 0.62, alpha: 1))!.draw(in: shape, angle: -90)
NSGraphicsContext.current?.restoreGraphicsState()

// Celular com uma seta de download.
let darkBlue = NSColor(red: 0.07, green: 0.24, blue: 0.75, alpha: 1)
func symbol(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor) -> NSImage {
    let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        .applying(.init(paletteColors: [color]))
    return NSImage(systemSymbolName: name, accessibilityDescription: nil)!.withSymbolConfiguration(config)!
}
let phone = symbol("iphone.gen3", pointSize: 520, weight: .light, color: .white)
phone.draw(in: NSRect(x: (size - phone.size.width) / 2, y: (size - phone.size.height) / 2,
                      width: phone.size.width, height: phone.size.height))
let arrow = symbol("arrow.down", pointSize: 230, weight: .bold, color: darkBlue)
arrow.draw(in: NSRect(x: (size - arrow.size.width) / 2, y: (size - arrow.size.height) / 2 - 10,
                      width: arrow.size.width, height: arrow.size.height))

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output))
