import AppKit
import ApplicationServices
import Carbon.HIToolbox
import DictadoKit

// Ventanas por teclado: solo lo que macOS 26 no trae de serie (su mosaico ya hace mitades y cuartos con fn⌃).
//   Hyper + ←/→   mitad → tercio → dos tercios del lado, en ciclo al repetir
//   Hyper + ↑     casi maximizar (margen pequeño); otra vez, vuelve al tamaño previo
//   Hyper + ↓     restaurar el tamaño previo
//   Hyper + N     a la siguiente pantalla, con las mismas proporciones (girada si cambia de orientación)
//   Hyper + ↩     centrar
// En una pantalla vertical (un monitor girado) las mitades van arriba y abajo, y una mitad de lado quedaría angosta:
//   Hyper + ↑/↓   mitad → tercio → dos tercios, arriba o abajo y a todo el ancho
//   Hyper + ←/→   a la pantalla de ese lado (a la mitad que da hacia la vertical, si es horizontal)
//   Hyper + ↩     casi maximizar; otra vez, vuelve al tamaño previo
// Y en cualquier pantalla:
//   Hyper + D     la ventana al frente y la que usaste antes, juntas en la pantalla de la del frente: arriba y abajo
//                 en una vertical, lado a lado en una horizontal. Al repetir, el reparto pasa de ⅔ + ⅓ a ½ + ½ y a ⅓ + ⅔
// La geometría vive en `GeometriaVentanas` (funciones puras, se prueban con --probar-ventanas); aquí solo se lee
// y se escribe la ventana por Accesibilidad.

/// Interruptor del módulo: registra los atajos según `Funcion.ventanas` y mueve la ventana enfocada.
@MainActor
final class VentanasTeclado {
    /// Lo que se recuerda de una ventana: su marco antes de que Dictado la tocara y lo último que le hizo.
    private struct Recuerdo {
        let ventana: AXUIElement
        var memoria: MemoriaVentana
    }

    /// La última disposición (Hyper + D): si al repetir siguen igual, se pasa al siguiente reparto.
    private struct Disposicion {
        let frente: AXUIElement
        let otra: AXUIElement
        var marco: CGRect
        var paso: Int
    }

    private let contexto: ContextoModulos
    private var recuerdos: [Recuerdo] = []
    private var disposicion: Disposicion?
    private var registrados = false
    /// Ids de Carbon reservados para este módulo: 30-39.
    private static let atajos: [(id: UInt32, tecla: Int, accion: AccionVentana)] = [
        (30, kVK_LeftArrow, .izquierda), (31, kVK_RightArrow, .derecha), (32, kVK_UpArrow, .casiMaximizar),
        (33, kVK_DownArrow, .restaurar), (34, kVK_ANSI_N, .otraPantalla), (35, kVK_Return, .centrar),
        (36, kVK_ANSI_D, .disponer),
    ]

