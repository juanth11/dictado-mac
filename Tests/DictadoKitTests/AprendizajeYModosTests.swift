import Testing
@testable import DictadoKit

@Test("Une palabras de un nombre: se aprende a la primera")
func uneNombre() {
    let c = Aprendizaje.cambios(pegado: "Mándale el informe a lu mina hoy.", editado: "Mándale el informe a Lumina hoy.")
    #expect(c == [.init(antes: "lu mina", despues: "Lumina", seguro: true)])
}

@Test("Una letra mal transcrita en un nombre")
func letraMal() {
    let c = Aprendizaje.cambios(pegado: "Revisa el contrato de Nímbo mañana", editado: "Revisa el contrato de Nimbo mañana")
    #expect(c.count == 1)
    #expect(c.first?.antes == "Nímbo")
    #expect(c.first?.despues == "Nimbo")
}

@Test("Reescribir o cambiar un dato no se aprende", arguments: [
    ("Nos vemos el lunes en la oficina", "Nos vemos el martes en la oficina"),
    ("Son 9 millones", "Son 10 millones"),
    ("Te escribo para contarte algo", "Quería contarte algo importante sobre la reunión"),
    ("el informe está listo", "el informe está listo y enviado"),
])
func noAprende(pegado: String, editado: String) {
    #expect(Aprendizaje.cambios(pegado: pegado, editado: editado).isEmpty)
}

@Test("Mayúscula al empezar frase no es un término")
func inicioFrase() {
    let c = Aprendizaje.cambios(pegado: "listo lo envío hoy", editado: "Listo lo envío hoy")
    #expect(c.isEmpty)
}

@Test("Nombre propio en minúscula: se aprende, pero pide repetirse")
func nombrePropio() {
    let c = Aprendizaje.cambios(pegado: "habla con fabián del caso", editado: "habla con Fabián del caso")
    #expect(c == [.init(antes: "fabián", despues: "Fabián", seguro: false)])
}

@Test("Encuentra lo pegado aunque lo edites")
func tramo() {
    let t = Aprendizaje.tramo(pegado: "hola lu mina", valorAlPegar: "Asunto: hola lu mina. Fin",
                              valorAhora: "Asunto: hola Lumina. Fin")
    #expect(t == "hola Lumina")
    #expect(Aprendizaje.tramo(pegado: "hola", valorAlPegar: "x hola y", valorAhora: "z hola y") == nil)
}

let ejemploModos = """
# comentario
[Correo]
apps: Mail, com.microsoft.Outlook
pestañas: Gmail
instrucciones: Tono profesional.
instrucciones: Trata de usted.

[Código]
apps: com.jetbrains., Terminal
instrucciones: Técnico.
pulir: no

[Otro]
apps: *
instrucciones: Mantén el tono.
"""

@Test("Lee el archivo de modos")
func leeModos() {
    let m = ModosDictado.leer(ejemploModos)
    #expect(m.map(\.nombre) == ["Correo", "Código", "Otro"])
    #expect(m[0].apps == ["Mail", "com.microsoft.Outlook"])
    #expect(m[0].pestanas == ["Gmail"])
    #expect(m[0].instrucciones == "Tono profesional. Trata de usted.")
    #expect(m[1].pulir == false)
}

@Test("Elige el modo por app, prefijo, nombre, pestaña o comodín")
func eligeModo() {
    let m = ModosDictado.leer(ejemploModos)
    #expect(ModosDictado.elegir(m, bundle: "com.apple.mail", nombreApp: "Mail", titulo: nil, navegador: false)?.nombre == "Correo")
    #expect(ModosDictado.elegir(m, bundle: "com.microsoft.Outlook", nombreApp: "Outlook", titulo: nil, navegador: false)?.nombre == "Correo")
    #expect(ModosDictado.elegir(m, bundle: "com.jetbrains.pycharm", nombreApp: "PyCharm", titulo: nil, navegador: false)?.nombre == "Código")
    #expect(ModosDictado.elegir(m, bundle: "com.apple.Terminal", nombreApp: "terminal", titulo: nil, navegador: false)?.nombre == "Código")
    #expect(ModosDictado.elegir(m, bundle: "com.google.Chrome", nombreApp: "Google Chrome", titulo: "Recibidos - Gmail", navegador: true)?.nombre == "Correo")
    #expect(ModosDictado.elegir(m, bundle: "com.apple.finder", nombreApp: "Finder", titulo: "Descargas", navegador: false)?.nombre == "Otro")
}
