import Testing
@testable import DictadoKit

private func fila(_ cuantas: Int, ancho: Double = 72, hueco: Double = 10) -> [LupaDock.Pieza] {
    (0..<cuantas).map { LupaDock.Pieza(izquierda: Double($0) * (ancho + hueco), ancho: ancho) }
}

@Test("Lupa: sin puntero todo queda en reposo")
func lupaReposo() {
    let r = LupaDock.calcular(fila(5), puntero: nil)
    #expect(r == .reposo(5))
}

@Test("Lupa: el perfil vale 1 bajo el puntero, 0 al radio y baja de forma monótona")
func lupaPerfil() {
    #expect(LupaDock.perfil(0) == 1)
    #expect(LupaDock.perfil(LupaDock.radio) == 0)
    #expect(LupaDock.perfil(LupaDock.radio * 2) == 0)
    var anterior = 1.0
    for d in stride(from: 0.0, through: LupaDock.radio, by: 5) {
        let v = LupaDock.perfil(d)
        #expect(v <= anterior + 1e-12)
        anterior = v
    }
    #expect(abs(LupaDock.escala(distancia: 0) - 1.5) < 1e-12)
}

@Test("Lupa: la pieza bajo el puntero llega a 1,5 y las lejanas no crecen")
func lupaEscalas() {
    let piezas = fila(9)
    let centro = piezas[4].centro
    let r = LupaDock.calcular(piezas, puntero: centro)
    #expect(abs(r.efectos[4].escala - 1.5) < 1e-9)
    #expect(r.efectos[0].escala == 1)
    #expect(r.efectos[8].escala == 1)
    #expect(r.efectos[3].escala > 1 && r.efectos[3].escala < r.efectos[4].escala)
    #expect(abs(r.efectos[3].escala - r.efectos[5].escala) < 1e-9)
}

@Test("Lupa: las vecinas se apartan sin solaparse y el punto bajo el puntero no se mueve")
func lupaSinSolape() {
    let piezas = fila(7)
    for x in stride(from: piezas[0].izquierda, through: piezas[6].derecha, by: 13) {
        let r = LupaDock.calcular(piezas, puntero: x)
        for i in 0..<(piezas.count - 1) {
            let a = piezas[i], b = piezas[i + 1]
            let finA = a.centro + r.efectos[i].desplazamiento + a.ancho * r.efectos[i].escala / 2
            let inicioB = b.centro + r.efectos[i + 1].desplazamiento - b.ancho * r.efectos[i + 1].escala / 2
            #expect(inicioB - finA >= 10 - 1e-9)   // el hueco de reposo se mantiene
        }
        // El punto bajo el puntero queda donde estaba.
        let k = piezas.lastIndex { $0.izquierda <= x } ?? 0
        let e = r.efectos[k]
        let izquierdaNueva = piezas[k].centro + e.desplazamiento - piezas[k].ancho * e.escala / 2
        let dentro = min(x, piezas[k].derecha)
        let nuevo = izquierdaNueva + (dentro - piezas[k].izquierda) / piezas[k].ancho * piezas[k].ancho * e.escala + (x - dentro)
        #expect(abs(nuevo - x) < 1e-6)
    }
}

@Test("Lupa: la barra solo se ensancha, y por los dos lados cuando el puntero está en medio")
func lupaCrecimiento() {
    let piezas = fila(9)
    let medio = LupaDock.calcular(piezas, puntero: piezas[4].centro)
    #expect(medio.crecimientoIzquierda > 0 && medio.crecimientoDerecha > 0)
    #expect(abs(medio.crecimientoIzquierda - medio.crecimientoDerecha) < 1e-6)
    let borde = LupaDock.calcular(piezas, puntero: piezas[0].centro)
    #expect(borde.crecimientoIzquierda < medio.crecimientoIzquierda)
    #expect(borde.crecimientoIzquierda >= 0 && borde.crecimientoDerecha >= 0)
}

@Test("Lupa: las piezas que no crecen solo se apartan")
func lupaWidgets() {
    var piezas = fila(5)
    piezas[2].crece = false
    let r = LupaDock.calcular(piezas, puntero: piezas[2].centro)
    #expect(r.efectos[2].escala == 1)
    #expect(r.efectos[1].escala > 1)
}

@Test("Lupa: sin escala máxima no hay efecto y una lista vacía no falla")
func lupaBordes() {
    #expect(LupaDock.calcular(fila(3), puntero: 50, maxima: 1) == .reposo(3))
    #expect(LupaDock.calcular([], puntero: 10).efectos.isEmpty)
}

