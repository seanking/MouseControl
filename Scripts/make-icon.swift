import AppKit
import CoreGraphics

let size = 1024
let cs = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: cs, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: a) }

// macOS icon grid: 824pt tile centered in a 1024 canvas.
let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

// Tile drop shadow.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: rgb(0, 0, 0, 0.35))
ctx.addPath(tilePath); ctx.setFillColor(rgb(40, 60, 200)); ctx.fillPath()
ctx.restoreGState()

// Tile gradient.
ctx.saveGState()
ctx.addPath(tilePath); ctx.clip()
let bg = CGGradient(colorsSpace: cs, colors: [rgb(92, 156, 255), rgb(52, 76, 222)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(bg, start: CGPoint(x: 512, y: 924), end: CGPoint(x: 512, y: 100), options: [])
// Soft highlight in the upper half.
let glow = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255, 0.22), rgb(255, 255, 255, 0)] as CFArray, locations: [0, 1])!
ctx.drawRadialGradient(glow, startCenter: CGPoint(x: 512, y: 860), startRadius: 0, endCenter: CGPoint(x: 512, y: 860), endRadius: 520, options: [])
ctx.restoreGState()

// Mouse body.
let body = CGRect(x: 512 - 175, y: 230, width: 350, height: 560)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 175, cornerHeight: 175, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 40, color: rgb(10, 20, 90, 0.45))
ctx.addPath(bodyPath); ctx.setFillColor(rgb(255, 255, 255)); ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(bodyPath); ctx.clip()
let shade = CGGradient(colorsSpace: cs, colors: [rgb(255, 255, 255), rgb(222, 230, 246)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(shade, start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
ctx.restoreGState()

// Button split and divider.
ctx.setStrokeColor(rgb(170, 184, 214)); ctx.setLineWidth(10); ctx.setLineCap(.round)
ctx.move(to: CGPoint(x: 512, y: body.maxY - 6)); ctx.addLine(to: CGPoint(x: 512, y: 580)); ctx.strokePath()
ctx.move(to: CGPoint(x: body.minX + 18, y: 560)); ctx.addLine(to: CGPoint(x: body.maxX - 18, y: 560))
ctx.setStrokeColor(rgb(200, 210, 232)); ctx.setLineWidth(8); ctx.strokePath()

// Scroll wheel.
let wheel = CGRect(x: 512 - 30, y: 610, width: 60, height: 120)
ctx.addPath(CGPath(roundedRect: wheel, cornerWidth: 30, cornerHeight: 30, transform: nil))
let wheelGradient = CGGradient(colorsSpace: cs, colors: [rgb(80, 130, 255), rgb(44, 66, 200)] as CFArray, locations: [0, 1])!
ctx.saveGState(); ctx.clip()
ctx.drawLinearGradient(wheelGradient, start: CGPoint(x: 512, y: wheel.maxY), end: CGPoint(x: 512, y: wheel.minY), options: [])
ctx.restoreGState()

let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
