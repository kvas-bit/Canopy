import Foundation
import Metal

public enum MetalShaderLibraryError: Error, LocalizedError {
    case shaderDirectoryMissing
    case compilationFailed(String)

    public var errorDescription: String? {
        switch self {
        case .shaderDirectoryMissing:
            return "Could not find Canopy Metal shader sources or default.metallib."
        case .compilationFailed(let msg):
            return "Metal shader compilation failed: \(msg)"
        }
    }
}

public enum MetalShaderLibraryLoader {
    public static func loadLibrary(device: MTLDevice) throws -> MTLLibrary {
        if let mainLibURL = Bundle.main.url(forResource: "default", withExtension: "metallib"),
           let lib = try? device.makeLibrary(URL: mainLibURL) {
            return lib
        }

        let shaderFiles = [
            "PostProcess.metal",
            "Meadow.metal",
            "WildMeadow.metal",
            "Moss.metal",
            "Stream.metal",
            "Dunes.metal"
        ]

        guard let shaderFolderURL = Bundle.module.url(forResource: "Shaders", withExtension: nil) else {
            if let defaultLib = device.makeDefaultLibrary() {
                return defaultLib
            }
            throw MetalShaderLibraryError.shaderDirectoryMissing
        }

        let sharedHeaderURL = shaderFolderURL.appendingPathComponent("ShaderShared.h")
        let sharedHeaderSource = try String(contentsOf: sharedHeaderURL, encoding: .utf8)

        var combinedSource = sharedHeaderSource + "\n\n"
        for filename in shaderFiles {
            let fileURL = shaderFolderURL.appendingPathComponent(filename)
            let raw = try String(contentsOf: fileURL, encoding: .utf8)
            let stripped = raw.replacingOccurrences(of: "#include \"ShaderShared.h\"", with: "")
            combinedSource += "// --- \(filename) ---\n" + stripped + "\n\n"
        }

        let options = MTLCompileOptions()
        if #available(macOS 15.0, *) {
            options.mathMode = .fast
        }
        do {
            return try device.makeLibrary(source: combinedSource, options: options)
        } catch {
            throw MetalShaderLibraryError.compilationFailed(error.localizedDescription)
        }
    }
}