// MARK: Ventanas por app

@Test("Ventanas: reconoce a Cra, a los Chromium y a Safari")
func ventanasFamilias() {
    #expect(NavegadoresDock.familia(bundleID: "dk.kildahl.cra") == .cra)
    #expect(NavegadoresDock.familia(bundleID: "com.google.Chrome") == .chromium)
    #expect(NavegadoresDock.familia(bundleID: "com.apple.Safari") == .safari)
    #expect(NavegadoresDock.familia(bundleID: "com.apple.finder") == nil)
    #expect(NavegadoresDock.familia(bundleID: nil) == nil)
}

@Test("Ventanas: el guion de Cra usa su diccionario (id de pestaña y active tab) y el de saltar usa select")
func ventanasGuionCra() {
    let g = NavegadoresDock.guionListar(bundleID: "dk.kildahl.cra", familia: .cra)
    #expect(g.contains("tell application id \"dk.kildahl.cra\""))
    #expect(g.contains("active tab of w"))
    #expect(g.contains("title of t"))
    let v = VentanaNavegador(indice: 1, id: "W\"1", titulo: "x", pestanas: [])
    let p = PestanaApp(id: "T9", titulo: "t", indice: 3, activa: false)
    let s = NavegadoresDock.guionSaltar(bundleID: "dk.kildahl.cra", familia: .cra, ventana: v, pestana: p)
    #expect(s.contains("select (first tab of (first window whose id is \"W\\\"1\") whose id is \"T9\")"))
    #expect(s.contains("activate"))
}

@Test("Ventanas: Chromium y Safari saltan por número y suben la ventana")
func ventanasGuionesOtros() {
    let v = VentanaNavegador(indice: 2, id: "", titulo: "", pestanas: [])
    let p = PestanaApp(id: "5", titulo: "", indice: 5, activa: false)
    let c = NavegadoresDock.guionSaltar(bundleID: "com.google.Chrome", familia: .chromium, ventana: v, pestana: p)
    #expect(c.contains("set active tab index of window 2 to 5") && c.contains("set index of window 2 to 1"))
    let s = NavegadoresDock.guionSaltar(bundleID: "com.apple.Safari", familia: .safari, ventana: v, pestana: p)
    #expect(s.contains("set current tab of window 2 to tab 5 of window 2"))
}

@Test("Ventanas: lee los registros del guion y agrupa las pestañas por ventana")
func ventanasLeer() {
    let rs = NavegadoresDock.separadorRegistro, us = NavegadoresDock.separadorCampo
    func reg(_ campos: [String]) -> String { campos.joined(separator: us) + rs }
    let texto = reg(["1", "w1", "Docs", "1", "a", "Docs", "false"]) + reg(["1", "w1", "Docs", "2", "b", "Mail", "true"])
        + reg(["2", "w2", "Otra", "1", "c", "Hola", "true"]) + "basura" + rs
    let v = NavegadoresDock.leer(texto)
    #expect(v.count == 2)
    #expect(v[0].pestanas.map(\.titulo) == ["Docs", "Mail"])
    #expect(v[0].pestanas[1].activa && !v[0].pestanas[0].activa)
    #expect(v[1].id == "w2" && v[1].pestanas.count == 1)
    #expect(NavegadoresDock.leer("").isEmpty)
}

@Test("Ventanas: empareja por título (o prefijo) y si no por posición")
func ventanasEmparejar() {
    let a = VentanaNavegador(indice: 1, id: "a", titulo: "Docs", pestanas: [])
    let b = VentanaNavegador(indice: 2, id: "b", titulo: "Mail", pestanas: [])
    #expect(NavegadoresDock.emparejar(titulo: "Mail", posicion: 0, entre: [a, b])?.id == "b")
    #expect(NavegadoresDock.emparejar(titulo: "Docs - Cra", posicion: 1, entre: [a, b])?.id == "a")
    #expect(NavegadoresDock.emparejar(titulo: "Otra", posicion: 1, entre: [a, b])?.id == "b")
    #expect(NavegadoresDock.emparejar(titulo: "Otra", posicion: 5, entre: [a, b]) == nil)
}

@Test("Ventanas: el título del panel se limpia y se recorta")
func ventanasTitulo() {
    #expect(PanelVentanasDock.titulo("  \n ") == "Sin título")
    #expect(PanelVentanasDock.titulo("a\nb") == "a b")
    #expect(PanelVentanasDock.titulo(String(repeating: "x", count: 80)).count == 46)
}
