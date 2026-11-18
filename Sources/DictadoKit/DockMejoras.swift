import CoreGraphics
import Foundation

// Lógica pura del Dock propio que se prueba con `swift test`: dónde se pega la barra, iconos propios por app, el estado de la
// papelera, editar la línea `dock:`, la pila (cuadrícula o abanico) de una carpeta, la navegación con flechas y las carpetas que
// están abiertas en el Finder.

// MARK: - Dónde se pega la barra

public enum ColocacionDock {
    /// Lo que el Dock del sistema le quita a la pantalla por abajo (puntos). Solo cuenta si está abajo y fijo (sin ocultarse solo):
    /// con el Dock del sistema escondido, a un lado o sin dato, no se reserva nada y la barra queda pegada a su margen. Antes se
    /// leía siempre `visibleFrame.minY`, que cambia a destiempo al cambiar de resolución o conectar otra pantalla (el Dock del
    /// sistema se reacomoda después del aviso) y dejaba un hueco vacío debajo de la barra.
    public static func reservaInferior(frame: CGRect, visible: CGRect, dockSistemaAbajoFijo: Bool, maximo: Double = 160) -> Double {
        guard dockSistemaAbajoFijo else { return 0 }
        let r = Double(visible.minY - frame.minY)
        guard r.isFinite else { return 0 }
        return min(max(r, 0), maximo)
    }

    /// La y de la parte de abajo de la ventana de la barra.
    public static func base(frame: CGRect, visible: CGRect, dockSistemaAbajoFijo: Bool) -> Double {
        Double(frame.minY) + reservaInferior(frame: frame, visible: visible, dockSistemaAbajoFijo: dockSistemaAbajoFijo)
    }

    /// Cuándo se vuelve a colocar tras un cambio de pantalla (segundos): ya, y otra vez cuando el Dock del sistema terminó de moverse.
    public static let reintentos: [Double] = [0, 0.4, 1.5]

    /// ¿Reserva el Dock del sistema la zona de abajo? `orientacion` y `autohide` son los valores de `com.apple.dock` (solo lectura).
    public static func dockSistemaAbajoFijo(orientacion: String?, autohide: Bool?) -> Bool {
        (orientacion ?? "bottom") == "bottom" && autohide != true
    }
}

// MARK: - Iconos propios

/// `iconos.txt`: una línea por app, `nombre o identificador = ruta del PNG` (el `~` se expande). Líneas con # son comentarios.
public enum IconosPersonalizados {
    public static func leer(_ texto: String, home: String = NSHomeDirectory()) -> [String: String] {
        var salida: [String: String] = [:]
        for cruda in texto.split(separator: "\n") {
            let linea = cruda.trimmingCharacters(in: .whitespaces)
            if linea.isEmpty || linea.hasPrefix("#") { continue }
            guard let igual = linea.firstIndex(of: "=") else { continue }
            let clave = BusquedaApps.normalizar(String(linea[..<igual]))
            let ruta = linea[linea.index(after: igual)...].trimmingCharacters(in: .whitespaces)
            if !clave.isEmpty, !ruta.isEmpty { salida[clave] = ReglasDock.expandir(ruta, home: home) }
        }
        return salida
    }

    /// La ruta del icono propio de una app (por identificador o por nombre), si hay.
    public static func ruta(_ app: EntradaApp, en mapa: [String: String]) -> String? {
        if let id = app.bundleID, let r = mapa[BusquedaApps.normalizar(id)] { return r }
        return mapa[BusquedaApps.normalizar(app.nombre)]
    }
}

// MARK: - Papelera

public enum EstadoPapelera {
    /// ¿Hay algo en la Papelera? `listado` son los nombres si macOS dejó leer la carpeta (nil si no: falta Acceso total al disco);
    /// `entradas` es la cuenta de elementos que da el sistema sin abrirla (nlink − 2 en APFS). Con el listado manda él (sin
    /// `.DS_Store`); sin él, la cuenta: más de uno es que hay algo (uno solo suele ser el `.DS_Store` de Finder).
    public static func llena(listado: [String]?, entradas: Int?) -> Bool {
        if let listado { return listado.contains { $0 != ".DS_Store" } }
        guard let entradas else { return false }
        return entradas > 1
    }
}

