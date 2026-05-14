//
//  MainView.swift
//  Rei
//
//  Main application view - platform agnostic
//

import SwiftUI
import MetalKit

#if os(iOS)
import UIKit
#endif

struct MainView: View {
    @StateObject private var sceneController = SceneController()
    @State private var isControlPanelCollapsed = false
    @Environment(\.scenePhase) private var scenePhase
    
    var body: some View {
        VStack(spacing: 0) {
            // Renderer view
            ZStack {
                RenderContainer(sceneController: sceneController)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                CrosshairView(progress: sceneController.deletionProgress)
                    .allowsHitTesting(false)

                #if os(iOS)
                IOSMovementOverlay(sceneController: sceneController)
                #endif
            }
            
            // Control panel
            ControlPanelContainer(
                sceneController: sceneController,
                isCollapsed: $isControlPanelCollapsed
            )
        }
        .background(Color.black)
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            if phase != .active {
                sceneController.inputHandler.clearActiveKeys()
            }
        }
    }
}

// MARK: - Render Container
struct RenderContainer: View {
    let sceneController: SceneController
    
    var body: some View {
        #if os(macOS)
        MetalViewContainer(sceneController: sceneController)
        #elseif os(iOS)
        MetalViewContainerIOS(sceneController: sceneController)
        #else
        Text("Unsupported platform")
        #endif
    }
}

#if os(macOS)
// macOS Metal View Wrapper
struct MetalViewContainer: NSViewRepresentable {
    let sceneController: SceneController

    func makeCoordinator() -> Coordinator {
        Coordinator(sceneController: sceneController)
    }
    
    func makeNSView(context: Context) -> MTKView {
        let mtkView = CustomMTKView()
        mtkView.device = MTLCreateSystemDefaultDevice()
        mtkView.framebufferOnly = false
        mtkView.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
        mtkView.colorPixelFormat = .rgba16Float
        mtkView.depthStencilPixelFormat = .invalid
        mtkView.preferredFramesPerSecond = 60
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        
        // MTKView.delegate is weak, so the coordinator owns the renderer.
        mtkView.delegate = context.coordinator.renderer
        mtkView.sceneController = sceneController

        DispatchQueue.main.async {
            mtkView.window?.makeFirstResponder(mtkView)
        }
        
        return mtkView
    }
    
    func updateNSView(_ nsView: MTKView, context: Context) {
        nsView.setNeedsDisplay(nsView.bounds)
    }

    class Coordinator {
        let renderer: MetalRendererCore

        init(sceneController: SceneController) {
            self.renderer = MetalRendererCore(sceneController: sceneController)
        }
    }
}
#endif

#if os(iOS)
class TouchMTKView: MTKView {
    weak var sceneController: SceneController?
    private var deleteHoldTimer: Timer?
    private var deleteHoldStartTime: TimeInterval = 0
    private var didDeleteDuringCurrentHold = false
    private let deleteHoldDuration: TimeInterval = 0.55
    private let deleteHoldMovementTolerance: CGFloat = 12
    private let lookSensitivityMultiplier: Float = 2.6
    private var activeTouch: UITouch?
    private var touchStartPoint: CGPoint = .zero
    private var lastTouchPoint: CGPoint = .zero

    func configure(sceneController: SceneController) {
        self.sceneController = sceneController
        isMultipleTouchEnabled = true
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        touchStartPoint = touch.location(in: self)
        lastTouchPoint = touchStartPoint
        sceneController?.cameraController.resetMouseSmoothing()
        startDeleteHold()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }

        let point = activeTouch.location(in: self)
        let delta = CGPoint(x: point.x - lastTouchPoint.x, y: point.y - lastTouchPoint.y)
        lastTouchPoint = point

        if distance(from: touchStartPoint, to: point) > deleteHoldMovementTolerance {
            cancelDeleteHold()
        }

