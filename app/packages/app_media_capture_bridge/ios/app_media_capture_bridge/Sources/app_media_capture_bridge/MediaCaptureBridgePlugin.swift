import Flutter
import MediaCaptureBridgeCore
import UIKit

@MainActor
public final class MediaCaptureBridgePlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
    private let environment: MediaCaptureProductionEnvironment
    private weak var messenger: FlutterBinaryMessenger?
    private var sceneDisconnectObserver: NSObjectProtocol?
    private var ownerSceneByWindow: [ObjectIdentifier: ObjectIdentifier] = [:]

    private lazy var controller = MediaCaptureBridgeController(
        core: environment.service,
        transferStore: environment.transferStore,
        presentationOwner: { [weak self] in self?.currentPresentationOwner() },
        ownerIsAlive: { [weak self] identity in self?.isOwnerWindowAlive(identity) == true }
    )

    private init(messenger: FlutterBinaryMessenger) {
        environment = MediaCaptureProductionEnvironment()
        self.messenger = messenger
        super.init()
        sceneDisconnectObserver = NotificationCenter.default.addObserver(
            forName: UIScene.didDisconnectNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let scene = notification.object as? UIWindowScene else { return }
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sceneIdentity = ObjectIdentifier(scene)
                let owners = ownerSceneByWindow.compactMap { owner, ownerScene in
                    ownerScene == sceneIdentity ? owner : nil
                }
                for owner in owners {
                    ownerSceneByWindow.removeValue(forKey: owner)
                    controller.ownerDestroyed(owner)
                }
            }
        }
    }

    deinit {
        if let sceneDisconnectObserver {
            NotificationCenter.default.removeObserver(sceneDisconnectObserver)
        }
    }

    public static func register(with registrar: FlutterPluginRegistrar) {
        let messenger = registrar.messenger()
        let instance = MediaCaptureBridgePlugin(messenger: messenger)
        let methodChannel = FlutterMethodChannel(
            name: mediaCaptureCommandsChannel,
            binaryMessenger: messenger
        )
        let eventChannel = FlutterEventChannel(
            name: mediaCaptureEventsChannel,
            binaryMessenger: messenger
        )
        registrar.addMethodCallDelegate(instance, channel: methodChannel)
        eventChannel.setStreamHandler(instance)
        registrar.publish(instance)
    }

    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        guard MediaCaptureWireCodec.methods.contains(call.method) else {
            result(FlutterMethodNotImplemented)
            return
        }
        controller.handle(
            operation: call.method,
            arguments: call.arguments,
            completion: FlutterBridgeCompletion(result: result)
        )
    }

    public func onListen(
        withArguments arguments: Any?,
        eventSink events: @escaping FlutterEventSink
    ) -> FlutterError? {
        controller.onListen(arguments: arguments, sink: FlutterBridgeEventSink(sink: events))
        return nil
    }

    public func onCancel(withArguments _: Any?) -> FlutterError? {
        controller.onCancel()
        return nil
    }

    public func detachFromEngine(for _: FlutterPluginRegistrar) {
        if let sceneDisconnectObserver {
            NotificationCenter.default.removeObserver(sceneDisconnectObserver)
            self.sceneDisconnectObserver = nil
        }
        ownerSceneByWindow.removeAll(keepingCapacity: false)
        controller.detachEngine()
    }

    private func currentPresentationOwner() -> MediaCapturePresentationOwner? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows = scenes.flatMap { scene in
            scene.windows.map { window in (scene: scene, window: window) }
        }
        let candidates = windows.map { candidate in
            MediaCaptureOwnerCandidate(
                identity: ObjectIdentifier(candidate.window),
                isForeground: candidate.scene.activationState == .foregroundActive,
                isVisible: !candidate.window.isHidden && candidate.window.alpha > 0,
                belongsToCurrentEngine: windowHostsCurrentEngine(candidate.window)
            )
        }
        guard let windowIdentity = MediaCaptureOwnerResolver.uniqueForegroundOwner(candidates),
              let selected = windows.first(where: { ObjectIdentifier($0.window) == windowIdentity }),
              let root = selected.window.rootViewController
        else {
            return nil
        }
        ownerSceneByWindow[windowIdentity] = ObjectIdentifier(selected.scene)
        return environment.presentationOwner(
            viewController: topViewController(from: root),
            identity: windowIdentity
        )
    }

    private func isOwnerWindowAlive(_ identity: ObjectIdentifier) -> Bool {
        let candidates = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .map { window in
                MediaCaptureOwnerCandidate(
                    identity: ObjectIdentifier(window),
                    isForeground: true,
                    isVisible: !window.isHidden && window.alpha > 0,
                    belongsToCurrentEngine: windowHostsCurrentEngine(window)
                )
        }
        return MediaCaptureOwnerResolver.isTrackedOwnerAlive(
            identity,
            candidates: candidates
        )
    }

    private func windowHostsCurrentEngine(_ window: UIWindow) -> Bool {
        guard let root = window.rootViewController else { return false }
        return hierarchyContainsCurrentFlutterEngine(root)
    }

    private func hierarchyContainsCurrentFlutterEngine(_ viewController: UIViewController) -> Bool {
        guard let messenger else { return false }
        return MediaCaptureViewControllerHierarchy.contains(viewController) { candidate in
            guard let flutter = candidate as? FlutterViewController else { return false }
            return flutter.binaryMessenger === messenger
        }
    }

    private func topViewController(from root: UIViewController) -> UIViewController {
        if let presented = root.presentedViewController, !presented.isBeingDismissed {
            return topViewController(from: presented)
        }
        if let navigation = root as? UINavigationController,
           let visible = navigation.visibleViewController {
            return topViewController(from: visible)
        }
        if let tabs = root as? UITabBarController,
           let selected = tabs.selectedViewController {
            return topViewController(from: selected)
        }
        if let split = root as? UISplitViewController,
           let trailing = split.viewControllers.last {
            return topViewController(from: trailing)
        }
        return root
    }
}

