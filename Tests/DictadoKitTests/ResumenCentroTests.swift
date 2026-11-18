import Testing
@testable import DictadoKit

private func texto(_ s: [SegmentoFrase]) -> String { Frase.texto(s) }

@Test("Resumen: TableroCompleto")
func resumen_TableroCompleto() {
    let c = CifrasHoy(sesiones: 7, segundos: 9.4 * 3600, tokens: 190_000_000, costoHoy: 39.17, costoSemana: 135.92)
    #expect(texto(ResumenCentro.tablero(c)) == "7 sesiones, 9,4 h de agentes y 190 M tokens hoy, con US$ 39,17 de costo equivalente y US$ 135,92 en 7 días")
}

@Test("Resumen: TableroUnaSesionYSinCosto")
func resumen_TableroUnaSesionYSinCosto() {
    let c = CifrasHoy(sesiones: 1, segundos: 50 * 60, tokens: nil, costoHoy: nil, costoSemana: nil)
    #expect(texto(ResumenCentro.tablero(c)) == "1 sesión y 50 min de agentes hoy")
}

@Test("Resumen: TableroSoloCosto")
func resumen_TableroSoloCosto() {
    let c = CifrasHoy(sesiones: nil, segundos: nil, tokens: nil, costoHoy: 4.5, costoSemana: 20)
    #expect(texto(ResumenCentro.tablero(c)) == "Costo equivalente: US$ 4,50 hoy y US$ 20,00 en 7 días")
}

@Test("Resumen: TableroVacioNoInventa")
func resumen_TableroVacioNoInventa() {
    #expect(ResumenCentro.tablero(CifrasHoy()).isEmpty)
}

@Test("Resumen: ConsumoConAmbasFuentes")
func resumen_ConsumoConAmbasFuentes() {
    let s = ResumenCentro.consumo(claudeCode: ("US$ 41,25", "US$ 493,22", "US$ 2.003"), hermes30: "US$ 0,53")
    #expect(texto(s) == "Claude Code: US$ 41,25 hoy, US$ 493,22 en 7 días y US$ 2.003 en 30 días. Hermes: US$ 0,53 en 30 días")
}

@Test("Resumen: ConsumoSoloHermes")
func resumen_ConsumoSoloHermes() {
    #expect(texto(ResumenCentro.consumo(claudeCode: nil, hermes30: "1,2 M")) == "Hermes: 1,2 M en 30 días")
}

@Test("Resumen: Herramientas")
func resumen_Herramientas() {
    let s = ResumenCentro.herramientas(mcpActivos: 12, mcpSinUso: 3, skillsActivas: 48, skillsSinUso: 0, enReserva: 20, pluginsActivos: 1, pluginsInstalados: 9)
    #expect(texto(s) == "12 MCP activos (3 sin uso), 48 skills activas, 20 en reserva y 1 de 9 plugin activo")
    #expect(s.contains { $0.tono == .acento && $0.texto.contains("3 sin uso") })
}

@Test("Resumen: AutomatizacionesSeDiceConPalabras")
func resumen_AutomatizacionesSeDiceConPalabras() {
    let r = ResumenAutomatizaciones(total: 20, fallo: 1, parado: 0, atrasado: 0, alDia: 14, sinDato: 2, apagado: 1)
    let s = ResumenCentro.automatizaciones(r)
    #expect(texto(s) == "1 pide atención, 14 al día, 2 sin dato y 1 apagada")
    #expect(s.first?.tono == .acento)
}

@Test("Resumen: AutomatizacionesVacio")
func resumen_AutomatizacionesVacio() {
    #expect(texto(ResumenCentro.automatizaciones(ResumenAutomatizaciones())) == "Nada programado")
}


@Test("Tema del fondo: la preferencia manda y en automático decide la luminancia")
func resumen_temaDelFondo() {
    #expect(TemaDelFondo.esClaro(preferencia: .oscuro, fondo: .mac, luminanciaClara: true, sistemaOscuro: false) == false)
    #expect(TemaDelFondo.esClaro(preferencia: .claro, fondo: .mac, luminanciaClara: false, sistemaOscuro: true))
    #expect(TemaDelFondo.esClaro(preferencia: .sistema, fondo: .mac, luminanciaClara: false, sistemaOscuro: false))
    #expect(TemaDelFondo.esClaro(preferencia: .automatico, fondo: .mac, luminanciaClara: true, sistemaOscuro: true))
    #expect(TemaDelFondo.esClaro(preferencia: .automatico, fondo: .mac, luminanciaClara: nil, sistemaOscuro: false) == false)
    #expect(TemaDelFondo.esClaro(preferencia: .automatico, fondo: .paleta("lagunaDurazno"), luminanciaClara: true, sistemaOscuro: false) == false)
}

@Test("Velo del Centro: nada en fondos oscuros, más cuanto más claro es el fondo")
func resumen_refuerzoDeVelo() {
    #expect(TemaDelFondo.refuerzoDeVelo(luminancia: nil) == 0)
    #expect(TemaDelFondo.refuerzoDeVelo(luminancia: 0.2) == 0)
    #expect(TemaDelFondo.refuerzoDeVelo(luminancia: TemaDelFondo.refuerzoDesde) == 0)
    #expect(TemaDelFondo.refuerzoDeVelo(luminancia: 1) == TemaDelFondo.refuerzoMaximo)
    #expect(TemaDelFondo.refuerzoDeVelo(luminancia: 2) == TemaDelFondo.refuerzoMaximo)
    #expect(TemaDelFondo.refuerzoDeVelo(luminancia: 0.8) > TemaDelFondo.refuerzoDeVelo(luminancia: 0.6))
}

@Test("Preferencia de tema: da la vuelta automático, oscuro, claro")
func resumen_preferenciaGira() {
    #expect(PreferenciaTema.automatico.siguiente == .oscuro)
    #expect(PreferenciaTema.oscuro.siguiente == .claro)
    #expect(PreferenciaTema.claro.siguiente == .automatico)
}
