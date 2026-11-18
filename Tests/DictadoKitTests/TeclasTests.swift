import Testing
@testable import DictadoKit

@Test("El paneo sigue la posición de la tecla: q a la izquierda, p a la derecha")
func paneoPorColumna() {
    let q = MapaTeclas.paneo(codigo: 12), p = MapaTeclas.paneo(codigo: 35)
    #expect(q < -0.3)
    #expect(p > 0.3)
    #expect(MapaTeclas.paneo(codigo: 0) < MapaTeclas.paneo(codigo: 37))  // a antes que l
    #expect(MapaTeclas.paneo(codigo: 18) < MapaTeclas.paneo(codigo: 29))  // 1 antes que 0
}

@Test("El espacio queda cerca del centro y el intro a la derecha")
func espacioEIntro() {
    #expect(abs(MapaTeclas.paneo(codigo: 49)) < 0.2)
    #expect(MapaTeclas.paneo(codigo: 36) > 0.4)
}

@Test("El paneo nunca pasa de la amplitud y un código desconocido va al centro")
func limitesDelPaneo() {
    for c in 0...130 { #expect(abs(MapaTeclas.paneo(codigo: c, amplitud: 0.7)) <= 0.7 + 1e-9) }
    #expect(MapaTeclas.paneo(codigo: 999) == 0)
}

@Test("Cada fila del teclado crece de izquierda a derecha")
func ordenDeLasFilas() {
    let filas: [[Int]] = [[18, 19, 20, 21, 23, 22, 26, 28, 25, 29], [12, 13, 14, 15, 17, 16, 32, 34, 31, 35], [0, 1, 2, 3, 5, 4, 38, 40, 37], [6, 7, 8, 9, 11, 45, 46]]
    for fila in filas {
        let p = fila.map { MapaTeclas.posicion(codigo: $0) }
        #expect(p == p.sorted())
    }
}

@Test("Espacio, intro y retroceso son teclas grandes; los modificadores y F18 no suenan")
func clasesDeTecla() {
    for c in [49, 36, 51] { #expect(MapaTeclas.esGrande(codigo: c)) }
    #expect(!MapaTeclas.esGrande(codigo: 0))
    for c in [55, 56, 58, 59, 79] { #expect(MapaTeclas.silenciosa(codigo: c)) }
    #expect(!MapaTeclas.silenciosa(codigo: 49))
}

@Test("Todos los sonidos de todos los perfiles son audibles, no recortan y no están vacíos", arguments: PerfilTeclas.allCases)
func sonidosSanos(perfil: PerfilTeclas) {
    for (abajo, grande) in [(true, false), (false, false), (true, true), (false, true)] {
        let x = SintesisTeclas.generar(perfil, abajo: abajo, grande: grande)
        #expect(x.count > 1000)
        #expect(AnalisisAudio.pico(x) < 0.95)
        #expect(AnalisisAudio.pico(x) > 0.05)
        #expect(AnalisisAudio.duracion(x) < 0.3)
        #expect(x.allSatisfy { $0.isFinite })
        #expect(abs(x.last ?? 1) < 0.01)      // termina en silencio: sin clic
    }
}

@Test("Soltar es más ligero que pulsar")
func arribaMasLigero() {
    for perfil in PerfilTeclas.allCases {
        let abajo = SintesisTeclas.generar(perfil, abajo: true, grande: false)
        let arriba = SintesisTeclas.generar(perfil, abajo: false, grande: false)
        #expect(AnalisisAudio.rms(arriba) < AnalisisAudio.rms(abajo))
        #expect(arriba.count < abajo.count)
    }
}

@Test("Los perfiles suenan distinto: el clack es mucho más agudo que el thock")
func perfilesDistintos() {
    let c = PerfilTeclas.allCases.map { AnalisisAudio.centroide(SintesisTeclas.generar($0, abajo: true, grande: false)) }
    #expect(Set(c.map { Int($0 / 50) }).count == c.count)   // ningún par cae en la misma franja de 50 Hz
    let thock = AnalisisAudio.centroide(SintesisTeclas.generar(.thock, abajo: true, grande: false))
    let clack = AnalisisAudio.centroide(SintesisTeclas.generar(.clack, abajo: true, grande: false))
    #expect(clack > thock * 5)
}

@Test("El volumen es parejo entre perfiles (RMS dentro de ±30 % del thock salvo el clack, ajustado por oído)")
func volumenParejo() {
    let base = AnalisisAudio.rms(SintesisTeclas.generar(.thock, abajo: true, grande: false))
    for p in [PerfilTeclas.crema, .burbuja] {
        let r = AnalisisAudio.rms(SintesisTeclas.generar(p, abajo: true, grande: false))
        #expect(abs(r / base - 1) < 0.3)
    }
}

@Test("Es determinista: dos veces da exactamente lo mismo")
func determinista() {
    #expect(SintesisTeclas.generar(.crema, abajo: true, grande: true) == SintesisTeclas.generar(.crema, abajo: true, grande: true))
}

@Test("Cambiar el tono cambia la duración al revés y mantiene la forma")
func cambioDeTono() {
    let x = SintesisTeclas.generar(.thock, abajo: true, grande: false)
    let agudo = SintesisTeclas.conTono(x, razon: 1.05)
    let grave = SintesisTeclas.conTono(x, razon: 0.95)
    #expect(agudo.count < x.count && grave.count > x.count)
    #expect(AnalisisAudio.centroide(agudo) > AnalisisAudio.centroide(x))
    #expect(AnalisisAudio.centroide(grave) < AnalisisAudio.centroide(x))
    #expect(SintesisTeclas.conTono(x, razon: 1) == x)
}

@Test("Las razones de tono son simétricas y el centro es 1")
func razonesDeTono() {
    let r = SintesisTeclas.razones(maximo: 0.08, pasos: 9)
    #expect(r.count == 9)
    #expect(r[4] == 1)
    #expect(abs(r[0] - 0.92) < 1e-9 && abs(r[8] - 1.08) < 1e-9)
    #expect(SintesisTeclas.razones(maximo: 0.08, pasos: 1) == [1])
}

@Test("El WAV tiene encabezado válido y el tamaño justo")
func wav() {
    let d = AnalisisAudio.datosWAV([0, 0.5, -0.5, 1])
    #expect(d.count == 44 + 8)
    #expect(Array(d[0..<4]) == Array("RIFF".utf8))
    #expect(Array(d[8..<12]) == Array("WAVE".utf8))
}
