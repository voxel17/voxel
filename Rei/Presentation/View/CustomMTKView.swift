//
//  CustomMTKView.swift
//  Rei
//
//  macOS-specific Metal view with input handling
//

import MetalKit

#if os(macOS)
import AppKit

class CustomMTKView: MTKView {
    weak var sceneController: SceneController?
    private var isMouseLocked = false
    private var deleteHoldTimer: Timer?
    private var deleteHoldStartTime: TimeInterval = 0
    private var deleteHoldStartPoint: NSPoint = .zero
    private let deleteHoldDuration: TimeInterval = 0.55
    private let deleteHoldMovementTolerance: CGFloat = 8
    
    override var acceptsFirstResponder: Bool { return true }
    
    override func mouseDown(with event: NSEvent) {
        if !isMouseLocked {
            lockMouse()
        }
        startDeleteHold(at: convert(event.locationInWindow, from: nil))
    }
    
    override func mouseUp(with event: NSEvent) {
        cancelDeleteHold()
    }
    
    override func rightMouseDown(with event: NSEvent) {
        if isMouseLocked {
            unlockMouse()
        }
    }
    
    override func mouseMoved(with event: NSEvent) {
        if isMouseLocked {
            handleMouseDelta(event)
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        if isMouseLocked {
            let point = convert(event.locationInWindow, from: nil)
            if distance(from: deleteHoldStartPoint, to: point) > deleteHoldMovementTolerance {
                cancelDeleteHold()
            }
            handleMouseDelta(event)
            
            let center = NSPoint(x: bounds.midX, y: bounds.midY)
            warpCursor(to: center)
        }
    }
    
    override func keyDown(with event: NSEvent) {
        if let characters = event.charactersIgnoringModifiers {
            if characters.lowercased() == "\u{1b}" { // Escape key
                unlockMouse()
                return
            }
            sceneController?.inputHandler.handleKeyDown(characters.lowercased())
        }
    }
    
    override func keyUp(with event: NSEvent) {
        if let characters = event.charactersIgnoringModifiers {
            sceneController?.inputHandler.handleKeyUp(characters.lowercased())
        }
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        
        for trackingArea in trackingAreas {
            removeTrackingArea(trackingArea)
        }
        
        let options: NSTrackingArea.Options = [
            .mouseMoved,
            .activeInKeyWindow,
            .inVisibleRect,
            .mouseEnteredAndExited
        ]
        let trackingArea = NSTrackingArea(
            rect: bounds,
            options: options,
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea)
    }
    
    // MARK: - Mouse Locking
    
    private func lockMouse() {
        guard !isMouseLocked else { return }
        isMouseLocked = true
        window?.makeFirstResponder(self)
        NSCursor.hide()
        CGAssociateMouseAndMouseCursorPosition(0)
        
        let center = NSPoint(x: bounds.midX, y: bounds.midY)
        warpCursor(to: center)
    }
    
    private func unlockMouse() {
        guard isMouseLocked else { return }
        cancelDeleteHold()
        isMouseLocked = false
        NSCursor.unhide()
        CGAssociateMouseAndMouseCursorPosition(1)
        sceneController?.cameraController.resetMouseSmoothing()
    }
    
    private func warpCursor(to point: NSPoint) {
        if let window = window {
            let windowPoint = convert(point, to: nil)
            let screenPoint = window.convertToScreen(NSRect(origin: windowPoint, size: .zero)).origin
            CGWarpMouseCursorPosition(CGPoint(x: screenPoint.x, y: screenPoint.y))
        }
    }
    
    private func handleMouseDelta(_ event: NSEvent) {
        let deltaX = Float(event.deltaX)
        let deltaY = Float(event.deltaY)
        sceneController?.inputHandler.handleMouseMove(deltaX: deltaX, deltaY: deltaY)
    }

    private func startDeleteHold(at point: NSPoint) {
        cancelDeleteHold()
        deleteHoldStartPoint = point
        deleteHoldStartTime = CACurrentMediaTime()
        sceneController?.setDeletionProgress(0)

        let timer = Timer(timeInterval: 1.0 / 60.0, repeats: true) { [weak self] timer in
            guard let self else {
                timer.invalidate()
                return
            }

            let progress = Float((CACurrentMediaTime() - self.deleteHoldStartTime) / self.deleteHoldDuration)
            self.sceneController?.setDeletionProgress(progress)

            if progress >= 1 {
                timer.invalidate()
                self.deleteHoldTimer = nil
                self.sceneController?.deleteTargetVoxel()
                self.sceneController?.setDeletionProgress(0)
            }
        }
        deleteHoldTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func cancelDeleteHold() {
        deleteHoldTimer?.invalidate()
        deleteHoldTimer = nil
        sceneController?.setDeletionProgress(0)
    }

    private func distance(from start: NSPoint, to end: NSPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
    }

    deinit {
        cancelDeleteHold()
    }
}
#endif
