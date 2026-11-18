import CoreGraphics

public enum AccionVentana: Equatable, Sendable {
    case izquierda, derecha, casiMaximizar, restaurar, otraPantalla, centrar
    /// Hyper + D (dos ventanas a la vez): no pasa por `plan`; se registra para que ↓ / ↩ puedan volver al previo.
    case disponer
}


/// Una pantalla en coordenadas de Accesibilidad: origen arriba a la izquierda de la pantalla principal, y hacia
/// abajo. `visible` descuenta la barra de menús y el Dock.
public struct PantallaAX: Equatable, Sendable {
    public var marco: CGRect
    public var visible: CGRect
    public init(marco: CGRect, visible: CGRect) { self.marco = marco; self.visible = visible }
}

/// Lo que se recuerda de una ventana para poder restaurar y para seguir el ciclo de tamaños.
public struct MemoriaVentana: Equatable, Sendable {
    /// El marco antes de que Dictado la acomodara (lo que restaura Hyper + ↓).
    public var previo: CGRect
    /// El marco que quedó tras la última acción, leído de la ventana (no el pedido: la app pudo ajustarlo).
    public var ultimo: CGRect
    /// Lo que quedó registrado (no siempre la tecla: volver al previo con ↑ queda como "restaurar").
    public var accion: AccionVentana
    public var paso: Int
    public init(previo: CGRect, ultimo: CGRect, accion: AccionVentana, paso: Int) {
        self.previo = previo; self.ultimo = ultimo; self.accion = accion; self.paso = paso
    }
}

public enum GeometriaVentanas {
    /// Ciclo de Hyper + ←/→: mitad, tercio, dos tercios.
    public static let fracciones: [CGFloat] = [1.0 / 2, 1.0 / 3, 2.0 / 3]
    public static let margenCasi: CGFloat = 12
    /// Tolerancia al comparar marcos: las apps redondean el tamaño a su manera.
    public static let tolerancia: CGFloat = 4

    /// NSScreen mide desde abajo a la izquierda de la pantalla principal; Accesibilidad, desde arriba.
    public static func aAX(_ r: CGRect, alturaPrincipal: CGFloat) -> CGRect {
        CGRect(x: r.minX, y: alturaPrincipal - r.maxY, width: r.width, height: r.height)
    }

    /// Pantallas en coordenadas AX a partir de (frame, visibleFrame) de NSScreen. La principal es la de origen (0, 0).
    public static func pantallas(_ cocoa: [(marco: CGRect, visible: CGRect)]) -> [PantallaAX] {
        guard let principal = cocoa.first(where: { $0.marco.origin == .zero }) ?? cocoa.first else { return [] }
        let h = principal.marco.height
        return cocoa.map { PantallaAX(marco: aAX($0.marco, alturaPrincipal: h), visible: aAX($0.visible, alturaPrincipal: h)) }
    }

    /// La pantalla donde está la mayor parte de la ventana; si no toca ninguna, la más cercana a su centro.
    public static func indice(de ventana: CGRect, en pantallas: [PantallaAX]) -> Int? {
        guard !pantallas.isEmpty else { return nil }
        let areas = pantallas.map { p -> CGFloat in
            let i = p.marco.intersection(ventana)
            return i.isNull ? 0 : i.width * i.height
        }
        if let mayor = areas.max(), mayor > 0 { return areas.firstIndex(of: mayor) }
        let centro = CGPoint(x: ventana.midX, y: ventana.midY)
        return pantallas.indices.min { a, b in
            distancia(centro, pantallas[a].marco) < distancia(centro, pantallas[b].marco)
        }
    }

    private static func distancia(_ p: CGPoint, _ r: CGRect) -> CGFloat {
        hypot(p.x - r.midX, p.y - r.midY)
    }

    public static func lado(izquierda: Bool, paso: Int, en v: CGRect) -> CGRect {
        let ancho = (v.width * fracciones[paso % fracciones.count]).rounded()
        return CGRect(x: izquierda ? v.minX : v.maxX - ancho, y: v.minY, width: ancho, height: v.height)
    }

    /// Lo mismo que `lado` pero arriba o abajo y a todo el ancho (pantallas verticales).
    public static func franja(arriba: Bool, paso: Int, en v: CGRect) -> CGRect {
        let alto = (v.height * fracciones[paso % fracciones.count]).rounded()
        return CGRect(x: v.minX, y: arriba ? v.minY : v.maxY - alto, width: v.width, height: alto)
    }

    /// Hyper + D: cuánto le toca a la ventana del frente, en ciclo.
    public static let repartos: [CGFloat] = [2.0 / 3, 1.0 / 2, 1.0 / 3]

