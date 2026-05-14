//
//  InputHandler.swift
//  Rei
//
//  Platform-agnostic input abstraction
//

import Foundation
import CoreGraphics
import QuartzCore

/// Abstract input protocol for cross-platform compatibility
protocol InputHandler {
    func handleKeyDown(_ key: String)
    func handleKeyUp(_ key: String)
    func handleMouseMove(deltaX: Float, deltaY: Float)
    func handleMouseClick(at point: CGPoint)
    func getActiveKeys() -> Set<String>
    func clearActiveKeys()
}

/// Concrete implementation of input handler
class DefaultInputHandler: InputHandler {
    private var activeKeys: Set<String> = []
    private var lastClickTime: TimeInterval = 0
    private let clickCooldown: TimeInterval = 0.1
    
    weak var sceneDelegate: InputSceneDelegate?
    
    func handleKeyDown(_ key: String) {
        activeKeys.insert(key.lowercased())
    }
    
    func handleKeyUp(_ key: String) {
        activeKeys.remove(key.lowercased())
    }
    
    func handleMouseMove(deltaX: Float, deltaY: Float) {
        sceneDelegate?.onMouseMove(deltaX: deltaX, deltaY: deltaY)
    }
    
    func handleMouseClick(at point: CGPoint) {
        let currentTime = CACurrentMediaTime()
        if currentTime - lastClickTime < clickCooldown {
            return
        }
        lastClickTime = currentTime
        sceneDelegate?.onMouseClick(at: point)
    }
    
    func getActiveKeys() -> Set<String> {
        return activeKeys
    }

    func clearActiveKeys() {
        activeKeys.removeAll()
    }
}

/// Delegate protocol for scene input callbacks
protocol InputSceneDelegate: AnyObject {
    func onMouseMove(deltaX: Float, deltaY: Float)
    func onMouseClick(at point: CGPoint)
}

import CoreGraphics
