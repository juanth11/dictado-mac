import Testing
@testable import DictadoKit

@Test("Con widgets caben 20 apps por página: columnas 5-8 de las filas 1-2 y 3-8 de las filas 3-4")
func lanz_conWidgets() {
    let r = RejillaLanzador(total: 45, conWidgets: true)
    #expect(r.porPagina == 20)
    #expect(r.paginas == 3)
    #expect(r.celda(de: 0) == .init(fila: 0, columna: 4))
    #expect(r.celda(de: 3) == .init(fila: 0, columna: 7))
    #expect(r.celda(de: 4) == .init(fila: 1, columna: 4))
    #expect(r.celda(de: 8) == .init(fila: 2, columna: 2))
    #expect(r.celda(de: 19) == .init(fila: 3, columna: 7))
    #expect(r.celda(de: 20) == .init(fila: 0, columna: 4))   // la página siguiente repite la disposición
}

@Test("Las apps nunca caen sobre un widget")
func lanz_sinChoques() {
    let r = RejillaLanzador(total: 20, conWidgets: true)
    for c in r.ranuras {
        #expect(!RejillaLanzador.bloquesWidgets.contains { b in
            c.columna >= b.columna && c.columna < b.columna + b.ancho && c.fila >= b.fila && c.fila < b.fila + b.alto
        })
    }
}

@Test("Sin widgets (al buscar) son 40 celdas de 10 × 4")
func lanz_sinWidgets() {
    let r = RejillaLanzador(total: 41, conWidgets: false)
    #expect(r.porPagina == 40)
    #expect(r.paginas == 2)
    #expect(r.celda(de: 9) == .init(fila: 0, columna: 9))
    #expect(r.celda(de: 10) == .init(fila: 1, columna: 0))
}

@Test("Páginas: rango de cada una y casos vacíos")
func lanz_paginas() {
    let r = RejillaLanzador(total: 45, conWidgets: true)
    #expect(r.rango(pagina: 0) == 0..<20)
    #expect(r.rango(pagina: 2) == 40..<45)
    #expect(r.rango(pagina: 9).isEmpty)
    #expect(r.pagina(de: 44) == 2)
    #expect(RejillaLanzador(total: 0, conWidgets: true).paginas == 1)
    #expect(RejillaLanzador(total: 20, conWidgets: true).paginas == 1)
}

@Test("Flechas: izquierda y derecha siguen el orden, cruzan de página y se quedan en los bordes")
func lanz_flechasLados() {
    let r = RejillaLanzador(total: 25, conWidgets: true)
    #expect(r.mover(desde: 0, .izquierda) == 0)
    #expect(r.mover(desde: 19, .derecha) == 20)
    #expect(r.mover(desde: 24, .derecha) == 24)
}

@Test("Flechas: arriba y abajo buscan la columna más cercana de la fila vecina")
func lanz_flechasVerticales() {
    let r = RejillaLanzador(total: 20, conWidgets: true)
    #expect(r.mover(desde: 0, .abajo) == 4)      // fila 0 → 1, misma columna
    #expect(r.mover(desde: 0, .arriba) == 0)     // ya está arriba
    #expect(r.mover(desde: 4, .abajo) == 10)     // columna 4 → fila 2 (columnas 2-7): la celda de la columna 4
    #expect(r.mover(desde: 8, .arriba) == 4)     // columna 2 → la más cercana de la fila 1, la columna 4
    #expect(r.mover(desde: 19, .abajo) == 19)
}

@Test("Flechas: la última fila corta se alcanza desde arriba")
func lanz_ultimaFilaCorta() {
    let r = RejillaLanzador(total: 9, conWidgets: true)   // 8 arriba y 1 en la fila 3
    #expect(r.mover(desde: 5, .abajo) == 8)
    #expect(r.mover(desde: 8, .abajo) == 8)
}

@Test("Lista vacía no revienta")
func lanz_vacia() {
    let r = RejillaLanzador(total: 0, conWidgets: true)
    #expect(r.mover(desde: 0, .abajo) == 0)
}