    init(_ contexto: ContextoModulos) {
        self.contexto = contexto
        NotificationCenter.default.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.ventanas.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        }
        sincronizar()
    }

    private func sincronizar() {
        if Funcion.ventanas.activa {
            guard !registrados else { return }
            registrados = true
            let hyper = cmdKey | optionKey | controlKey | shiftKey
            let ocupados = Self.atajos.filter { a in
                !Atajos.shared.registrar(id: a.id, tecla: a.tecla, modificadores: hyper,
                                         alPresionar: { [weak self] in a.accion == .disponer ? self?.disponer() : self?.ejecutar(a.accion) })
            }
            if !ocupados.isEmpty {
                contexto.avisar("Algunos atajos de ventanas los usa otra app", "keyboard.badge.exclamationmark", nil)
            }
        } else {
            guard registrados else { return }
            registrados = false
            Self.atajos.forEach { Atajos.shared.quitar(id: $0.id) }
            recuerdos = []
            disposicion = nil
        }
    }

    func ejecutar(_ accion: AccionVentana) {
        guard AXIsProcessTrusted() else {
            contexto.avisar("Activa Accesibilidad para mover ventanas", "lock", nil)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let appAX = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appAX, 0.3)  // una app colgada no traba el atajo
        guard let ventana = AX.elemento(appAX, kAXFocusedWindowAttribute) ?? AX.elemento(appAX, kAXMainWindowAttribute) else {
            contexto.avisar("No hay una ventana que mover", "macwindow", nil)
            return
        }
        AXUIElementSetMessagingTimeout(ventana, 0.3)
        if AX.bool(ventana, "AXFullScreen") == true {
            contexto.avisar("La ventana está en pantalla completa", "arrow.down.right.and.arrow.up.left", nil)
            return
        }
        guard let actual = AX.marco(ventana) else { return }
        let memoria = recuerdos.first { CFEqual($0.ventana, ventana) }?.memoria
        let pantallas = GeometriaVentanas.pantallas(NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        guard let plan = GeometriaVentanas.plan(accion, actual: actual, pantallas: pantallas, memoria: memoria) else {
            if GeometriaVentanas.enVertical(actual, pantallas: pantallas), accion == .izquierda || accion == .derecha {
                contexto.avisar("No hay otra pantalla a ese lado", "rectangle.portrait.arrowtriangle.2.outward", nil)
            } else if accion == .restaurar, memoria == nil {
                // Con memoria y sin plan, la ventana ya está en su tamaño previo: no hace falta avisar.
                contexto.avisar("No hay un tamaño previo que restaurar", "arrow.uturn.backward", nil)
            }
            return
        }
        acomodar(ventana, de: appAX, a: plan.marco, antes: actual, registro: plan.registro, paso: plan.paso)
    }

    /// Mueve la ventana y recuerda lo que le hizo (el previo para volver, y el paso del ciclo).
    @discardableResult
    private func acomodar(_ ventana: AXUIElement, de app: AXUIElement, a marco: CGRect, antes: CGRect,
                          registro: AccionVentana, paso: Int) -> CGRect {
        let indice = recuerdos.firstIndex { CFEqual($0.ventana, ventana) }
        let memoria = indice.map { recuerdos[$0].memoria }
        AX.mover(ventana, a: marco, app: app)
        let leido = AX.marco(ventana) ?? marco  // la app puede ajustar el tamaño (mínimos, celdas de texto)
        let nueva = GeometriaVentanas.recordar(memoria, accion: registro, antes: antes, leido: leido, paso: paso)
        if let indice { recuerdos.remove(at: indice) }
        recuerdos.insert(Recuerdo(ventana: ventana, memoria: nueva), at: 0)
        if recuerdos.count > 40 { recuerdos.removeLast() }  // las ventanas cerradas se olvidan solas
        return leido
    }

    /// Hyper + D: la ventana al frente y la anterior, juntas en la pantalla de la del frente.
    func disponer() {
        guard AXIsProcessTrusted() else {
            contexto.avisar("Activa Accesibilidad para mover ventanas", "lock", nil)
            return
        }
        guard let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != getpid() else { return }
        let appAX = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(appAX, 0.3)
        guard let frente = AX.elemento(appAX, kAXFocusedWindowAttribute) ?? AX.elemento(appAX, kAXMainWindowAttribute),
              let marcoFrente = AX.marco(frente) else {
            contexto.avisar("No hay una ventana que acomodar", "macwindow", nil)
            return
        }
        // ¿Repites sobre la misma pareja tal como quedó? Siguiente reparto. Si no, la ventana que usaste antes.
        var paso = 0
        var otra: (ventana: AXUIElement, app: AXUIElement, marco: CGRect)?
        if let d = disposicion, CFEqual(d.frente, frente), GeometriaVentanas.parecidos(marcoFrente, d.marco),
           let marcoOtra = AX.marco(d.otra) {
            var pid: pid_t = 0
            AXUIElementGetPid(d.otra, &pid)
            otra = (d.otra, AXUIElementCreateApplication(pid), marcoOtra)
            paso = d.paso + 1
        } else {
            otra = Self.anterior(a: marcoFrente, pidFrente: app.processIdentifier)
        }
        guard let otra else {
            contexto.avisar("No hay otra ventana para acomodar al lado", "rectangle.split.1x2", nil)
            return
        }
        let pantallas = GeometriaVentanas.pantallas(NSScreen.screens.map { ($0.frame, $0.visibleFrame) })
        guard let i = GeometriaVentanas.indice(de: marcoFrente, en: pantallas) else { return }
        let reparto = GeometriaVentanas.disposicion(paso: paso, en: pantallas[i].visible)
        let quedo = acomodar(frente, de: appAX, a: reparto.frente, antes: marcoFrente, registro: .disponer, paso: paso)
        AXUIElementSetMessagingTimeout(otra.ventana, 0.3)
        acomodar(otra.ventana, de: otra.app, a: reparto.otra, antes: otra.marco, registro: .disponer, paso: paso)
        disposicion = Disposicion(frente: frente, otra: otra.ventana, marco: quedo, paso: paso)
    }

    /// La ventana que usaste antes de la del frente: la siguiente en el orden de pantalla (de adelante hacia atrás),
    /// de una app normal y de tamaño de ventana (no menús, avisos ni la isla).
    private static func anterior(a marcoFrente: CGRect, pidFrente: pid_t) -> (ventana: AXUIElement, app: AXUIElement, marco: CGRect)? {
        let lista = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        for w in lista {
            guard (w[kCGWindowLayer as String] as? Int) == 0, (w[kCGWindowAlpha as String] as? Double ?? 1) > 0,
                  let pid = w[kCGWindowOwnerPID as String] as? pid_t, pid != getpid(),
                  let b = w[kCGWindowBounds as String] as? [String: CGFloat] else { continue }
            let marco = CGRect(x: b["X"] ?? 0, y: b["Y"] ?? 0, width: b["Width"] ?? 0, height: b["Height"] ?? 0)
            guard marco.width >= 200, marco.height >= 120 else { continue }
            if pid == pidFrente && GeometriaVentanas.parecidos(marco, marcoFrente) { continue }   // la del frente
            guard NSRunningApplication(processIdentifier: pid)?.activationPolicy == .regular else { continue }
            let appAX = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(appAX, 0.3)
            let ventanas = AX.valor(appAX, kAXWindowsAttribute) as? [AXUIElement] ?? []
            if let v = ventanas.first(where: { AX.marco($0).map { GeometriaVentanas.parecidos($0, marco) } ?? false }) {
                return (v, appAX, marco)
            }
        }
        return nil
    }
}

