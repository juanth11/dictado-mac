import Foundation

// Selector de apps que reemplaza ⌘Tab: aquí solo vive lo puro (qué teclas cuentan, a dónde va la selección, el orden de uso, la
// disposición de la rejilla y qué parte de la lista se ve). Lo que toca el sistema (el tap de teclado, el panel, Accesibilidad,
// AppleScript) está en la app: Sources/Dictado/SelectorApps.swift.

// MARK: - Teclas

/// Las teclas que el selector entiende mientras ⌘ sigue apretado.
public enum TeclaSelector: Equatable, Sendable {
    case tab(atras: Bool)
    /// La tecla de arriba de Tab (` en un teclado US): cicla ventanas de la app, como ⌘` del sistema.
    case acento(atras: Bool)
    case arriba, abajo, izquierda, derecha
}

/// Lo que el tap le avisa al selector.
public enum EntradaSelector: Equatable, Sendable {
    case iniciar(atras: Bool)
    case tecla(TeclaSelector)
    case cancelar
    /// Return con ⌘ apretado: ir ya a lo elegido.
    case confirmar
    /// Se soltó ⌘: ir a lo elegido.
    case soltarCmd
}

public struct ModsSelector: OptionSet, Sendable {
    public let rawValue: Int
    public init(rawValue: Int) { self.rawValue = rawValue }
    public static let cmd = ModsSelector(rawValue: 1)
    public static let shift = ModsSelector(rawValue: 2)
    public static let opcion = ModsSelector(rawValue: 4)
    public static let control = ModsSelector(rawValue: 8)
}

/// Decide, tecla a tecla, qué se consume y qué pasa. Corre en el hilo del tap: sin memoria dinámica pesada ni llamadas al sistema.
/// Regla de oro: fuera del selector solo se consume ⌘Tab y ⌘⇧Tab (sin ⌥ ni ⌃, que son de otros atajos, p. ej. hyper).
public struct ClasificadorSelector: Sendable {
    public static let codigoTab = 48
    public static let codigoAcento = 50
    public static let codigoEsc = 53
    public static let codigoReturn = 36
    public static let codigoReturnNumerico = 76
    public static let codigoIzquierda = 123
    public static let codigoDerecha = 124
    public static let codigoAbajo = 125
    public static let codigoArriba = 126

    /// Verdadero desde ⌘Tab hasta que se suelta ⌘ (o Esc, o Return).
    public private(set) var activo = false
    private var consumidas: Set<Int> = []

    public init() {}

    public mutating func teclaAbajo(codigo: Int, mods: ModsSelector) -> (consumir: Bool, entrada: EntradaSelector?) {
        if !activo {
            guard codigo == Self.codigoTab, mods.contains(.cmd), !mods.contains(.opcion), !mods.contains(.control) else { return (false, nil) }
            activo = true
            consumidas.insert(codigo)
            return (true, .iniciar(atras: mods.contains(.shift)))
        }
        // Activo pero ⌘ ya no está: se perdió el aviso de soltarlo. Se cierra y la tecla pasa tal cual.
        guard mods.contains(.cmd) else {
            activo = false
            consumidas.removeAll()
            return (false, .soltarCmd)
        }
        consumidas.insert(codigo)
        let atras = mods.contains(.shift)
        switch codigo {
        case Self.codigoTab: return (true, .tecla(.tab(atras: atras)))
        case Self.codigoAcento: return (true, .tecla(.acento(atras: atras)))
        case Self.codigoIzquierda: return (true, .tecla(.izquierda))
        case Self.codigoDerecha: return (true, .tecla(.derecha))
        case Self.codigoAbajo: return (true, .tecla(.abajo))
        case Self.codigoArriba: return (true, .tecla(.arriba))
        case Self.codigoEsc:
            activo = false
            return (true, .cancelar)
        case Self.codigoReturn, Self.codigoReturnNumerico:
            activo = false
            return (true, .confirmar)
        default: return (true, nil)   // mientras el selector está abierto, ninguna otra tecla llega a la app de atrás
        }
    }

    /// Soltar una tecla que se consumió al bajar también se consume.
    public mutating func teclaArriba(codigo: Int) -> Bool {
        consumidas.remove(codigo) != nil
    }

    /// Cambió algún modificador. Nunca se consume. Devuelve `.soltarCmd` si ⌘ ya no está apretado.
    public mutating func modificadores(_ mods: ModsSelector) -> EntradaSelector? {
        guard activo, !mods.contains(.cmd) else { return nil }
        activo = false
        return .soltarCmd
    }

    /// Cierra por fuera (el panel ya eligió con el ratón, o el tap se apagó): nada más se consume.
    public mutating func terminar() {
        activo = false
    }

    /// Devuelve si estaba activo (el tap se apagó y hay que cancelar).
    public mutating func reiniciar() -> Bool {
        let estaba = activo
        activo = false
        consumidas.removeAll()
        return estaba
    }
}

