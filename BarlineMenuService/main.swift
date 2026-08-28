//
//  main.swift
//  BarlineMenuService
//

import Foundation

SourcePIDCache.shared.start()
Listener.shared.activate()
RunLoop.current.run()