// MARK: - La línea `dock:`

extension ReglasDock {
    /// Las piezas como las escribe el archivo (la inversa de `analizar`).
    public static func serializar(_ piezas: [PiezaDock], home: String = NSHomeDirectory()) -> String {
        var partes: [String] = []
        for p in limpiarHuecos(piezas) {
            switch p {
            case .hueco: partes.append("|")
            case .reloj: partes.append("reloj")
            case .agenda: partes.append("agenda")
            case .agentes: partes.append("agentes")
            case .tareas: partes.append("tareas")
            case .plan: partes.append("plan")
            case .dictar: partes.append("dictar")
            case .foco: partes.append("foco")
            case .musica: partes.append("musica")
            case .mac: partes.append("mac")
            case .bateria: partes.append("bateria")
            case .fecha: partes.append("fecha")
            case .papelera: partes.append("papelera")
            case .clima: partes.append("clima")
            case .lanzador: partes.append("lanzador")
            case .abiertas: partes.append("abiertas")
            case .finder: partes.append("finder")
            case .app(let c): partes.append(pieza(c, home: home) == .app(c) ? c : "app:" + c)
            case .grupo(let n): partes.append("grupo:" + n)
            case .carpeta(let r): partes.append("carpeta:" + (r.hasPrefix(home + "/") ? "~" + r.dropFirst(home.count) : r))
            }
        }
        return partes.joined(separator: ", ").replacingOccurrences(of: ", |, ", with: ", | ")
            .replacingOccurrences(of: ", |", with: " |")
    }

    /// Fija la app (al final de su bloque de apps, antes del hueco que sigue) o la quita si ya estaba.
    public static func alternarApp(_ piezas: [PiezaDock], id: String, nombre: String? = nil) -> [PiezaDock] {
        let coincide: (PiezaDock) -> Bool = { p in
            guard case .app(let c) = p else { return false }
            return BusquedaApps.normalizar(c) == BusquedaApps.normalizar(id) || nombre.map { BusquedaApps.normalizar(c) == BusquedaApps.normalizar($0) } == true
        }
        if piezas.contains(where: coincide) { return limpiarHuecos(piezas.filter { !coincide($0) }) }
        var salida = piezas
        if let ultima = salida.lastIndex(where: { $0.esApp }) { salida.insert(.app(id), at: ultima + 1) }
        else if let a = salida.firstIndex(of: .abiertas) ?? salida.firstIndex(where: { if case .carpeta = $0 { return true } else { return false } }) { salida.insert(contentsOf: [.app(id), .hueco], at: a) }
        else { salida.append(contentsOf: [.hueco, .app(id)]) }
        return limpiarHuecos(salida)
    }

    /// ¿Está fija esa app?
    public static func tieneApp(_ piezas: [PiezaDock], id: String, nombre: String? = nil) -> Bool {
        piezas.contains { p in
            guard case .app(let c) = p else { return false }
            return BusquedaApps.normalizar(c) == BusquedaApps.normalizar(id) || nombre.map { BusquedaApps.normalizar(c) == BusquedaApps.normalizar($0) } == true
        }
    }

    /// Cambia la línea `dock:` del espacio `nombre` en el texto de `espacios.txt` (la crea si no la tenía). No toca nada más.
    public static func reemplazarLineaDock(en texto: String, espacio nombre: String, por linea: String) -> String {
        var lineas = texto.components(separatedBy: "\n")
        guard let inicio = lineas.firstIndex(where: { $0.trimmingCharacters(in: .whitespaces).lowercased() == "[" + nombre.lowercased() + "]" }) else { return texto }
        var fin = lineas.count
        for i in (inicio + 1)..<lineas.count where lineas[i].trimmingCharacters(in: .whitespaces).hasPrefix("[") { fin = i; break }
        if let existente = (inicio + 1..<fin).first(where: { BusquedaApps.normalizar(lineas[$0].split(separator: ":").first.map(String.init) ?? "") == "dock" }) {
            lineas[existente] = "dock: " + linea
        } else {
            var punto = fin
            while punto > inicio + 1, lineas[punto - 1].trimmingCharacters(in: .whitespaces).isEmpty { punto -= 1 }
            lineas.insert("dock: " + linea, at: punto)
        }
        return lineas.joined(separator: "\n")
    }
}