// MARK: - La selección

public enum ResultadoSoltar: Equatable, Sendable {
    case nada
    /// `elemento` es nil si se eligió la app sola; `conPanel` es falso en el toque rápido (el panel nunca salió).
    case confirmar(app: Int, elemento: Int?, conPanel: Bool)
}

/// A dónde apunta el selector: una app de la fila o un elemento (ventana o pestaña) de su lista. Los totales los pone quien lee el
/// sistema, que sabe cuántas apps y cuántos elementos hay; la máquina solo se mueve dentro de ellos.
public struct MaquinaSelector: Equatable, Sendable {
    public enum Fase: Equatable, Sendable { case reposo, esperando, visible }

    /// Antes de este tiempo (segundos) soltar ⌘ es un toque rápido: va a la app anterior sin mostrar el panel.
    public static let retrasoPanel = 0.15

    public private(set) var fase = Fase.reposo
    public private(set) var app = 0
    /// nil = la selección está en la fila de apps.
    public private(set) var elemento: Int?
    public var totalApps = 0
    public var totalElementos = 0
    /// Dónde cae la selección al bajar a la lista (la pestaña activa de la ventana de adelante).
    public var elementoInicial = 0

    public init() {}

    /// ⌘Tab: la app de adelante es la 0, así que se salta a la 1. ⌘⇧Tab empieza por la última.
    public mutating func iniciar(atras: Bool, totalApps total: Int) {
        totalApps = max(0, total)
        totalElementos = 0
        elementoInicial = 0
        elemento = nil
        app = total <= 1 ? 0 : (atras ? total - 1 : 1)
        fase = total == 0 ? .reposo : .esperando
    }

    /// Pasó `retrasoPanel` con ⌘ apretado (o hubo otra tecla): sale el panel.
    public mutating func mostrar() {
        if fase == .esperando { fase = .visible }
    }

    /// Mueve la selección. Devuelve true si cambió de app (la lista de elementos es otra).
    @discardableResult
    public mutating func tecla(_ t: TeclaSelector) -> Bool {
        guard fase != .reposo else { return false }
        mostrar()
        switch t {
        case .tab(let atras): return mover(atras ? -1 : 1)
        case .derecha: return mover(1)
        case .izquierda: return mover(-1)
        case .abajo:
            guard totalElementos > 0 else { return false }
            if let e = elemento { elemento = min(e + 1, totalElementos - 1) }
            else { elemento = min(max(elementoInicial, 0), totalElementos - 1) }
        case .arriba:
            guard let e = elemento else { return false }
            elemento = e == 0 ? nil : e - 1
        case .acento(let atras):
            guard totalElementos > 0 else { return false }
            if let e = elemento {
                elemento = ((e + (atras ? -1 : 1)) % totalElementos + totalElementos) % totalElementos
            } else if atras {
                elemento = totalElementos - 1
            } else {
                // La app de adelante ya está en su primera ventana: se empieza por la siguiente.
                elemento = min(app == 0 ? 1 : 0, totalElementos - 1)
            }
        }
        return false
    }

    private mutating func mover(_ paso: Int) -> Bool {
        guard totalApps > 1 else { return false }
        app = ((app + paso) % totalApps + totalApps) % totalApps
        elemento = nil
        totalElementos = 0
        elementoInicial = 0
        return true
    }

    /// ⌘ se soltó (o Return): a dónde ir.
    public mutating func soltar() -> ResultadoSoltar {
        defer { fase = .reposo; elemento = nil }
        guard fase != .reposo, totalApps > 0 else { return .nada }
        return .confirmar(app: app, elemento: elemento, conPanel: fase == .visible)
    }

    public mutating func cancelar() {
        fase = .reposo
        elemento = nil
    }

    /// Los elementos de la app seleccionada cambiaron (llegaron las pestañas): la selección no se pasa del final.
    public mutating func ajustarElementos(total: Int, inicial: Int) {
        totalElementos = max(0, total)
        elementoInicial = inicial
        if let e = elemento { elemento = total == 0 ? nil : min(e, total - 1) }
    }
}

// MARK: - Orden de uso

/// Las apps en el orden en que las usaste, la de ahora primero (como el ⌘Tab de siempre).
public enum OrdenUso {
    /// Pone `id` al frente de la lista de uso, sin repetirlo ni pasarse de `limite`.
    public static func registrar<ID: Hashable>(_ id: ID, en lista: [ID], limite: Int = 64) -> [ID] {
        var nueva = lista.filter { $0 != id }
        nueva.insert(id, at: 0)
        return Array(nueva.prefix(limite))
    }

    /// Las apps vivas: primero las que están en la lista de uso (en ese orden) y luego las demás como vinieron.
    public static func ordenar<ID: Hashable>(vivos: [ID], uso: [ID]) -> [ID] {
        let presentes = Set(vivos)
        var vistos = Set<ID>()
        var resultado: [ID] = []
        for id in uso where presentes.contains(id) && vistos.insert(id).inserted { resultado.append(id) }
        for id in vivos where vistos.insert(id).inserted { resultado.append(id) }
        return resultado
    }
}

