import AppKit

// Точка входа на AppKit вместо `@main struct App: App`.
//
// У ClipFlow нет главного окна: это menu bar app, чьё «окно» — floating NSPanel,
// который должен появляться, не забирая активность у текущего приложения.
// SwiftUI App-lifecycle требует хотя бы одну сцену и управляет активацией
// по своим правилам, поэтому здесь AppKit даёт меньше кода и больше контроля.
// SwiftUI используется там, где он силён — во всём UI внутри окон.

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.run()
