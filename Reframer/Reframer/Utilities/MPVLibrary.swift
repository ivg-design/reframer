import Foundation
import Darwin

// MARK: - MPV C Types

typealias mpv_handle = OpaquePointer

typealias mpv_render_context = OpaquePointer

typealias mpv_create_fn = @convention(c) () -> mpv_handle?
typealias mpv_initialize_fn = @convention(c) (mpv_handle?) -> Int32
typealias mpv_terminate_destroy_fn = @convention(c) (mpv_handle?) -> Void
typealias mpv_set_option_string_fn = @convention(c) (mpv_handle?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
typealias mpv_command_fn = @convention(c) (mpv_handle?, UnsafePointer<UnsafePointer<CChar>?>?) -> Int32
typealias mpv_set_property_fn = @convention(c) (mpv_handle?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
typealias mpv_get_property_fn = @convention(c) (mpv_handle?, UnsafePointer<CChar>?, Int32, UnsafeMutableRawPointer?) -> Int32
typealias mpv_get_property_string_fn = @convention(c) (mpv_handle?, UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
typealias mpv_free_fn = @convention(c) (UnsafeMutableRawPointer?) -> Void
typealias mpv_set_wakeup_callback_fn = @convention(c) (mpv_handle?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, UnsafeMutableRawPointer?) -> Void
typealias mpv_wait_event_fn = @convention(c) (mpv_handle?, Double) -> UnsafePointer<mpv_event>?
typealias mpv_event_name_fn = @convention(c) (Int32) -> UnsafePointer<CChar>?
typealias mpv_error_string_fn = @convention(c) (Int32) -> UnsafePointer<CChar>?

typealias mpv_render_context_create_fn = @convention(c) (UnsafeMutablePointer<mpv_render_context?>?, mpv_handle?, UnsafePointer<mpv_render_param>?) -> Int32
typealias mpv_render_context_free_fn = @convention(c) (mpv_render_context?) -> Void
typealias mpv_render_context_set_update_callback_fn = @convention(c) (mpv_render_context?, (@convention(c) (UnsafeMutableRawPointer?) -> Void)?, UnsafeMutableRawPointer?) -> Void
typealias mpv_render_context_render_fn = @convention(c) (mpv_render_context?, UnsafePointer<mpv_render_param>?) -> Void

struct mpv_event {
    var event_id: Int32
    var error: Int32
    var reply_userdata: UInt64
    var data: UnsafeMutableRawPointer?
}

struct mpv_opengl_init_params {
    var get_proc_address: (@convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>?) -> UnsafeMutableRawPointer?)?
    var get_proc_address_ctx: UnsafeMutableRawPointer?
}

struct mpv_opengl_fbo {
    var fbo: Int32
    var w: Int32
    var h: Int32
    var internal_format: Int32
}

struct mpv_render_param {
    var type: Int32
    var data: UnsafeMutableRawPointer?
}

enum MPVFormat {
    static let none: Int32 = 0
    static let string: Int32 = 1
    static let osdString: Int32 = 2
    static let flag: Int32 = 3
    static let int64: Int32 = 4
    static let double: Int32 = 5
    static let node: Int32 = 6
    static let nodeArray: Int32 = 7
    static let nodeMap: Int32 = 8
    static let byteArray: Int32 = 9
}

enum MPVRenderParamType {
    static let invalid: Int32 = 0
    static let apiType: Int32 = 1
    static let openglInitParams: Int32 = 2
    static let openglFBO: Int32 = 3
    static let flipY: Int32 = 4
}

// MARK: - MPV Loader

final class MPVLibrary {
    static let shared = MPVLibrary()

    private(set) var isLoaded = false
    private var handle: UnsafeMutableRawPointer?

    private(set) var mpv_create: mpv_create_fn!
    private(set) var mpv_initialize: mpv_initialize_fn!
    private(set) var mpv_terminate_destroy: mpv_terminate_destroy_fn!
    private(set) var mpv_set_option_string: mpv_set_option_string_fn!
    private(set) var mpv_command: mpv_command_fn!
    private(set) var mpv_set_property: mpv_set_property_fn!
    private(set) var mpv_get_property: mpv_get_property_fn!
    private(set) var mpv_get_property_string: mpv_get_property_string_fn!
    private(set) var mpv_free: mpv_free_fn!
    private(set) var mpv_set_wakeup_callback: mpv_set_wakeup_callback_fn!
    private(set) var mpv_wait_event: mpv_wait_event_fn!
    private(set) var mpv_event_name: mpv_event_name_fn!
    private(set) var mpv_error_string: mpv_error_string_fn!

    private(set) var mpv_render_context_create: mpv_render_context_create_fn!
    private(set) var mpv_render_context_free: mpv_render_context_free_fn!
    private(set) var mpv_render_context_set_update_callback: mpv_render_context_set_update_callback_fn!
    private(set) var mpv_render_context_render: mpv_render_context_render_fn!

    func load(at path: String) throws {
        if isLoaded { return }

        guard let libHandle = dlopen(path, RTLD_NOW | RTLD_GLOBAL) else {
            throw MPVLoadError.loadFailed(String(cString: dlerror()))
        }

        handle = libHandle
        do {
            mpv_create = try loadSymbol("mpv_create")
            mpv_initialize = try loadSymbol("mpv_initialize")
            mpv_terminate_destroy = try loadSymbol("mpv_terminate_destroy")
            mpv_set_option_string = try loadSymbol("mpv_set_option_string")
            mpv_command = try loadSymbol("mpv_command")
            mpv_set_property = try loadSymbol("mpv_set_property")
            mpv_get_property = try loadSymbol("mpv_get_property")
            mpv_get_property_string = try loadSymbol("mpv_get_property_string")
            mpv_free = try loadSymbol("mpv_free")
            mpv_set_wakeup_callback = try loadSymbol("mpv_set_wakeup_callback")
            mpv_wait_event = try loadSymbol("mpv_wait_event")
            mpv_event_name = try loadSymbol("mpv_event_name")
            mpv_error_string = try loadSymbol("mpv_error_string")

            mpv_render_context_create = try loadSymbol("mpv_render_context_create")
            mpv_render_context_free = try loadSymbol("mpv_render_context_free")
            mpv_render_context_set_update_callback = try loadSymbol("mpv_render_context_set_update_callback")
            mpv_render_context_render = try loadSymbol("mpv_render_context_render")
        } catch {
            dlclose(libHandle)
            handle = nil
            throw error
        }

        isLoaded = true
    }

    func unload() {
        if let handle = handle {
            dlclose(handle)
        }
        handle = nil
        isLoaded = false
    }

    func errorString(_ code: Int32) -> String {
        guard let mpv_error_string = mpv_error_string else { return "mpv error \(code)" }
        if let cStr = mpv_error_string(code) {
            return String(cString: cStr)
        }
        return "mpv error \(code)"
    }

    private func loadSymbol<T>(_ name: String) throws -> T {
        guard let handle = handle else {
            throw MPVLoadError.loadFailed("libmpv not loaded")
        }
        guard let symbol = dlsym(handle, name) else {
            throw MPVLoadError.symbolMissing(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }
}

enum MPVLoadError: LocalizedError {
    case loadFailed(String)
    case symbolMissing(String)

    var errorDescription: String? {
        switch self {
        case .loadFailed(let message):
            return "Failed to load libmpv: \(message)"
        case .symbolMissing(let symbol):
            return "Missing libmpv symbol: \(symbol)"
        }
    }
}