        sceneController?.inputHandler.handleMouseMove(
            deltaX: Float(delta.x) * lookSensitivityMultiplier,
            deltaY: Float(delta.y) * lookSensitivityMultiplier
        )
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let activeTouch, touches.contains(activeTouch) else { return }
        finishDeleteHoldIfReady()
        sceneController?.cameraController.resetMouseSmoothing()
        self.activeTouch = nil
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        cancelDeleteHold()
        sceneController?.cameraController.resetMouseSmoothing()
        activeTouch = nil
    }

    private func startDeleteHold() {
        cancelDeleteHold()
        didDeleteDuringCurrentHold = false
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
                self.didDeleteDuringCurrentHold = true
                self.sceneController?.deleteTargetVoxel()
                self.sceneController?.setDeletionProgress(0)
            }
        }
        deleteHoldTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func finishDeleteHoldIfReady() {
        if deleteHoldTimer != nil &&
           !didDeleteDuringCurrentHold &&
           CACurrentMediaTime() - deleteHoldStartTime >= deleteHoldDuration {
            sceneController?.deleteTargetVoxel()
        }
        cancelDeleteHold()
    }

    private func cancelDeleteHold() {
        deleteHoldTimer?.invalidate()
        deleteHoldTimer = nil
        sceneController?.setDeletionProgress(0)
    }

    private func distance(from start: CGPoint, to end: CGPoint) -> CGFloat {
        let dx = end.x - start.x
        let dy = end.y - start.y
        return sqrt(dx * dx + dy * dy)
    }

    deinit {
        cancelDeleteHold()
    }
}

// iOS Metal View Wrapper
struct MetalViewContainerIOS: UIViewRepresentable {
    let sceneController: SceneController

    func makeCoordinator() -> Coordinator {
        Coordinator(sceneController: sceneController)
    }
    
    func makeUIView(context: Context) -> MTKView {
        let view = TouchMTKView()
        view.device = MTLCreateSystemDefaultDevice()
        view.framebufferOnly = false
        view.clearColor = MTLClearColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0)
        view.colorPixelFormat = .rgba16Float
        view.depthStencilPixelFormat = .invalid
        view.preferredFramesPerSecond = 60
        view.enableSetNeedsDisplay = false
        view.isPaused = false
        
        view.delegate = context.coordinator.renderer
        view.configure(sceneController: sceneController)
        
        return view
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {}

    class Coordinator {
        let renderer: MetalRendererCore

        init(sceneController: SceneController) {
            self.renderer = MetalRendererCore(sceneController: sceneController)
        }
    }
}
#endif

// MARK: - Control Panel Container
struct ControlPanelContainer: View {
    let sceneController: SceneController
    @Binding var isCollapsed: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        isCollapsed.toggle()
                    }
                } label: {
                    Label(
                        isCollapsed ? "Show Controls" : "Hide Controls",
                        systemImage: isCollapsed ? "chevron.up" : "chevron.down"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: 40, height: 32)
                }
                .buttonStyle(.plain)

                if isCollapsed {
                    Text("Controls")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.75))
                    Spacer()
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(Color(white: 0.12))

            if !isCollapsed {
                ControlPanel(sceneController: sceneController)
                    .frame(height: 120)
            }
        }
        .background(Color(white: 0.15))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(white: 0.3)),
            alignment: .top
        )
    }
}

// MARK: - Control Panel
struct ControlPanel: View {
    let sceneController: SceneController
    
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 16) {
                // Voxel operations
                Button(action: {
                    sceneController.addSphere(
                        center: Vector3Int(64, 64, 64),
                        radius: 10,
                        material: .stone
                    )
                }) {
                    Label("Add Sphere", systemImage: "target")
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Button(action: {
                    sceneController.addCube(
                        min: Vector3Int(60, 60, 60),
                        max: Vector3Int(68, 68, 68),
                        material: .stone
                    )
                }) {
                    Label("Add Cube", systemImage: "square.grid.2x2")
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                // Terrain
                Button(action: {
                    sceneController.generateTerrain(scale: 0.05, height: 30)
                }) {
                    Label("Generate Terrain", systemImage: "mountain.2")
                        .foregroundColor(.white)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                
                Divider()
                    .frame(height: 40)
                    .background(Color.white.opacity(0.3))
                
                // Camera
                Button(action: {
                    sceneController.resetCamera()
                }) {
                    Label("Reset Camera", systemImage: "camera.fill")
                        .foregroundColor(.white)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Button(action: {
                    sceneController.clearAll()
                }) {
                    Label("Clear All", systemImage: "trash")
                        .foregroundColor(.white)
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                
                Spacer()

                Picker("Quality", selection: Binding(
                    get: { sceneController.renderQuality },
                    set: { sceneController.renderQuality = $0 }
                )) {
                    ForEach(RenderQuality.allCases) { quality in
                        Text(quality.rawValue).tag(quality)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 260)
                
                #if os(macOS)
                Text("WASD + Mouse to move | ESC to release mouse")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal)
                #else
                Text("Drag to rotate | Hold crosshair to delete")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal)
                #endif
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(white: 0.12))
    }
}

struct CrosshairView: View {
    let progress: Float

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.white.opacity(0.55), lineWidth: 1)
                .frame(width: 22, height: 22)

            Circle()
                .trim(from: 0, to: CGFloat(progress))
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 32, height: 32)
                .rotationEffect(.degrees(-90))

            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 2, height: 10)

            Rectangle()
                .fill(Color.white.opacity(0.7))
                .frame(width: 10, height: 2)
        }
        .shadow(radius: 2)
    }
}

