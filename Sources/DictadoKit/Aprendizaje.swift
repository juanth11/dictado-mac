import Foundation

/// Diccionario que aprende: compara lo que Dictado pegó con lo que quedó después de que lo corregiste y saca las
/// correcciones de palabras sueltas ("lu mina" → "Lumina"). Solo cuenta cambios pequeños y parecidos: si
/// reescribiste la frase o cambiaste un dato, no es un error de transcripción y no se aprende.
public enum Aprendizaje {
    public struct Cambio: Equatable, Sendable {
        public let antes: String
        public let despues: String
        /// Parece un nombre o término (tiene mayúsculas, une o separa palabras, o solo cambia tildes): se aprende a la
        /// primera. Los demás necesitan verse repetidos antes de volverse corrección.
        public let seguro: Bool

        public init(antes: String, despues: String, seguro: Bool) {
            self.antes = antes
            self.despues = despues
            self.seguro = seguro
        }
    }

    /// El tramo que ocupa ahora lo pegado: lo que hay entre el texto de antes y el de después del pegado. nil si
    /// cambió algo fuera del dictado (no se puede saber qué parte es la tuya).
    public static func tramo(pegado: String, valorAlPegar: String, valorAhora: String) -> String? {
        guard !pegado.isEmpty, let r = valorAlPegar.range(of: pegado, options: .backwards) else { return nil }
        let previo = valorAlPegar[..<r.lowerBound], posterior = valorAlPegar[r.upperBound...]
        guard valorAhora.count >= previo.count + posterior.count,
              valorAhora.hasPrefix(previo), valorAhora.hasSuffix(posterior) else { return nil }
        let inicio = valorAhora.index(valorAhora.startIndex, offsetBy: previo.count)
        let fin = valorAhora.index(valorAhora.endIndex, offsetBy: -posterior.count)
        return inicio <= fin ? String(valorAhora[inicio..<fin]) : nil
    }

    /// Las correcciones de palabra que hay entre lo pegado y lo editado.
    public static func cambios(pegado: String, editado: String) -> [Cambio] {
        let a = palabras(pegado), b = palabras(editado)
        guard !a.isEmpty, !b.isEmpty, a.count <= 600, b.count <= 600 else { return [] }
        var resultado: [Cambio] = []
        for (ra, rb) in tramosDistintos(a.map(\.limpia), b.map(\.limpia)) {
            guard (1...3).contains(ra.count), (1...3).contains(rb.count) else { continue }
            let antes = a[ra].map(\.limpia).joined(separator: " ")
            let despues = b[rb].map(\.limpia).joined(separator: " ")
            // Inicio de frase: ahí las mayúsculas son de la gramática, no del término.
            let inicioFrase = rb.lowerBound == 0 || b[rb.lowerBound - 1].cruda.last.map { ".!?:¿¡\n".contains($0) } == true
            if let c = evaluar(antes, despues, inicioFrase: inicioFrase) { resultado.append(c) }
        }
        return resultado
    }

    static func evaluar(_ antes: String, _ despues: String, inicioFrase: Bool) -> Cambio? {
        guard antes != despues,
              !antes.contains(where: \.isNumber), !despues.contains(where: \.isNumber),
              antes.filter(\.isLetter).count >= 3, despues.filter(\.isLetter).count >= 3 else { return nil }
        let fa = plegar(antes), fb = plegar(despues)
        let mayusculas = despues.contains(where: \.isUppercase)
        if fa == fb {
            // Mismas letras: cambió el espacio, las tildes o las mayúsculas.
            let soloPrimera = antes.lowercased() == despues.lowercased()
                && despues.split(separator: " ").allSatisfy { p in !p.dropFirst().contains(where: \.isUppercase) }
                && antes.split(separator: " ").count == despues.split(separator: " ").count
            if soloPrimera {  // "nimbo" → "Nimbo": nombre propio, salvo al empezar frase
                return inicioFrase ? nil : Cambio(antes: antes, despues: despues, seguro: false)
            }
            return Cambio(antes: antes, despues: despues, seguro: !inicioFrase || antes.count != despues.count)
        }
        let largo = max(fa.count, fb.count)
        guard min(fa.count, fb.count) >= 3, distancia(fa, fb) <= max(1, Int(Double(largo) * 0.34)) else { return nil }
        return Cambio(antes: antes, despues: despues, seguro: mayusculas && !inicioFrase)
    }

    // MARK: Piezas

    struct Palabra { let cruda: Substring; let limpia: String }

    static func palabras(_ s: String) -> [Palabra] {
        let bordes = CharacterSet.punctuationCharacters.union(.symbols)
        return s.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).compactMap { cruda in
            let limpia = cruda.trimmingCharacters(in: bordes)
            return limpia.isEmpty ? nil : Palabra(cruda: cruda, limpia: limpia)
        }
    }

    /// Sin mayúsculas, sin tildes y sin espacios.
    static func plegar(_ s: String) -> String {
        s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil).filter { !$0.isWhitespace }
    }

    /// Tramos que no coinciden entre las dos listas, según la subsecuencia común más larga.
    static func tramosDistintos(_ a: [String], _ b: [String]) -> [(Range<Int>, Range<Int>)] {
        let n = a.count, m = b.count
        var lcs = Array(repeating: Array(repeating: 0, count: m + 1), count: n + 1)
        for i in stride(from: n - 1, through: 0, by: -1) {
            for j in stride(from: m - 1, through: 0, by: -1) {
                lcs[i][j] = a[i] == b[j] ? lcs[i + 1][j + 1] + 1 : max(lcs[i + 1][j], lcs[i][j + 1])
            }
        }
        var tramos: [(Range<Int>, Range<Int>)] = []
        var i = 0, j = 0, ia = 0, jb = 0
        func cerrar() {
            if ia < i || jb < j { tramos.append((ia..<i, jb..<j)) }
        }
        while i < n || j < m {
            if i < n, j < m, a[i] == b[j] {
                cerrar()
                i += 1; j += 1
                ia = i; jb = j
            } else if j < m, i == n || lcs[i][j + 1] >= lcs[i + 1][j] {
                j += 1
            } else {
                i += 1
            }
        }
        cerrar()
        return tramos
    }

    static func distancia(_ a: String, _ b: String) -> Int {
        let x = Array(a), y = Array(b)
        guard !x.isEmpty else { return y.count }
        guard !y.isEmpty else { return x.count }
        var previa = Array(0...y.count)
        for i in 1...x.count {
            var actual = [i] + Array(repeating: 0, count: y.count)
            for j in 1...y.count {
                actual[j] = min(previa[j] + 1, actual[j - 1] + 1, previa[j - 1] + (x[i - 1] == y[j - 1] ? 0 : 1))
            }
            previa = actual
        }
        return previa[y.count]
    }
}
