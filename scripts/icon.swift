import AppKit
let directory = CommandLine.arguments[1]
for size in [16,32,128,256,512] {
    for scale in [1,2] {
        let px = size * scale
        let image = NSImage(size: NSSize(width:px,height:px))
        image.lockFocus()
        let factor = CGFloat(px)/1024
        let transform = NSAffineTransform(); transform.scale(by:factor); transform.concat()
        let box = NSBezierPath(roundedRect:NSRect(x:50,y:50,width:924,height:924),xRadius:210,yRadius:210)
        NSGradient(starting:NSColor(calibratedRed:0.05,green:0.31,blue:0.36,alpha:1),ending:NSColor(calibratedRed:0.03,green:0.65,blue:0.61,alpha:1))!.draw(in:box,angle:65)
        let shield = NSBezierPath(); shield.move(to:NSPoint(x:512,y:810)); shield.line(to:NSPoint(x:760,y:715)); shield.line(to:NSPoint(x:730,y:430)); shield.curve(to:NSPoint(x:512,y:210),controlPoint1:NSPoint(x:710,y:340),controlPoint2:NSPoint(x:610,y:250)); shield.curve(to:NSPoint(x:294,y:430),controlPoint1:NSPoint(x:414,y:250),controlPoint2:NSPoint(x:314,y:340)); shield.line(to:NSPoint(x:264,y:715)); shield.close()
        NSColor.white.withAlphaComponent(0.93).setStroke(); shield.lineWidth = 42; shield.lineJoinStyle = .round; shield.stroke()
        for y in [460,580] { for x in [412,512,612] { NSColor.white.setFill(); NSBezierPath(ovalIn:NSRect(x:x-26,y:y-26,width:52,height:52)).fill() } }
        image.unlockFocus()
        let data = NSBitmapImageRep(data:image.tiffRepresentation!)!.representation(using:.png,properties:[:])!
        let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
        try data.write(to:URL(fileURLWithPath:directory).appendingPathComponent(name))
    }
}