@MainActor
private final class FlutterBridgeCompletion: MediaCaptureBridgeCompletion {
    private let result: FlutterResult
    private var completed = false

    init(result: @escaping FlutterResult) {
        self.result = result
    }

    func success(_ value: [String: Any]) {
        guard !completed else { return }
        completed = true
        result(FlutterWireValue.convert(value))
    }

    func failure(_ failure: MediaCaptureWireFailure) {
        guard !completed else { return }
        completed = true
        result(FlutterWireValue.error(failure))
    }
}

@MainActor
private final class FlutterBridgeEventSink: MediaCaptureBridgeEventSink {
    private let sink: FlutterEventSink
    private var ended = false

    init(sink: @escaping FlutterEventSink) {
        self.sink = sink
    }

    func success(_ value: [String: Any]) {
        guard !ended else { return }
        sink(FlutterWireValue.convert(value))
    }

    func failure(_ failure: MediaCaptureWireFailure) {
        guard !ended else { return }
        ended = true
        sink(FlutterWireValue.error(failure))
    }

    func endOfStream() {
        guard !ended else { return }
        ended = true
        sink(FlutterEndOfEventStream)
    }
}

private enum FlutterWireValue {
    static func convert(_ value: Any) -> Any {
        if let bytes = value as? MediaCaptureWireBytes {
            return FlutterStandardTypedData(bytes: bytes.takeData())
        }
        if let dictionary = value as? [String: Any] {
            return dictionary.mapValues(convert)
        }
        if let array = value as? [Any] {
            return array.map(convert)
        }
        return value
    }

    static func error(_ failure: MediaCaptureWireFailure) -> FlutterError {
        FlutterError(
            code: failure.code,
            message: "Media capture request failed.",
            details: failure.details
        )
    }
}