#if os(iOS)
struct IOSMovementOverlay: View {
    let sceneController: SceneController

    var body: some View {
        VStack {
            Spacer()

            HStack(alignment: .bottom) {
                MovementControls(sceneController: sceneController)
                    .padding(.leading, 18)
                    .padding(.bottom, 18)

                Spacer()

                VStack(spacing: 10) {
                    HoldKeyButton(systemImage: "arrow.up.to.line", key: " ", sceneController: sceneController)
                    HoldKeyButton(systemImage: "arrow.down.to.line", key: "c", sceneController: sceneController)
                }
                .padding(.trailing, 18)
                .padding(.bottom, 18)
            }
        }
        .onDisappear {
            sceneController.inputHandler.clearActiveKeys()
        }
    }
}

struct MovementControls: View {
    let sceneController: SceneController

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                HoldKeyButton(systemImage: "arrow.up", key: "w", sceneController: sceneController)
                HStack(spacing: 8) {
                    HoldKeyButton(systemImage: "arrow.left", key: "a", sceneController: sceneController)
                    HoldKeyButton(systemImage: "arrow.down", key: "s", sceneController: sceneController)
                    HoldKeyButton(systemImage: "arrow.right", key: "d", sceneController: sceneController)
                }
            }
        }
    }
}

struct HoldKeyButton: View {
    let systemImage: String
    let key: String
    let sceneController: SceneController

    var body: some View {
        PressKeyButton(systemImage: systemImage, key: key, sceneController: sceneController)
            .frame(width: 54, height: 50)
    }
}

struct PressKeyButton: UIViewRepresentable {
    let systemImage: String
    let key: String
    let sceneController: SceneController

    func makeCoordinator() -> Coordinator {
        Coordinator(key: key, sceneController: sceneController)
    }

    func makeUIView(context: Context) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: systemImage), for: .normal)
        button.tintColor = .white
        button.backgroundColor = UIColor.black.withAlphaComponent(0.18)
        button.layer.cornerRadius = 10
        button.layer.borderColor = UIColor.white.withAlphaComponent(0.25).cgColor
        button.layer.borderWidth = 1
        button.adjustsImageWhenHighlighted = false

        button.addTarget(context.coordinator, action: #selector(Coordinator.press), for: [.touchDown, .touchDragEnter])
        button.addTarget(context.coordinator, action: #selector(Coordinator.releasePress), for: [
            .touchUpInside,
            .touchUpOutside,
            .touchCancel,
            .touchDragExit
        ])

        return button
    }

    func updateUIView(_ uiView: UIButton, context: Context) {
        uiView.setImage(UIImage(systemName: systemImage), for: .normal)
        context.coordinator.key = key
        context.coordinator.sceneController = sceneController
    }

    static func dismantleUIView(_ uiView: UIButton, coordinator: Coordinator) {
        coordinator.releasePress()
    }

    class Coordinator: NSObject {
        var key: String
        weak var sceneController: SceneController?
        private var isPressed = false

        init(key: String, sceneController: SceneController) {
            self.key = key
            self.sceneController = sceneController
        }

        @objc func press() {
            guard !isPressed else { return }
            isPressed = true
            sceneController?.inputHandler.handleKeyDown(key)
        }

        @objc func releasePress() {
            guard isPressed else { return }
            isPressed = false
            sceneController?.inputHandler.handleKeyUp(key)
        }

        deinit {
            releasePress()
        }
    }
}
#endif

#Preview {
    MainView()
}
