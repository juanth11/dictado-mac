import Testing
@testable import DictadoKit

private typealias Par = MapeoHID.Par
private let otro = Par(origen: 0x7_0000_00E1, destino: 0x7_0000_00E5)
private let bloqAControl = Par(origen: MapeoHID.bloqMayus, destino: 0x7_0000_00E0)

@Test("Sin mapeos previos, hyper queda solo y no guarda nada")
func hyperSobreVacio() {
    let r = MapeoHID.conHyper([], guardado: nil, yaAplicado: false)
    #expect(r.mapeo == [MapeoHID.propio])
    #expect(r.previo == nil)
}

@Test("Conserva los mapeos de otras teclas")
func conservaOtros() {
    let r = MapeoHID.conHyper([otro], guardado: nil, yaAplicado: false)
    #expect(r.mapeo.contains(otro) && r.mapeo.contains(MapeoHID.propio))
    #expect(MapeoHID.sinHyper(r.mapeo, previo: r.previo) == [otro])
}

@Test("Un mapeo previo de Bloq Mayús se guarda y vuelve al quitar hyper")
func devuelvePrevio() {
    let r = MapeoHID.conHyper([bloqAControl, otro], guardado: nil, yaAplicado: false)
    #expect(r.previo == bloqAControl)
    #expect(!r.mapeo.contains(bloqAControl))
    let vuelta = MapeoHID.sinHyper(r.mapeo, previo: r.previo)
    #expect(vuelta.contains(bloqAControl) && vuelta.contains(otro) && !vuelta.contains(MapeoHID.propio))
}

@Test("Reaplicar no pierde lo guardado ni duplica")
func reaplicar() {
    let primero = MapeoHID.conHyper([bloqAControl, otro], guardado: nil, yaAplicado: false)
    let otraVez = MapeoHID.conHyper(primero.mapeo, guardado: bloqAControl, yaAplicado: true)
    #expect(otraVez.previo == bloqAControl)
    #expect(otraVez.mapeo.filter { $0 == MapeoHID.propio }.count == 1)
}

@Test("JSON para hidutil, en decimal")
func jsonHidutil() {
    #expect(MapeoHID.json([]) == "{\"UserKeyMapping\":[]}")
    let j = MapeoHID.json([MapeoHID.propio])
    #expect(j.contains("\"HIDKeyboardModifierMappingSrc\":\(MapeoHID.bloqMayus)"))
    #expect(j.contains("\"HIDKeyboardModifierMappingDst\":\(MapeoHID.f18)"))
}