// MARK: - Disposición

public enum DisposicionSelector {
    /// Lado de la celda de un icono y aire entre celdas (rejilla de 4).
    public static let celda = 80.0
    public static let hueco = 8.0
    public static let relleno = 20.0

    /// Cuántas columnas caben en el 84 % del ancho de la pantalla y, si las apps no caben en una fila, las reparte parejo.
    public static func columnas(total: Int, anchoPantalla: Double) -> Int {
        guard total > 0 else { return 1 }
        let util = anchoPantalla * 0.84 - 2 * relleno
        let maxima = max(3, min(12, Int((util + hueco) / (celda + hueco))))
        if total <= maxima { return total }
        let filas = (total + maxima - 1) / maxima
        return (total + filas - 1) / filas
    }

    /// Rangos de índices de cada fila.
    public static func filas(total: Int, columnas: Int) -> [Range<Int>] {
        guard total > 0, columnas > 0 else { return [] }
        return stride(from: 0, to: total, by: columnas).map { $0..<min($0 + columnas, total) }
    }

    /// Ancho del contenido de la fila más ancha.
    public static func anchoFila(columnas: Int) -> Double {
        Double(columnas) * celda + Double(max(0, columnas - 1)) * hueco
    }
}

// MARK: - Ventanas y pestañas como una sola lista

public enum ElementoDetalle: Equatable, Sendable {
    case ventana(Int)
    case pestana(ventana: Int, indice: Int)

    public var indiceVentana: Int {
        switch self {
        case .ventana(let v): return v
        case .pestana(let v, _): return v
        }
    }
}

/// Lo que importa de una ventana para armar la lista: cuántas pestañas tiene y cuál es la activa.
public struct ResumenVentana: Equatable, Sendable {
    public var pestanas: Int
    public var activa: Int?
    public init(pestanas: Int, activa: Int? = nil) {
        self.pestanas = pestanas
        self.activa = activa
    }
}

public enum ListaDetalle {
    /// Cada ventana seguida de sus pestañas, en orden. ↓/↑ recorren esta lista.
    public static func aplanar(_ ventanas: [ResumenVentana]) -> [ElementoDetalle] {
        var lista: [ElementoDetalle] = []
        for (v, w) in ventanas.enumerated() {
            lista.append(.ventana(v))
            for p in 0..<max(0, w.pestanas) { lista.append(.pestana(ventana: v, indice: p)) }
        }
        return lista
    }

    /// Dónde cae la selección al bajar: la pestaña activa de la ventana de adelante; si no hay, su ventana.
    public static func inicial(_ ventanas: [ResumenVentana]) -> Int {
        guard let primera = ventanas.first, let activa = primera.activa, activa >= 0, activa < primera.pestanas else { return 0 }
        return 1 + activa
    }

    /// Qué elementos se ven si solo caben `maximo` puntos de alto: la selección siempre queda a la vista. Empieza por arriba si todo
    /// cabe o no hay selección.
    public static func visibles(alturas: [Double], hueco: Double, seleccion: Int?, maximo: Double) -> Range<Int> {
        guard !alturas.isEmpty else { return 0..<0 }
        func fin(desde inicio: Int) -> Int {
            var usado = 0.0
            var i = inicio
            while i < alturas.count {
                let suma = usado + alturas[i] + (i > inicio ? hueco : 0)
                if suma > maximo && i > inicio { break }
                usado = suma
                i += 1
            }
            return i
        }
        var inicio = 0
        if let s = seleccion, s >= 0, s < alturas.count {
            while fin(desde: inicio) <= s && inicio < s { inicio += 1 }
        }
        return inicio..<fin(desde: inicio)
    }
}

// MARK: - Icono genérico de pestaña

/// Sin favicon (la lista de pestañas no lo trae y no se consulta la red), cada pestaña lleva la inicial de su sitio sobre un tono
/// que sale del dominio: el mismo sitio siempre se ve igual.
public enum EtiquetaPestana {
    public static let tonos = 6

    public static func dominio(de url: String) -> String {
        guard let host = URL(string: url)?.host?.lowercased(), !host.isEmpty else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    public static func inicial(titulo: String, url: String) -> String {
        let fuente = dominio(de: url).isEmpty ? titulo : dominio(de: url)
        guard let c = fuente.first(where: { $0.isLetter || $0.isNumber }) else { return "" }
        return String(c).uppercased()
    }

    /// 0..<tonos, estable entre ejecuciones (no usa `hashValue`, que cambia en cada arranque).
    public static func tono(de dominio: String) -> Int {
        var h: UInt32 = 5381
        for u in dominio.unicodeScalars { h = h &* 33 &+ u.value }
        return Int(h % UInt32(tonos))
    }
}
