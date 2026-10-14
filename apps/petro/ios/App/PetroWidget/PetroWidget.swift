import WidgetKit
import SwiftUI

// MARK: - البيانات المشتركة (App Group) — نفس صيغة أندرويد: "v1;..." للوردية و"c1;..." للتقويم

/// قراءة من Keychain مشترك بين التطبيق والويدجت (لا يحتاج App Group ولا تسجيلاً في بوابة Apple).
enum SharedKeychain {
    static var group: String? { Bundle.main.object(forInfoDictionaryKey: "KeychainGroup") as? String }

    static func get(_ key: String) -> String? {
        guard let g = group else { return nil }
        let q: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "petro.widget",
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: g,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum Store {

    static let gregorian: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.firstWeekday = 1 // الأحد
        c.timeZone = TimeZone.current
        return c
    }()

    static func key(_ d: Date) -> String {
        let f = DateFormatter()
        f.calendar = gregorian
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    struct ShiftDay { let type: Character; let day: Int; let len: Int; let nextType: Character; let nextLen: Int }

    static func shiftDays() -> [String: ShiftDay] {
        guard let raw = SharedKeychain.get("data"), raw.hasPrefix("v1;") else { return [:] }
        var out: [String: ShiftDay] = [:]
        for rec in raw.dropFirst(3).split(separator: ";") {
            let f = rec.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            guard f.count == 6, let t = f[1].first, let d = Int(f[2]), let l = Int(f[3]), let nt = f[4].first, let nl = Int(f[5]) else { continue }
            out[f[0]] = ShiftDay(type: t, day: d, len: l, nextType: nt, nextLen: nl)
        }
        return out
    }

    static func calDays() -> [String: Character] {
        guard let raw = SharedKeychain.get("cal"), raw.hasPrefix("c1;") else { return [:] }
        var out: [String: Character] = [:]
        for rec in raw.dropFirst(3).split(separator: ";") {
            let f = rec.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
            if f.count == 2, let t = f[1].first { out[f[0]] = t }
        }
        return out
    }

    static func themeId() -> String { SharedKeychain.get("theme") ?? "petro" }
}

// MARK: - الثيمات

struct Theme {
    let bg: Color, primary: Color, secondary: Color, accent: Color, pastText: Color, futureText: Color

    static func by(_ id: String) -> Theme {
        switch id {
        case "dark": return Theme(bg: Color(hex: 0x111827), primary: Color(hex: 0xF9FAFB), secondary: Color(hex: 0xD1D5DB), accent: Color(hex: 0x3CC285), pastText: Color(hex: 0x9CA3AF), futureText: Color(hex: 0x1F2937))
        case "ocean": return Theme(bg: Color(hex: 0xE0F2FE), primary: Color(hex: 0x0C2A43), secondary: Color(hex: 0x38617F), accent: Color(hex: 0x0369A1), pastText: Color(hex: 0x8AA6BC), futureText: Color(hex: 0x0C2A43))
        case "sunset": return Theme(bg: Color(hex: 0xFFEDD5), primary: Color(hex: 0x431407), secondary: Color(hex: 0x7C4A2D), accent: Color(hex: 0xC2410C), pastText: Color(hex: 0xB08A74), futureText: Color(hex: 0x431407))
        case "glass": return Theme(bg: Color(hex: 0x1E293B), primary: .white, secondary: Color(hex: 0xE5E7EB), accent: Color(hex: 0x6EE7B7), pastText: Color(hex: 0xB6BDC8), futureText: Color(hex: 0x111827))
        default: return Theme(bg: .white, primary: Color(hex: 0x111827), secondary: Color(hex: 0x4B5563), accent: Color(hex: 0x1A8754), pastText: Color(hex: 0x9CA3AF), futureText: Color(hex: 0x374151))
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}

extension View {
    @ViewBuilder func widgetBackground(_ color: Color) -> some View {
        if #available(iOSApplicationExtension 17.0, *) {
            self.containerBackground(color, for: .widget)
        } else {
            self.background(color)
        }
    }
}

// MARK: - مساعدات العرض

func arabicDigits(_ n: Int) -> String {
    String(String(n).map { c -> Character in
        if let v = c.wholeNumberValue, let u = UnicodeScalar(0x0660 + v) { return Character(u) }
        return c
    })
}

func daysText(_ n: Int) -> String {
    if n == 1 { return "يوم واحد" }
    if n == 2 { return "يومان" }
    if n >= 3 && n <= 10 { return arabicDigits(n) + " أيام" }
    return arabicDigits(n) + " يوماً"
}

func typeLabel(_ t: Character) -> String {
    switch t { case "m": return "وردية الصباح"; case "a": return "وردية العصر"; case "n": return "وردية الليل"; default: return "راحة" }
}

func typeColor(_ t: Character) -> Color {
    switch t { case "m": return Color(hex: 0xF59E0B); case "a": return Color(hex: 0xF97316); case "n": return Color(hex: 0x6366F1); default: return Color(hex: 0x9CA3AF) }
}

func typeLetter(_ t: Character) -> String {
    switch t { case "m": return "ص"; case "a": return "ع"; case "n": return "ل"; default: return "ر" }
}

struct DayChip: View {
    let text: String, type: Character, state: Int, theme: Theme, size: CGFloat
    var body: some View {
        let base = typeColor(type)
        Text(text)
            .font(.system(size: size * 0.42, weight: .bold))
            .foregroundColor(state == 1 ? .white : (state == 0 ? theme.pastText : theme.futureText))
            .frame(maxWidth: .infinity, minHeight: size, maxHeight: size)
            .background(RoundedRectangle(cornerRadius: 8).fill(state == 1 ? base : base.opacity(state == 0 ? 0.12 : 0.28)))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(state == 1 ? Color.white : Color.clear, lineWidth: 2))
    }
}

struct Logo: View {
    var size: CGFloat
    var body: some View {
        Image("Logo").resizable().scaledToFit().frame(width: size, height: size)
    }
}

// MARK: - الخط الزمني

struct DayEntry: TimelineEntry { let date: Date }

struct DayProvider: TimelineProvider {
    func placeholder(in context: Context) -> DayEntry { DayEntry(date: Date()) }
    func getSnapshot(in context: Context, completion: @escaping (DayEntry) -> Void) { completion(DayEntry(date: Date())) }
    func getTimeline(in context: Context, completion: @escaping (Timeline<DayEntry>) -> Void) {
        let cal = Store.gregorian
        let start = cal.startOfDay(for: Date())
        var entries = [DayEntry(date: Date())]
        for i in 1...7 { if let d = cal.date(byAdding: .day, value: i, to: start) { entries.append(DayEntry(date: d)) } }
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

// MARK: - ويدجت الوردية (صغير / متوسط 4×2 / شاشة القفل)

struct ShiftWidgetView: View {
    let entry: DayEntry
    @Environment(\.widgetFamily) var family

    var body: some View {
        let theme = Theme.by(Store.themeId())
        let days = Store.shiftDays()
        let today = days[Store.key(entry.date)]
        Group {
            switch family {
            case .accessoryInline:
                Text(today.map { typeLabel($0.type) + " · " + arabicDigits($0.day) + "/" + arabicDigits($0.len) } ?? "افتح التطبيق")
            case .accessoryRectangular:
                VStack(alignment: .leading, spacing: 2) {
                    Text(today.map { typeLabel($0.type) } ?? "افتح التطبيق لتحديث الجدول").font(.headline)
                    if let t = today {
                        Text("اليوم " + arabicDigits(t.day) + " من " + arabicDigits(t.len)).font(.caption)
                        Text(t.len - t.day == 0 ? "آخر يوم" : "باقي " + daysText(t.len - t.day)).font(.caption)
                    }
                }
            case .systemSmall:
                small(theme, today)
            default:
                medium(theme, today, days)
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetBackground(theme.bg)
    }

    func small(_ theme: Theme, _ t: Store.ShiftDay?) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack { Logo(size: 22); Spacer() }
            if let t = t {
                Text(typeLabel(t.type)).font(.system(size: 17, weight: .bold)).foregroundColor(theme.primary)
                Text("اليوم " + arabicDigits(t.day) + " من " + arabicDigits(t.len)).font(.system(size: 12)).foregroundColor(theme.secondary)
                Spacer(minLength: 0)
                Text(t.len - t.day == 0 ? "آخر يوم" : "باقي " + daysText(t.len - t.day)).font(.system(size: 13, weight: .bold)).foregroundColor(theme.accent)
            } else {
                Text("افتح التطبيق لتحديث الجدول").font(.system(size: 13, weight: .bold)).foregroundColor(theme.primary)
            }
        }
    }

    func medium(_ theme: Theme, _ t: Store.ShiftDay?, _ days: [String: Store.ShiftDay]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Logo(size: 26)
                Text(t.map { typeLabel($0.type) } ?? "افتح التطبيق لتحديث الجدول").font(.system(size: 17, weight: .bold)).foregroundColor(theme.primary)
                Spacer()
                if let t = t { Text("اليوم " + arabicDigits(t.day) + " من " + arabicDigits(t.len)).font(.system(size: 13)).foregroundColor(theme.secondary) }
            }
            if let t = t {
                let count = min(t.len, 7)
                let start = t.len <= 7 ? 0 : min(max(t.day - 1 - 3, 0), t.len - 7)
                HStack(spacing: 4) {
                    ForEach(0..<count, id: \.self) { i in
                        let a = start + i
                        DayChip(text: arabicDigits(a + 1), type: t.type, state: a < t.day - 1 ? 0 : (a == t.day - 1 ? 1 : 2), theme: theme, size: 34)
                    }
                }
                HStack {
                    Text(t.len - t.day == 0 ? "آخر يوم في هذه الفترة" : "باقي " + daysText(t.len - t.day)).font(.system(size: 14, weight: .bold)).foregroundColor(theme.primary)
                    Spacer()
                    Text("بعدها: " + typeLabel(t.nextType) + " " + daysText(t.nextLen)).font(.system(size: 12)).foregroundColor(theme.secondary)
                }
            }
        }
    }
}

struct ShiftWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PetroShiftWidget", provider: DayProvider()) { entry in
            ShiftWidgetView(entry: entry)
        }
        .configurationDisplayName("ورديتي")
        .description("ورديتك واليوم الحالي والأيام المتبقية منها")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - ويدجت التقويم (كبير 4×4)

struct CalendarWidgetView: View {
    let entry: DayEntry
    static let months = ["يناير", "فبراير", "مارس", "أبريل", "مايو", "يونيو", "يوليو", "أغسطس", "سبتمبر", "أكتوبر", "نوفمبر", "ديسمبر"]
    static let weekdays = ["أحد", "إثنين", "ثلاثاء", "أربعاء", "خميس", "جمعة", "سبت"]

