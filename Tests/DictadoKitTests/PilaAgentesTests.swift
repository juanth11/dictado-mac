import Testing
@testable import DictadoKit

@Suite struct PilaAgentesTests {
    @Test func laGrandeEsLaPrimeraQueTrabaja() {
        let r = PilaAgentes.repartir([.espera, .lista, .trabaja, .trabaja])
        #expect(r.grande == 2)
        #expect(r.pila == [3, 1])   // otra en marcha primero, luego lo terminado
    }

    @Test func sinTrabajoNoHayGrandeYTodoVaALaPila() {
        let r = PilaAgentes.repartir([.lista, .lista])
        #expect(r.grande == nil)
        #expect(r.pila == [0, 1])
    }

    @Test func lasQueEsperanNoEntran() {
        let r = PilaAgentes.repartir([.espera, .espera])
        #expect(r.grande == nil)
        #expect(r.pila.isEmpty)
    }

    @Test func progresoConTope() {
        #expect(PilaAgentes.progreso(contexto: 412_000) == 0.412)
        #expect(PilaAgentes.progreso(contexto: 5_000_000) == 1)
        #expect(PilaAgentes.progreso(contexto: -3) == 0)
        #expect(PilaAgentes.porcentaje(contexto: 412_000) == "41 %")
    }

    @Test func ocultas() {
        #expect(PilaAgentes.ocultas(total: 2) == 0)
        #expect(PilaAgentes.ocultas(total: 5) == 2)
    }
}
