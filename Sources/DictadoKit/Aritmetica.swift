import Foundation

/// Calculadora del lanzador. Un analizador propio, sin `NSExpression`: lo escrito en el buscador es texto de la persona
/// y nunca se evalúa como código. Acepta + − × ÷ (también `-`, `*`, `/`), paréntesis, decimales con coma o punto y
/// porcentaje; todo lo demás se rechaza.
public enum Aritmetica {
    private static let largoMaximo = 160
    private static let profundidadMaxima = 48
    private static let magnitudMaxima = 1e15

    /// El valor de una expresión, o nil si no lo es: texto suelto, un número solo, símbolos de más, división entre cero.
    /// Hace falta al menos una operación o un porcentaje: "42" y "(5)" no son cuentas.
    public static func evaluar(_ texto: String) -> Double? {
        let caracteres = Array(texto.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !caracteres.isEmpty, caracteres.count <= largoMaximo else { return nil }
        var analizador = Analizador(caracteres)
        guard let v = analizador.expresion(0), analizador.alFinal(), analizador.hizoOperacion,
              v.x.isFinite, abs(v.x) < magnitudMaxima else { return nil }
        return v.x
    }

    /// "1.234,5" no existe: sin separador de miles. Hasta 10 decimales, sin ceros de sobra y con coma decimal.
    public static func formatear(_ valor: Double) -> String {
        if valor == valor.rounded(), abs(valor) < magnitudMaxima { return String(Int64(valor)) }
        var texto = String(format: "%.10f", valor)
        while texto.hasSuffix("0") { texto.removeLast() }
        if texto.hasSuffix(".") { texto.removeLast() }
        if texto == "-0" || texto.isEmpty { texto = "0" }
        return texto.replacingOccurrences(of: ".", with: ",")
    }

    /// El resultado listo para mostrar y copiar, o nil si el texto no es una cuenta.
    public static func resultado(_ texto: String) -> String? {
        evaluar(texto).map(formatear)
    }

    private struct Valor { var x: Double; var porcentaje = false }

    private struct Analizador {
        let c: [Character]
        var i = 0
        var hizoOperacion = false
        init(_ c: [Character]) { self.c = c }

        mutating func alFinal() -> Bool { saltarEspacios(); return i >= c.count }

        mutating func saltarEspacios() { while i < c.count, c[i].isWhitespace { i += 1 } }

        mutating func mirar() -> Character? { saltarEspacios(); return i < c.count ? c[i] : nil }

        // suma := termino (('+'|'-') termino)*     "200 + 10%" suma el 10 % de 200
        mutating func expresion(_ nivel: Int) -> Valor? {
            guard nivel < Aritmetica.profundidadMaxima, var izq = termino(nivel) else { return nil }
            while let op = mirar(), "+-−–".contains(op) {
                i += 1
                hizoOperacion = true
                guard let der = termino(nivel) else { return nil }
                let monto = der.porcentaje ? izq.x * der.x : der.x
                izq = Valor(x: "+".contains(op) ? izq.x + monto : izq.x - monto)
            }
            return izq
        }

        // termino := unario (('*'|'/') unario)*
        mutating func termino(_ nivel: Int) -> Valor? {
            guard var izq = unario(nivel) else { return nil }
            while let op = mirar(), "*×/÷".contains(op) {
                i += 1
                hizoOperacion = true
                guard let der = unario(nivel) else { return nil }
                if "*×".contains(op) {
                    izq = Valor(x: izq.x * der.x)
                } else {
                    guard der.x != 0 else { return nil }
                    izq = Valor(x: izq.x / der.x)
                }
            }
            return izq
        }

        // unario := ('+'|'-') unario | primario '%'*
        mutating func unario(_ nivel: Int) -> Valor? {
            guard nivel < Aritmetica.profundidadMaxima, let p = mirar() else { return nil }
            if "+-−–".contains(p) {
                i += 1
                guard var v = unario(nivel + 1) else { return nil }
                if !"+".contains(p) { v.x = -v.x }
                return v
            }
            guard var v = primario(nivel) else { return nil }
            while mirar() == "%" {
                i += 1
                hizoOperacion = true
                v = Valor(x: v.x / 100, porcentaje: true)
            }
            return v
        }

        mutating func primario(_ nivel: Int) -> Valor? {
            guard let p = mirar() else { return nil }
            if p == "(" {
                i += 1
                guard let v = expresion(nivel + 1), mirar() == ")" else { return nil }
                i += 1
                return Valor(x: v.x)
            }
            return numero()
        }

        /// Dígitos con a lo sumo un separador decimal (coma o punto).
        mutating func numero() -> Valor? {
            var texto = ""
            var separadores = 0
            var digitos = 0
            while i < c.count {
                let ch = c[i]
                if ch.isASCII, ch.isNumber { texto.append(ch); digitos += 1 }
                else if ch == "." || ch == "," { separadores += 1; texto.append(".") }
                else { break }
                i += 1
            }
            guard digitos > 0, separadores <= 1, let x = Double(texto) else { return nil }
            return Valor(x: x)
        }
    }
}