    var body: some View {
        let theme = Theme.by(Store.themeId())
        let cal = Store.gregorian
        let map = Store.calDays()
        let comps = cal.dateComponents([.year, .month], from: entry.date)
        let first = cal.date(from: comps) ?? entry.date
        let offset = cal.component(.weekday, from: first) - 1
        let dim = cal.range(of: .day, in: .month, for: first)?.count ?? 30
        let todayKey = Store.key(entry.date)
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Logo(size: 24)
                Text(Self.months[(comps.month ?? 1) - 1] + " " + arabicDigits(comps.year ?? 2026)).font(.system(size: 16, weight: .bold)).foregroundColor(theme.primary)
                Spacer()
            }
            HStack(spacing: 3) {
                ForEach(0..<7, id: \.self) { i in
                    Text(Self.weekdays[i]).font(.system(size: 10, weight: .bold)).foregroundColor(theme.secondary).frame(maxWidth: .infinity)
                }
            }
            ForEach(0..<6, id: \.self) { row in
                HStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { col in
                        let idx = row * 7 + col
                        let day = idx - offset + 1
                        if day >= 1 && day <= dim, let d = cal.date(byAdding: .day, value: day - 1, to: first) {
                            let k = Store.key(d)
                            if let t = map[k] {
                                DayChip(text: arabicDigits(day), type: t, state: k < todayKey ? 0 : (k == todayKey ? 1 : 2), theme: theme, size: 30)
                            } else {
                                Text(arabicDigits(day)).font(.system(size: 12, weight: .bold)).foregroundColor(theme.secondary).frame(maxWidth: .infinity, minHeight: 30)
                            }
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 30)
                        }
                    }
                }
            }
            HStack(spacing: 6) {
                ForEach(Array("mano"), id: \.self) { t in
                    Text(typeLetter(t) + " " + typeLabel(t).replacingOccurrences(of: "وردية ", with: ""))
                        .font(.system(size: 10, weight: .bold)).foregroundColor(theme.futureText)
                        .padding(.horizontal, 8).padding(.vertical, 2)
                        .background(RoundedRectangle(cornerRadius: 6).fill(typeColor(t).opacity(0.28)))
                }
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetBackground(theme.bg)
    }
}

struct CalendarWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PetroCalendarWidget", provider: DayProvider()) { entry in
            CalendarWidgetView(entry: entry)
        }
        .configurationDisplayName("تقويم الورديات")
        .description("تقويم الشهر كاملاً بألوان ورديتك")
        .supportedFamilies([.systemLarge])
    }
}

@main
struct PetroWidgetBundle: WidgetBundle {
    var body: some Widget {
        ShiftWidget()
        CalendarWidget()
    }
}