// MARK: - Geometría (pura)

// MARK: - Accesibilidad

/// Lectura y escritura de ventanas por Accesibilidad (la usan Ventanas y el Buscador).
enum AX {
    static func valor(_ e: AXUIElement, _ atributo: String) -> CFTypeRef? {
        var v: CFTypeRef?
        return AXUIElementCopyAttributeValue(e, atributo as CFString, &v) == .success ? v : nil
    }

    static func elemento(_ e: AXUIElement, _ atributo: String) -> AXUIElement? {
        guard let v = valor(e, atributo), CFGetTypeID(v) == AXUIElementGetTypeID() else { return nil }
        return (v as! AXUIElement)
    }

    static func bool(_ e: AXUIElement, _ atributo: String) -> Bool? {
        valor(e, atributo) as? Bool
    }

    static func marco(_ e: AXUIElement) -> CGRect? {
        guard let p = valor(e, kAXPositionAttribute), let t = valor(e, kAXSizeAttribute),
              CFGetTypeID(p) == AXValueGetTypeID(), CFGetTypeID(t) == AXValueGetTypeID() else { return nil }
        var origen = CGPoint.zero, tamano = CGSize.zero
        guard AXValueGetValue(p as! AXValue, .cgPoint, &origen), AXValueGetValue(t as! AXValue, .cgSize, &tamano) else { return nil }
        return CGRect(origin: origen, size: tamano)
    }

    static func modificable(_ e: AXUIElement, _ atributo: String) -> Bool {
        var si: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(e, atributo as CFString, &si) == .success && si.boolValue
    }

    /// Tamaño → posición → tamaño: el primer tamaño evita que la app lo recorte al llegar a una pantalla más
    /// chica; el último corrige lo que la app ajustó al moverse. En Chromium/Electron, `AXEnhancedUserInterface`
    /// prendido hace que cada cambio sea lento y animado: se apaga mientras tanto y se deja como estaba.
    static func mover(_ ventana: AXUIElement, a marco: CGRect, app: AXUIElement) {
        let mejorada = bool(app, "AXEnhancedUserInterface") == true
        if mejorada { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanFalse) }
        defer { if mejorada { AXUIElementSetAttributeValue(app, "AXEnhancedUserInterface" as CFString, kCFBooleanTrue) } }
        var origen = marco.origin, tamano = marco.size
        guard let posicion = AXValueCreate(.cgPoint, &origen), let medida = AXValueCreate(.cgSize, &tamano) else { return }
        let redimensionable = modificable(ventana, kAXSizeAttribute)
        if redimensionable { AXUIElementSetAttributeValue(ventana, kAXSizeAttribute as CFString, medida) }
        AXUIElementSetAttributeValue(ventana, kAXPositionAttribute as CFString, posicion)
        if redimensionable { AXUIElementSetAttributeValue(ventana, kAXSizeAttribute as CFString, medida) }
    }
}
