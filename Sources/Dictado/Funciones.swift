import AppKit
import DictadoKit

/// Funciones opcionales de Dictado. Cada una vive en su propio archivo, se prende o apaga desde el menú
/// "Funciones" y está documentada en docs/FUNCIONES.md (qué hace, qué archivos toca, qué permiso usa y cómo
/// quitarla del todo).
enum Funcion: String, CaseIterable {
    case hyper, ventanas, buscador, pulido, acciones, icloud, lanzador, velo, teclas, dock, selector

    var titulo: String {
        switch self {
        case .hyper: return "Tecla hyper (Bloq Mayús)"
        case .ventanas: return "Ventanas por teclado"
        case .buscador: return "Buscador de ventanas"
        case .pulido: return "Dictado pulido con IA local"
        case .acciones: return "Acciones sobre texto seleccionado"
        case .icloud: return "Quitar descargas de iCloud (limpieza)"
        case .lanzador: return "Lanzador de apps (Aurora)"
        case .velo: return "Velo (desenfoca lo que no usas)"
        case .teclas: return "Teclas con sonido"
        case .dock: return "Dock propio (Aurora)"
        case .selector: return "Selector de apps con ventanas y pestañas"
        }
    }

    var detalle: String {
        switch self {
        case .hyper: return "Mantén Bloq Mayús + otra tecla = ⌃⌥⌘⇧ para atajos que no chocan con nada; sola sigue siendo Bloq Mayús"
        case .ventanas: return "Hyper + flechas: mitades, tercios, casi maximizar, otra pantalla, restaurar; en un monitor vertical, arriba y abajo; Hyper + D junta dos ventanas"
        case .buscador: return "Hyper + Espacio: busca una ventana por su título y salta a ella"
        case .pulido: return "Limpia muletillas y puntuación del dictado según la app (todo en el Mac)"
        case .acciones: return "Hyper + T: traducir, corregir, resumir o mandar a Claude el texto seleccionado"
        case .icloud: return "En Limpieza, libera archivos grandes que ya están en iCloud (siguen en la nube)"
        case .lanzador: return "Hyper + L, la esquina inferior derecha o la pieza del Dock: pantalla completa con tus apps (fijadas, carpetas y más usadas), el fondo de tu Mac, un buscador que también calcula y widgets de fecha, clima, música, agenda y agentes"
        case .velo: return "Hyper + B: desenfoca todo menos la ventana activa; también con una sacudida del ratón. Hyper + G cambia de modo, Hyper + J (mantenida) lo levanta un momento"
        case .teclas: return "Sonido de interruptor mecánico en cada tecla (sintetizado en el Mac), con perfiles, estéreo según la tecla y volumen propio. Hyper + K lo apaga"
        case .dock: return "Una barra abajo con la hora, la agenda, los agentes, tus apps y carpetas, y un selector de espacios. Aparece al tocar el borde de abajo; Hyper + O la muestra o la esconde. Convive con el Dock del sistema"
        case .selector: return "⌘Tab abre un selector de vidrio con tus apps (la usada más reciente primero) y, debajo de la elegida, sus ventanas y las pestañas de Cra, Chrome, Arc, Safari y compañía; ↓ y ↑ las recorren, ` cicla las ventanas, soltar ⌘ salta. Un toque rápido cambia a la app anterior. Necesita Accesibilidad; sin ella sigue el ⌘Tab del sistema"
        }
    }

    /// Lo que vale mientras no la hayas tocado en el menú: las clásicas y el lanzador (su fuga de memoria ya se resolvió: la prueba
    /// `--probar-lanzador-memoria` lo mide) vienen prendidos. Apagadas: el velo, las teclas y el Dock.
    var porOmision: Bool { self != .velo && self != .teclas && self != .dock }

    var activa: Bool {
        UserDefaults.dictado.object(forKey: "funcion." + rawValue) as? Bool ?? porOmision
    }

    func poner(_ si: Bool) {
        UserDefaults.dictado.set(si, forKey: "funcion." + rawValue)
        NotificationCenter.default.post(name: .funcionesCambiaron, object: nil, userInfo: ["funcion": rawValue])
    }
}

extension Notification.Name {
    /// Se publica cuando prendes o apagas una función en el menú; userInfo["funcion"] = rawValue.
    static let funcionesCambiaron = Notification.Name("dictado.funcionesCambiaron")
    /// Empieza o termina un bloque de foco; userInfo["activo"] = Bool.
    static let focoCambio = Notification.Name("dictado.focoCambio")
}

/// Lo que un módulo puede usar de la app sin depender de sus detalles internos.
@MainActor
struct ContextoModulos {
    /// Aviso corto en la isla (o en el indicador si no hay isla): texto, símbolo SF, nota opcional.
    let avisar: (String, String, String?) -> Void
    /// Guarda una idea en la carpeta de ideas (como ⌥⇧Espacio).
    let guardarIdea: (String) -> Void
    let abrirPortapapeles: () -> Void
    let abrirCaptura: () -> Void
    let abrirSalud: () -> Void
    /// Abre el centro de mando; si ya está abierto, lo cierra.
    let alternarCentro: () -> Void
    /// Abre el lanzador de apps (Aurora); si ya está abierto, lo cierra.
    let alternarLanzador: () -> Void
    /// Empieza un bloque de foco con la siguiente prioridad del brief; si hay uno, muestra cómo va.
    let alternarFoco: () -> Void
    /// Abre el enlace de la reunión en curso o la próxima (Meet, Zoom, Teams).
    let unirseAProxima: () -> Void
    /// Graba la reunión en curso (o la termina si ya estás grabando).
    let alternarNotas: () -> Void
    /// El módulo de pulido registra aquí su transformación: recibe el texto dictado y devuelve el final.
    let registrarPulido: (@escaping @MainActor (String) async -> String) -> Void
    /// Pausa (true) o reanuda (false) el historial del portapapeles mientras un módulo lo usa de paso
    /// (copiar una selección con ⌘C simulado, pegar un resultado y devolver lo que había).
    let pausarHistorial: (Bool) -> Void
    /// ¿Estás dictando o grabando una reunión? (Teclas se calla mientras tanto.)
    let dictando: () -> Bool
    /// Hyper + número, Hyper + ] y Hyper + [: cambia de espacio (ver `Espacios.swift`).
    var cambiarEspacio: (DestinoEspacio) -> Void = { _ in }
}