    /// La del frente arriba y la otra abajo en una pantalla vertical; lado a lado (la del frente a la izquierda) en una
    /// horizontal.
    public static func disposicion(paso: Int, en v: CGRect) -> (frente: CGRect, otra: CGRect) {
        let f = repartos[paso % repartos.count]
        if vertical(v) {
            let alto = (v.height * f).rounded()
            return (CGRect(x: v.minX, y: v.minY, width: v.width, height: alto),
                    CGRect(x: v.minX, y: v.minY + alto, width: v.width, height: v.height - alto))
        }
        let ancho = (v.width * f).rounded()
        return (CGRect(x: v.minX, y: v.minY, width: ancho, height: v.height),
                CGRect(x: v.minX + ancho, y: v.minY, width: v.width - ancho, height: v.height))
    }

    /// Más alta que ancha: un monitor girado.
    public static func vertical(_ v: CGRect) -> Bool { v.height > v.width }

    /// ¿La ventana está en una pantalla vertical?
    public static func enVertical(_ ventana: CGRect, pantallas: [PantallaAX]) -> Bool {
        indice(de: ventana, en: pantallas).map { vertical(pantallas[$0].visible) } ?? false
    }

    /// Qué tamaño del ciclo toca: si lo último fue esta misma acción y la ventana no se movió desde entonces, el
    /// siguiente; si ya coincide con un paso del ciclo, el que sigue; si no, la mitad.
    public static func pasoCiclo(_ accion: AccionVentana, actual: CGRect, memoria: MemoriaVentana?, marco: (Int) -> CGRect) -> Int {
        if let m = memoria, parecidos(actual, m.ultimo), m.accion == accion {
            return (m.paso + 1) % fracciones.count
        }
        for k in fracciones.indices where parecidos(actual, marco(k)) {
            return (k + 1) % fracciones.count
        }
        return 0
    }

    public static func pasoLado(izquierda: Bool, actual: CGRect, en v: CGRect, memoria: MemoriaVentana?) -> Int {
        pasoCiclo(izquierda ? .izquierda : .derecha, actual: actual, memoria: memoria) { lado(izquierda: izquierda, paso: $0, en: v) }
    }

    public static func casiMaximizada(_ v: CGRect) -> CGRect {
        v.insetBy(dx: margenCasi, dy: margenCasi)
    }

    /// Mismo tamaño (recortado si no cabe), centrada en el área visible.
    public static func centrada(_ m: CGRect, en v: CGRect) -> CGRect {
        let w = min(m.width, v.width), h = min(m.height, v.height)
        return redondear(CGRect(x: v.midX - w / 2, y: v.midY - h / 2, width: w, height: h))
    }

    /// La misma posición y tamaño relativos en otra pantalla (una mitad izquierda sigue siendo mitad izquierda). Entre
    /// una pantalla horizontal y una vertical se giran los ejes: la mitad izquierda pasa a ser la de arriba y la derecha,
    /// la de abajo (y al revés), para que nada quede como una tira angosta.
    public static func trasladada(_ m: CGRect, de o: CGRect, a d: CGRect) -> CGRect {
        var rel = CGRect(x: (m.minX - o.minX) / o.width, y: (m.minY - o.minY) / o.height,
                         width: m.width / o.width, height: m.height / o.height)
        if vertical(o) != vertical(d) { rel = CGRect(x: rel.minY, y: rel.minX, width: rel.height, height: rel.width) }
        let r = CGRect(x: d.minX + rel.minX * d.width, y: d.minY + rel.minY * d.height,
                       width: rel.width * d.width, height: rel.height * d.height)
        return redondear(ajustada(r, a: d))
    }

    /// La pantalla pegada a ese lado (la más cercana hacia la izquierda o la derecha), si hay.
    public static func vecina(_ i: Int, izquierda: Bool, en pantallas: [PantallaAX]) -> Int? {
        let m = pantallas[i].marco
        let candidatas = pantallas.indices.filter { j in
            j != i && (izquierda ? pantallas[j].marco.midX < m.minX : pantallas[j].marco.midX > m.maxX)
        }
        func hueco(_ j: Int) -> CGFloat {
            izquierda ? m.minX - pantallas[j].marco.maxX : pantallas[j].marco.minX - m.maxX
        }
        return candidatas.min { hueco($0) < hueco($1) }
    }

    /// Recorta el tamaño a lo que cabe y mete la ventana dentro del área visible.
    public static func ajustada(_ m: CGRect, a v: CGRect) -> CGRect {
        let w = min(m.width, v.width), h = min(m.height, v.height)
        return CGRect(x: min(max(m.minX, v.minX), v.maxX - w), y: min(max(m.minY, v.minY), v.maxY - h), width: w, height: h)
    }

    /// La pantalla que sigue de izquierda a derecha (y de arriba abajo si están apiladas), en ciclo.
    public static func siguiente(_ i: Int, en pantallas: [PantallaAX]) -> Int {
        let orden = pantallas.indices.sorted { a, b in
            let pa = pantallas[a].marco, pb = pantallas[b].marco
            return pa.minX != pb.minX ? pa.minX < pb.minX : pa.minY < pb.minY
        }
        guard let pos = orden.firstIndex(of: i) else { return i }
        return orden[(pos + 1) % orden.count]
    }

