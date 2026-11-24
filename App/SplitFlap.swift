import SwiftUI

// MARK: - Fallblattanzeige (Solari-Stil, wie Flug- und Zuganzeiger der 70er)
//
// Jede Ziffer ist ein Blatt aus zwei Hälften. Beim Wechsel klappt die obere Hälfte
// nach unten weg, danach fällt die untere Hälfte des neuen Zeichens herunter.
// Wie bei den echten Tafeln läuft eine Ziffer vorwärts durch 0…9, bis sie den Zielwert erreicht.

struct SplitFlapBoard: View {
    let text: String
    var cellWidth: CGFloat = 34
    var cellHeight: CGFloat = 54

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(text.enumerated()), id: \.offset) { _, char in
                if char.isNumber {
                    SplitFlapCell(target: char, width: cellWidth, height: cellHeight)
                } else {
                    Text(String(char))
                        .font(.custom("DINCondensed-Bold", size: cellHeight * 0.62))
                        .foregroundStyle(FlapStyle.housingText)
                        .frame(width: cellWidth * 0.32, height: cellHeight, alignment: .bottom)
                        .offset(y: -cellHeight * 0.08)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(FlapStyle.housing))
        .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(text)
    }
}

enum FlapStyle {
    static let housing = Color(red: 0.07, green: 0.07, blue: 0.08)
    static let housingText = Color(red: 0.93, green: 0.91, blue: 0.84)
    static let flapTop = LinearGradient(colors: [Color(white: 0.20), Color(white: 0.15)], startPoint: .top, endPoint: .bottom)
    static let flapBottom = LinearGradient(colors: [Color(white: 0.13), Color(white: 0.10)], startPoint: .top, endPoint: .bottom)
    static let glyph = Color(red: 0.96, green: 0.94, blue: 0.87)
}

struct SplitFlapCell: View {
    let target: Character
    let width: CGFloat
    let height: CGFloat

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var shown: Character
    @State private var old: Character
    @State private var topAngle: Double = 0
    @State private var bottomAngle: Double = 0
    @State private var flipTask: Task<Void, Never>?

    init(target: Character, width: CGFloat, height: CGFloat) {
        self.target = target
        self.width = width
        self.height = height
        _shown = State(initialValue: target)
        _old = State(initialValue: target)
    }

    var body: some View {
        ZStack {
            // feststehende Hälften: oben schon das neue, unten noch das alte Zeichen
            VStack(spacing: 1.5) {
                half(shown, top: true)
                half(old, top: false)
            }
            // bewegliche Blätter
            VStack(spacing: 1.5) {
                half(old, top: true)
                    .overlay(Color.black.opacity(0.45).opacity(abs(topAngle) / 90))   // Ebenen-Deckkraft: billig
                    .rotation3DEffect(.degrees(topAngle), axis: (x: 1, y: 0, z: 0),
                                      anchor: .bottom, perspective: 0.45)
                half(shown, top: false)
                    .overlay(Color.black.opacity(0.45).opacity(abs(bottomAngle) / 90))
                    .rotation3DEffect(.degrees(bottomAngle), axis: (x: 1, y: 0, z: 0),
                                      anchor: .top, perspective: 0.45)
            }
            // Achse in der Mitte
            Rectangle()
                .fill(Color.black.opacity(0.85))
                .frame(height: 1.5)
            HStack {
                hinge
                Spacer()
                hinge
            }
            .padding(.horizontal, -1)
        }
        .frame(width: width, height: height)
        .onChange(of: target) { _, newValue in
            animate(to: newValue)
        }
        .onDisappear { flipTask?.cancel() }
    }

    private var hinge: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(Color(white: 0.32))
            .frame(width: 2.5, height: height * 0.12)
    }

    private func half(_ char: Character, top: Bool) -> some View {
        let r: CGFloat = 4
        return Text(String(char))
            .font(.custom("DINCondensed-Bold", size: height * 0.98))
            .foregroundStyle(FlapStyle.glyph)
            .frame(width: width, height: height)
            .offset(y: height * 0.06)          // DIN Condensed sitzt etwas hoch
            .frame(width: width, height: (height - 1.5) / 2, alignment: top ? .top : .bottom)
            .clipped()
            .background(top ? FlapStyle.flapTop : FlapStyle.flapBottom)
            .clipShape(UnevenRoundedRectangle(topLeadingRadius: top ? r : 0,
                                              bottomLeadingRadius: top ? 0 : r,
                                              bottomTrailingRadius: top ? 0 : r,
                                              topTrailingRadius: top ? r : 0,
                                              style: .continuous))
    }

    // MARK: Ablauf

    private func animate(to newValue: Character) {
        flipTask?.cancel()
        guard !reduceMotion else {
            shown = newValue; old = newValue; topAngle = 0; bottomAngle = 0
            return
        }
        flipTask = Task { @MainActor in
            let steps = Self.steps(from: shown, to: newValue)
            // Gesamtdauer begrenzen, damit die Tafel im Sekundentakt fertig wird
            let perFlip = min(0.18, 0.6 / Double(max(steps.count, 1)))
            for next in steps {
                if Task.isCancelled { break }
                await flip(to: next, duration: perFlip)
            }
            if Task.isCancelled { return }
            settle(newValue)
        }
    }

    private func flip(to next: Character, duration: Double) async {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            old = shown
            shown = next
            topAngle = 0
            bottomAngle = 89.9
        }
        withAnimation(.easeIn(duration: duration * 0.5)) { topAngle = -89.9 }
        try? await Task.sleep(for: .seconds(duration * 0.5))
        withAnimation(.easeOut(duration: duration * 0.5)) { bottomAngle = 0 }
        try? await Task.sleep(for: .seconds(duration * 0.5))
        withTransaction(instant) {
            old = shown
            topAngle = 0
        }
    }

    private func settle(_ value: Character) {
        var instant = Transaction()
        instant.disablesAnimations = true
        withTransaction(instant) {
            shown = value; old = value; topAngle = 0; bottomAngle = 0
        }
    }

    /// Zwischenschritte wie bei einer echten Fallblatttafel: immer vorwärts 0 → 9 → 0.
    /// Bei mehr als drei Schritten (die schnellen Meterstellen) direkt auf den Zielwert,
    /// sonst blättert die Tafel ununterbrochen und kostet unnötig CPU.
    static func steps(from: Character, to: Character) -> [Character] {
        guard let a = from.wholeNumberValue, let b = to.wholeNumberValue, a != b else {
            return from == to ? [] : [to]
        }
        let count = (b - a + 10) % 10
        guard count <= 3 else { return [to] }
        return (1...count).map { Character(String((a + $0) % 10)) }
    }
}

#Preview {
    SplitFlapBoard(text: "361.190,469")
        .padding()
}