// MARK: - La pila de una carpeta

public enum ModoPila: Equatable, Sendable { case abanico, cuadricula }

public enum PilaDock {
    /// Como las pilas de macOS: pocos elementos, abanico; muchos, cuadrícula.
    public static let maximoAbanico = 8

    public static func modo(cuantos: Int, preferencia: String? = nil) -> ModoPila {
        switch preferencia {
        case "abanico": return .abanico
        case "cuadricula", "cuadrícula": return .cuadricula
        default: return cuantos > 0 && cuantos <= maximoAbanico ? .abanico : .cuadricula
        }
    }

    /// Un elemento del abanico: el desvío a la derecha (curva de la pila) y el giro en grados. El 0 es el de más abajo (el más reciente).
    public static func abanico(indice i: Int, de n: Int) -> (desvio: Double, giro: Double) {
        guard n > 1 else { return (0, 0) }
        let t = Double(i) / Double(max(1, n - 1))
        return (desvio: (t * t * 44).rounded(), giro: -(t * 7).rounded() / 1)
    }
}

// MARK: - Navegar con flechas

public enum NavegacionPanel {
    public enum Paso: Sendable { case izquierda, derecha, arriba, abajo }

    /// El elemento que sigue. En cuadrícula `columnas` por fila y la primera fila queda arriba; en el abanico (columnas = 1) el
    /// índice 0 está abajo, así que "arriba" sube al siguiente. Sin selección, entra por el primero. Nunca se sale de la lista.
    public static func mover(_ actual: Int?, paso: Paso, total: Int, columnas: Int, abanico: Bool = false) -> Int? {
        guard total > 0 else { return nil }
        guard let a = actual, (0..<total).contains(a) else { return 0 }
        let c = max(1, columnas)
        var d = 0
        switch paso {
        case .izquierda: d = abanico ? 0 : -1
        case .derecha: d = abanico ? 0 : 1
        case .arriba: d = abanico ? 1 : -c
        case .abajo: d = abanico ? -1 : c
        }
        let n = a + d
        return (0..<total).contains(n) ? n : a
    }
}

// MARK: - Carpetas abiertas en el Finder

public enum FinderAbiertas {
    /// Las rutas de carpeta a partir de lo que dicen las ventanas (`AXDocument`: "file:///Users/ana/Docs/"): sin repetir, solo
    /// carpetas que existen (`esCarpeta`), sin la raíz ni la carpeta personal (siempre están a mano) ni las que ya están fijas.
    public static func rutas(documentos: [String], fijas: Set<String> = [], home: String = NSHomeDirectory(), esCarpeta: (String) -> Bool) -> [String] {
        var vistas = Set<String>()
        var salida: [String] = []
        for d in documentos {
            guard let u = URL(string: d), u.isFileURL else { continue }
            var r = u.path
            while r.count > 1, r.hasSuffix("/") { r.removeLast() }
            guard r != "/", r != home, !fijas.contains(r), esCarpeta(r), vistas.insert(r).inserted else { continue }
            salida.append(r)
        }
        return salida
    }
}

// MARK: - El reloj de tarjetas

public enum RelojTarjetas {
    /// La hora (1–12, sin cero a la izquierda), los minutos (dos cifras) y AM/PM.
    public static func partes(hora24: Int, minuto: Int) -> (hora: String, minuto: String, periodo: String) {
        let h = hora24 % 12 == 0 ? 12 : hora24 % 12
        return (String(h), String(format: "%02d", minuto), hora24 < 12 ? "AM" : "PM")
    }
}
