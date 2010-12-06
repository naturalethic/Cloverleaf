global.util     = require 'util'
global.put      = (args...) -> util.print a for a in args
global.puts     = (args...) -> put args.join('\n') + '\n'
global.p        = (args...) -> puts util.inspect(a) for a in args
global.pl       = (args...) -> put args.join(', ') + '\n'

frame = NSScreen.mainScreen().visibleFrame()
window = NSWindow.alloc() initWithContentRect:[frame[0] + 3, frame[3] - 420, 400, 400], styleMask:1, backing:2, defer:false
window setTitle:'TestApp'
window makeKeyAndOrderFront:null


