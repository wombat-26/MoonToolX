import SwiftUI

/// Menüpunkt Hilfe › MoonToolX-Kurzanleitung (⌘?)
struct HelpMenuButton: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("MoonToolX-Kurzanleitung") { openWindow(id: "help") }
            .keyboardShortcut("?", modifiers: .command)
    }
}

/// Kurzanleitung für Benutzer
struct HelpView: View {
    static let windowSize = CGSize(width: 560, height: 640)

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "–"
        let b = info?["CFBundleVersion"] as? String ?? "–"
        return "Version \(v) (\(b))"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 14) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MoonToolX").font(.title.weight(.semibold))
                        Text("Kurzanleitung · \(version)").foregroundStyle(.secondary)
                    }
                }

                section("Was MoonToolX zeigt", symbol: "moon.stars") {
                    Text("MoonToolX berechnet die aktuelle Entfernung zwischen Erdmittelpunkt und Mondmittelpunkt sekundengenau und zeigt dazu die Mondphase.")
                }

                section("Das Hauptfenster", symbol: "macwindow") {
                    item("Fallblattanzeige", "Entfernung in Kilometern mit Metern, jede Sekunde neu berechnet.")
                    item("Änderung", "Ob sich der Mond gerade nähert oder entfernt und wie schnell, in Metern pro Sekunde mit einer Nachkommastelle.")
                    item("Lichtlaufzeit", "So lange braucht das Licht vom Mond zur Erde.")
                    item("Oberfläche – Oberfläche", "Entfernung minus mittlerer Erd- und Mondradius.")
                    item("Entfernung von Ihrem Standort", "Abstand von Ihrem Mac-Standort zum Mondmittelpunkt. Steht der Mond hoch am Himmel, ist er bis zu einen Erdradius (etwa 6.400 km) kleiner als der Abstand der Mittelpunkte; bei Mondauf- und -untergang sind beide fast gleich. Beim ersten Start fragt macOS, ob MoonToolX den Standort verwenden darf. Der Standort bleibt auf Ihrem Mac.")
                    item("Mondhöhe · Richtung", "Höhe des Mondmittelpunkts über dem Horizont an Ihrem Standort, ohne Lichtbrechung der Atmosphäre: + über dem Horizont, − darunter. Dazu die Himmelsrichtung (N, NNO, NO … NNW) und der Azimut in Grad, von Nord über Ost gezählt (Ost = 90°, Süd = 180°). Steht der Mond unter dem Horizont, zeigt die Richtung, wo er sich unter dem Horizont befindet.")
                    item("Mondbild", "Aktuelle Phase, Norden oben, so wie der Mond von der Nordhalbkugel aus erscheint. Mit **Wie am Himmel** unter dem Bild dreht MoonToolX den Mond so, wie Sie ihn an Ihrem Standort sehen: Zenit oben, das orange N markiert den Mond-Nordpol. Je nach Breitengrad und Tageszeit liegt der Mond schräg oder steht auf der Südhalbkugel fast kopf. Steht er unter dem Horizont, erscheint er blass. Die Größe folgt der Entfernung: In Erdnähe erscheint der Mond größer, in Erdferne kleiner, im selben Verhältnis wie am Himmel.")
                    item("Auf- und Untergang", "Unter dem Mondbild: ob der Mond gerade sichtbar ist und wie lange noch, bzw. wann er aufgeht; dazu Aufgang, höchster Stand (Meridiandurchgang mit Höhe) und Untergang an Ihrem Standort, mit Himmelsrichtung. Auf- und Untergang gelten für den oberen Mondrand mit Lichtbrechung der Atmosphäre, wie in Kalendern üblich, auf etwa eine Minute genau.")
                    item("Scheinbarer Durchmesser", "So groß erscheint der Mond am Himmel, in Bogenminuten (60 Bogenminuten = 1 Grad), von Ihrem Standort aus gesehen.")
                    item("Supermond und Mikromond", "Steht der Mond bei Vollmond oder Neumond nahe dem Perigäum, zeigt MoonToolX „Supermond“ bzw. „Super-Neumond“; nahe dem Apogäum „Mikromond“ bzw. „Mikro-Neumond“. Grundlage ist die Definition von Richard Nolle: höchstens 10 % der Spanne zwischen Perigäum und Apogäum des laufenden Umlaufs. Die Kennzeichnung nennt Zeitpunkt (Ortszeit) und Entfernung des Vollmonds bzw. Neumonds, nicht die aktuelle Entfernung.")
                    item("Termine", "Nächste Hauptphasen sowie Perigäum (erdnächster Punkt) und Apogäum (erdfernster Punkt), in Ortszeit.")
                }

                section("Rückblick und Vorschau im Diagramm", symbol: "cursorarrow.click") {
                    Text("Das Diagramm zeigt die Entfernung 14 Tage zurück und 14 Tage voraus. Klicken Sie auf eine Stelle im Diagramm: MoonToolX zeigt für 3 Sekunden Mondbild, Phase und Entfernung zu diesem Zeitpunkt und kehrt dann zur aktuellen Anzeige zurück. Links von der gestrichelten Linie (jetzt) heißt das **Rückblick**, rechts davon **Vorschau**. Ein weiterer Klick startet die 3 Sekunden neu.")
                }

                section("Widget hinzufügen", symbol: "square.grid.2x2") {
                    step(1, "Ziehen Sie MoonToolX in den Ordner **Programme** und starten Sie die App einmal.")
                    step(2, "Klicken Sie mit der rechten Maustaste auf den Schreibtisch und wählen Sie **Widgets bearbeiten …** aus.")
                    step(3, "Suchen Sie nach **MoonToolX**, wählen Sie die Größe (klein, mittel oder groß) und ziehen Sie das Widget an die gewünschte Stelle.")
                    Text("Das Widget aktualisiert sich genau dann, wenn sich die angezeigte Kilometerzahl ändert, spätestens jede Minute. Wie die drei Größen aussehen, zeigt **Fenster › Widget-Vorschau**.")
                        .foregroundStyle(.secondary)
                }

                section("Darstellung", symbol: "circle.lefthalf.filled") {
                    Text("MoonToolX folgt dem Erscheinungsbild von macOS (hell oder dunkel). Ist in den Systemeinstellungen unter **Bedienungshilfen › Bewegung** die Option **Bewegung reduzieren** eingeschaltet, wechselt die Fallblattanzeige ohne Animation.")
                }

                section("Genauigkeit und Daten", symbol: "scope") {
                    item("Ephemeride", "JPL DE440 (NASA Jet Propulsion Laboratory), gültig von 2020 bis 2099. Die Berechnung ist weitaus genauer als die angezeigten Meter.")
                    item("Standort", "Entfernung vom Standort auf unter 0,1 km, Mondhöhe und Himmelsrichtung auf unter 0,001° genau (Abgleich mit JPL Horizons). Erlauben oder entziehen können Sie den Zugriff in den Systemeinstellungen unter **Datenschutz & Sicherheit › Ortungsdienste**.")
                    item("Phasenzeiten", "Auf etwa eine Minute genau.")
                    item("Mondbilder", "Aus der LRO/LROC-Mondkarte (NASA Scientific Visualization Studio), in 2-Grad-Schritten. Die Libration (das leichte Taumeln des Mondes) wird nicht dargestellt.")
                    item("Zeiten", "Alle Zeiten in der Zeitzone, die in macOS eingestellt ist.")
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(width: Self.windowSize.width, height: Self.windowSize.height)
    }

    private func section<Content: View>(_ title: String, symbol: String,
                                        @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: symbol)
                .font(.title3.weight(.semibold))
            VStack(alignment: .leading, spacing: 6, content: content)
                .padding(.leading, 30)
        }
    }

    private func item(_ title: String, _ text: String) -> some View {
        Text("\(Text(title).bold()): \(text)")
            .fixedSize(horizontal: false, vertical: true)
    }

    private func step(_ n: Int, _ text: LocalizedStringKey) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("\(n).").bold().monospacedDigit()
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
    }
}
