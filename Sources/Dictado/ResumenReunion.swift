import Foundation

/// Notas de reunión sin Centro de mando: cuando no hay un script de acciones (`centro.acciones`), la transcripción se
/// guarda como un archivo legible en `~/Documents/Reuniones` (o la carpeta del ajuste `reunionesCarpeta`) y, si el Mac
/// tiene Claude Code, le pide arriba un resumen con decisiones y pendientes (`claude -p`). Así cualquier persona tiene
/// notas útiles sin configurar nada más. El ajuste `resumenClaude` en `false` lo apaga y deja solo la transcripción.
enum ResumenReunion {
    /// Carpeta visible donde quedan las notas de cada reunión.
    static var carpeta: URL {
        if let c = UserDefaults.dictado.string(forKey: "reunionesCarpeta"), !c.isEmpty {
            return URL(fileURLWithPath: (c as NSString).expandingTildeInPath)
        }
        return URL(fileURLWithPath: NSHomeDirectory() + "/Documents/Reuniones")
    }

    /// El comando `claude` del Mac, si está instalado (la app no hereda el PATH de la terminal).
    static var claude: URL? {
        let casa = NSHomeDirectory()
        let candidatos = [casa + "/.local/bin/claude", casa + "/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        return candidatos.first { FileManager.default.isExecutableFile(atPath: $0) }.map { URL(fileURLWithPath: $0) }
    }

    static var usarClaude: Bool { UserDefaults.dictado.object(forKey: "resumenClaude") as? Bool ?? true }

    /// Guarda las notas de la reunión en la carpeta visible. Devuelve el aviso para la isla y si salió bien.
    nonisolated static func guardar(transcripcion ruta: URL, titulo: String, inicio: Date) -> (String, Bool) {
        guard let transcripcion = try? String(contentsOf: ruta, encoding: .utf8) else {
            return ("Transcripción guardada en el Mac", true)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "es_CO")
        f.dateFormat = "yyyy-MM-dd HHmm"
        let limpio = titulo.replacingOccurrences(of: "[/:\\\\]", with: "-", options: .regularExpression)
        let destino = carpeta.appendingPathComponent("\(f.string(from: inicio)) \(String(limpio.prefix(60))).md")

        var resumen: String?
        var problema: String?
        if usarClaude {
            if let claude {
                (resumen, problema) = resumir(transcripcion, con: claude)
            } else {
                problema = "sin Claude Code para el resumen"
            }
        }
        var texto = "# \(titulo)\n\n"
        if let resumen { texto += resumen.trimmingCharacters(in: .whitespacesAndNewlines) + "\n\n---\n\n## Transcripción\n\n" }
        // La transcripción ya trae su título: se quita para no repetirlo.
        texto += transcripcion.split(separator: "\n", omittingEmptySubsequences: false)
            .drop { $0.hasPrefix("# ") || $0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: "\n") + "\n"
        do {
            try FileManager.default.createDirectory(at: carpeta, withIntermediateDirectories: true)
            try texto.write(to: destino, atomically: true, encoding: .utf8)
        } catch {
            return ("Transcripción guardada, pero no se pudo escribir en \(carpeta.path)", false)
        }
        let donde = carpeta.path.hasPrefix(NSHomeDirectory() + "/Documents") ? "Documentos → " + carpeta.lastPathComponent : carpeta.path
        if resumen != nil { return ("Notas listas: «\(titulo)» en \(donde)", true) }
        return ("Transcripción lista en \(donde)" + (problema.map { " (\($0))" } ?? ""), true)
    }

    /// Le pide a Claude Code el resumen. Devuelve el texto o el motivo del fallo.
    nonisolated static func resumir(_ transcripcion: String, con claude: URL) -> (String?, String?) {
        let pedido = """
        Eres un asistente que escribe notas de reunión en español, claras y breves. Abajo va la transcripción automática \
        de una reunión ("Tú" es quien grabó; "Otros", el resto de participantes). Puede tener errores de transcripción: \
        corrígelos por contexto y no inventes nada que no se haya dicho.

        Responde solo con este markdown, sin introducción:

        ## Resumen
        (3 a 6 frases)

        ## Decisiones
        - (una por línea; "Ninguna" si no hubo)

        ## Pendientes
        - [ ] (qué, quién y para cuándo si se dijo)

        ## Temas abiertos
        - (lo que quedó sin resolver; omite la sección si no hay)

        Transcripción:

        \(transcripcion)
        """
        let p = Process()
        p.executableURL = claude
        p.arguments = ["-p", "--output-format", "text"]
        var entorno = ProcessInfo.processInfo.environment
        // Si Dictado se abrió desde una sesión de Claude Code, no se hereda esa sesión.
        for clave in entorno.keys where clave.hasPrefix("CLAUDE") { entorno[clave] = nil }
        entorno["PATH"] = [NSHomeDirectory() + "/.local/bin", "/opt/homebrew/bin", "/usr/local/bin", entorno["PATH"] ?? "/usr/bin:/bin"]
            .joined(separator: ":")
        p.environment = entorno
        p.currentDirectoryURL = URL(fileURLWithPath: NSTemporaryDirectory())
        let entrada = Pipe(), salida = Pipe()
        p.standardInput = entrada
        p.standardOutput = salida
        p.standardError = FileHandle.nullDevice
        let fin = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in fin.signal() }
        do { try p.run() } catch { return (nil, "no se pudo abrir Claude Code") }
        // La transcripción va por la entrada estándar: una reunión larga no cabe como argumento.
        DispatchQueue.global().async {
            entrada.fileHandleForWriting.write(Data(pedido.utf8))
            try? entrada.fileHandleForWriting.close()
        }
        final class Caja: @unchecked Sendable { var datos = Data() }
        let caja = Caja()
        let lector = DispatchQueue(label: "resumen-reunion")
        lector.async { caja.datos = salida.fileHandleForReading.readDataToEndOfFile() }
        if fin.wait(timeout: .now() + 300) == .timedOut {
            p.terminate()
            return (nil, "Claude tardó demasiado")
        }
        lector.sync {}
        let texto = String(decoding: caja.datos, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard p.terminationStatus == 0, texto.contains("## ") else {
            return (nil, "Claude no respondió; abre Claude Code una vez para iniciar sesión")
        }
        return (texto, nil)
    }
}
