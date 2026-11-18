import AppKit
import DictadoKit

// La esquina activa del lanzador: el puntero se queda ~0,3 s en una esquina de la pantalla y el lanzador se abre (o se cierra).
// Reemplaza a la vista Apps del sistema.
//
// Sin vigilar el puntero en bucle: en cada esquina elegida hay un cuadrito transparente de 4 pt (como la franja del borde del Dock) cuya
// zona de seguimiento avisa al entrar y al salir; solo entonces corre un cronómetro de 0,3 s. La espera es lógica pura
// (`PoliticaEsquina`, con pruebas): no dispara con un botón apretado ni en un arrastre, y una vez disparada no vuelve a hacerlo hasta que
// el puntero salga de la esquina.
//
// Ajuste (defaults write app.dictado …):
//   lanzador.esquina   ninguna | inferiorDerecha | inferiorIzquierda | superiorDerecha | superiorIzquierda   (inferiorDerecha por omisión)
// Solo existe con la función "Lanzador de apps" encendida. Con la esquina en `ninguna` no hay ninguna ventana.

extension Ajustes {
    static var esquinaLanzador: EsquinaLanzador { EsquinaLanzador(ajuste: UserDefaults.dictado.string(forKey: "lanzador.esquina")) }
}

@MainActor
final class EsquinasLanzador {
    @MainActor private final class Cara {
        let id: CGDirectDisplayID
        var panel: NSPanel?
        var sensor: SensorDock?
        var politica = PoliticaEsquina()
        var espera: DispatchWorkItem?
        init(id: CGDirectDisplayID) { self.id = id }
    }

    private let contexto: ContextoModulos
    private var caras: [CGDirectDisplayID: Cara] = [:]
    private var esquina = EsquinaLanzador.ninguna
    private var firma = ""
    private var observadores: [NSObjectProtocol] = []

    init(_ contexto: ContextoModulos) {
        self.contexto = contexto
        let centro = NotificationCenter.default
        observadores.append(centro.addObserver(forName: .funcionesCambiaron, object: nil, queue: .main) { [weak self] nota in
            guard (nota.userInfo?["funcion"] as? String) == Funcion.lanzador.rawValue else { return }
            MainActor.assumeIsolated { self?.sincronizar() }
        })
        observadores.append(centro.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sincronizar() }
        })
        // `defaults write app.dictado lanzador.esquina …` vale al momento (solo se hace algo si cambió de verdad).
        observadores.append(centro.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.sincronizar() }
        })
        sincronizar()
    }

    private func idDe(_ p: NSScreen) -> CGDirectDisplayID? { p.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID }

    private func sincronizar() {
        let e = Funcion.lanzador.activa ? Ajustes.esquinaLanzador : .ninguna
        let nueva = e.rawValue + NSScreen.screens.map { NSStringFromRect($0.frame) }.joined()
        guard nueva != firma else { return }
        firma = nueva
        esquina = e
        guard e != .ninguna else { return soltarTodo() }
        var vivas = Set<CGDirectDisplayID>()
        for p in NSScreen.screens {
            guard let id = idDe(p), let m = e.marco(x: p.frame.minX, y: p.frame.minY, ancho: p.frame.width, alto: p.frame.height,
                                                    lado: AuroraLanzador.ladoEsquina) else { continue }
            vivas.insert(id)
            let cara = caras[id] ?? Cara(id: id)
            caras[id] = cara
            if cara.panel == nil { crear(cara) }
            cara.politica.sale()
            cara.panel?.setFrame(NSRect(x: m.x, y: m.y, width: m.lado, height: m.lado), display: false)
            cara.panel?.orderFrontRegardless()
        }
        for (id, cara) in caras where !vivas.contains(id) {
            soltar(cara)
            caras[id] = nil
        }
    }

    private func crear(_ cara: Cara) {
        let sensor = SensorDock()
        sensor.alEntrar = { [weak self, weak cara] in if let cara { self?.entro(cara) } }
        sensor.alSalir = { [weak self, weak cara] in if let cara { self?.salio(cara) } }
        let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        p.isFloatingPanel = true
        p.level = NSWindow.Level(rawValue: AuroraLanzador.nivelEsquina)
        p.backgroundColor = .clear
        p.isOpaque = false
        p.hasShadow = false
        p.hidesOnDeactivate = false
        p.isReleasedWhenClosed = false
        p.becomesKeyOnlyIfNeeded = true
        p.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        p.contentView = sensor
        cara.panel = p
        cara.sensor = sensor
    }

    private func entro(_ cara: Cara) {
        guard cara.politica.entra(botonesAbajo: NSEvent.pressedMouseButtons != 0) else { return }
        cara.espera?.cancel()
        let tarea = DispatchWorkItem { [weak self, weak cara] in
            MainActor.assumeIsolated {
                guard let self, let cara, let panel = cara.panel else { return }
                let dentro = NSMouseInRect(NSEvent.mouseLocation, panel.frame.insetBy(dx: -2, dy: -2), false)
                if cara.politica.vence(botonesAbajo: NSEvent.pressedMouseButtons != 0, punteroDentro: dentro) { self.contexto.alternarLanzador() }
            }
        }
        cara.espera = tarea
        DispatchQueue.main.asyncAfter(deadline: .now() + PoliticaEsquina.espera, execute: tarea)
    }

    private func salio(_ cara: Cara) {
        // AppKit avisa una salida falsa al reacomodar ventanas (justo cuando el lanzador se abre): si el puntero sigue en la esquina, no cuenta.
        if let panel = cara.panel, NSMouseInRect(NSEvent.mouseLocation, panel.frame.insetBy(dx: -2, dy: -2), false) { return }
        cara.espera?.cancel()
        cara.politica.sale()
    }

    private func soltar(_ cara: Cara) {
        cara.espera?.cancel()
        cara.sensor?.alEntrar = nil
        cara.sensor?.alSalir = nil
        cara.panel?.contentView = nil
        cara.panel?.orderOut(nil)
        cara.panel = nil
        cara.sensor = nil
    }

    private func soltarTodo() {
        caras.values.forEach(soltar)
        caras = [:]
    }
}