    public static func parecidos(_ a: CGRect, _ b: CGRect) -> Bool {
        abs(a.minX - b.minX) <= tolerancia && abs(a.minY - b.minY) <= tolerancia
            && abs(a.width - b.width) <= tolerancia && abs(a.height - b.height) <= tolerancia
    }

    public static func redondear(_ r: CGRect) -> CGRect {
        CGRect(x: r.minX.rounded(), y: r.minY.rounded(), width: r.width.rounded(), height: r.height.rounded())
    }

    public typealias Plan = (marco: CGRect, paso: Int, registro: AccionVentana)

    /// El marco nuevo para la acción y lo que se registra en memoria, o nil si no hay nada que hacer (sin previo que
    /// restaurar, una sola pantalla, ninguna pantalla hacia ese lado).
    public static func plan(_ accion: AccionVentana, actual: CGRect, pantallas: [PantallaAX], memoria: MemoriaVentana?) -> Plan? {
        guard let i = indice(de: actual, en: pantallas) else { return nil }
        let v = pantallas[i].visible
        // ¿La ventana sigue como la dejó Dictado? Si la moviste a mano, su marco actual pasa a ser el "previo".
        let acomodada = memoria.map { parecidos(actual, $0.ultimo) } ?? false
        if vertical(v) { return planVertical(accion, actual: actual, i: i, pantallas: pantallas, memoria: acomodada ? memoria : nil) }
        switch accion {
        case .izquierda, .derecha:
            let izquierda = accion == .izquierda
            let paso = pasoLado(izquierda: izquierda, actual: actual, en: v, memoria: acomodada ? memoria : nil)
            return (lado(izquierda: izquierda, paso: paso, en: v), paso, accion)
        case .casiMaximizar:
            // Volver al previo queda como "restaurar", para que el siguiente ↑ vuelva a casi maximizar.
            if let m = memoria, acomodada, m.accion == .casiMaximizar { return (m.previo, 0, .restaurar) }
            return (casiMaximizada(v), 0, accion)
        case .restaurar:
            guard let m = memoria, !parecidos(actual, m.previo) else { return nil }
            return (m.previo, 0, accion)
        case .otraPantalla:
            guard pantallas.count > 1 else { return nil }
            return (trasladada(actual, de: v, a: pantallas[siguiente(i, en: pantallas)].visible), 0, accion)
        case .centrar:
            return (centrada(actual, en: v), 0, accion)
        case .disponer:
            return nil
        }
    }

    /// Las mismas teclas en una pantalla vertical (ver el encabezado). `memoria` solo llega si la ventana sigue como
    /// la dejó Dictado.
    private static func planVertical(_ accion: AccionVentana, actual: CGRect, i: Int, pantallas: [PantallaAX],
                                     memoria: MemoriaVentana?) -> Plan? {
        let v = pantallas[i].visible
        switch accion {
        case .casiMaximizar, .restaurar:   // ↑ arriba, ↓ abajo
            let arriba = accion == .casiMaximizar
            let paso = pasoCiclo(accion, actual: actual, memoria: memoria) { franja(arriba: arriba, paso: $0, en: v) }
            return (franja(arriba: arriba, paso: paso, en: v), paso, accion)
        case .izquierda, .derecha:
            let izquierda = accion == .izquierda
            guard let j = vecina(i, izquierda: izquierda, en: pantallas) else { return nil }
            let d = pantallas[j].visible
            if vertical(d) { return (trasladada(actual, de: v, a: d), 0, .otraPantalla) }
            // Queda en la mitad de la horizontal que da hacia la vertical; se registra como ese lado, para que
            // allí la tecla contraria la lleve a la otra mitad y la misma siga el ciclo.
            return (lado(izquierda: !izquierda, paso: 0, en: d), 0, izquierda ? .derecha : .izquierda)
        case .centrar:   // ↩ casi maximiza; otra vez, vuelve al previo
            if let m = memoria, m.accion == .centrar { return (m.previo, 0, .restaurar) }
            return (casiMaximizada(v), 0, .centrar)
        case .otraPantalla:
            guard pantallas.count > 1 else { return nil }
            return (trasladada(actual, de: v, a: pantallas[siguiente(i, en: pantallas)].visible), 0, accion)
        case .disponer:
            return nil
        }
    }

    /// Lo que queda en memoria tras aplicar la acción (`accion` es lo que el plan pidió registrar). El previo solo se
    /// renueva si la ventana estaba "libre" (nunca la tocó Dictado o la moviste a mano): así volver al previo lleva al
    /// tamaño de antes de toda la serie de atajos.
    public static func recordar(_ memoria: MemoriaVentana?, accion: AccionVentana, antes: CGRect, leido: CGRect, paso: Int) -> MemoriaVentana {
        let acomodada = memoria.map { parecidos(antes, $0.ultimo) } ?? false
        let previo = acomodada ? memoria!.previo : antes
        return MemoriaVentana(previo: previo, ultimo: leido, accion: accion, paso: paso)
    }
}

