import Testing
@testable import DictadoKit

private let cal = calendarioDePrueba()

private let ejemplo = """
[{"id": 7, "texto": "Enviar el poder firmado", "origen": "reunion", "ref": "Comité", "cita": "Ana, quedas tú.", "vence": "2026-11-17",
  "estado": "abierta", "creada": "2026-11-15T09:00:00", "cerrada": null},
 {"id": 3, "texto": "Pagar la cuota", "origen": "manual", "ref": null, "cita": null, "vence": null, "estado": "abierta"},
 {"id": 9, "texto": "Ya hecha", "origen": "dictado", "vence": "2026-11-16", "estado": "hecha", "cerrada": "2026-11-16T08:15:00"},
 {"id": 11, "texto": "", "origen": "manual"},
 {"sin": "id"}]
"""

@Test("Tareas: la lista del centro se lee y salta las mal formadas")
func tareasDecodificar() {
    let t = TareasCentro.decodificar(datosJSON(ejemplo))
    #expect(t?.map(\.id) == [7, 3, 9])
    #expect(t?[0].cita == "Ana, quedas tú." && t?[0].ref == "Comité")
    #expect(t?[1].vence == nil && t?[1].ref == nil)
}

@Test("Tareas: un rechazo del centro o una respuesta que no es lista no es una lista")
func tareasRechazo() {
    #expect(TareasCentro.decodificar(datosJSON("{\"ok\": false, \"error\": \"estado inválido\"}")) == nil)
    #expect(TareasCentro.decodificar(datosJSON("sin novedades")) == nil)
    #expect(TareasCentro.decodificar(datosJSON("[]")) == [])
}

@Test("Tareas: el rótulo une el origen con el vencimiento")
func tareasRotulo() {
    let ahora = f(16, 9)
    let t = TareaCentro(id: 1, texto: "x", origen: "reunion", ref: "Comité", vence: "2026-11-17")
    #expect(TareasCentro.rotulo(t, ahora: ahora, calendario: cal) == "Comité · vence mañana")
    #expect(TareasCentro.rotulo(TareaCentro(id: 2, texto: "x", origen: "dictado"), ahora: ahora, calendario: cal) == "Dictado")
    #expect(TareasCentro.vencimiento("2026-11-16", ahora: ahora, calendario: cal) == "vence hoy")
    #expect(TareasCentro.vencimiento("2026-11-15", ahora: ahora, calendario: cal) == "venció ayer")
    #expect(TareasCentro.vencimiento("2026-11-12", ahora: ahora, calendario: cal) == "venció hace 4 días")
    #expect(TareasCentro.vencimiento("2026-11-20", ahora: ahora, calendario: cal) == "vence vie 20")
    #expect(TareasCentro.vencimiento("basura", ahora: ahora, calendario: cal) == nil)
}

@Test("Tareas: abiertas primero las que vencen antes; sin fecha al final")
func tareasOrden() {
    let lista = [TareaCentro(id: 1, texto: "a"), TareaCentro(id: 2, texto: "b", vence: "2026-11-20"),
                 TareaCentro(id: 3, texto: "c", vence: "2026-11-17"), TareaCentro(id: 4, texto: "d", estado: "hecha")]
    #expect(TareasCentro.ordenar(lista).map(\.id) == [3, 2, 1])
}

@Test("Tareas: el día cuenta las hechas hoy y las abiertas")
func tareasResumen() {
    let lista = [TareaCentro(id: 1, texto: "a"), TareaCentro(id: 2, texto: "b"),
                 TareaCentro(id: 3, texto: "c", estado: "hecha", cerrada: "2026-11-16T08:15:00"),
                 TareaCentro(id: 4, texto: "d", estado: "hecha", cerrada: "2026-11-15T20:00:00"),
                 TareaCentro(id: 5, texto: "e", estado: "descartada", cerrada: "2026-11-16T09:00:00")]
    let r = TareasCentro.resumenDelDia(lista, ahora: f(16, 12), calendario: cal)
    #expect(r.hechas == 1 && r.total == 3)
}
