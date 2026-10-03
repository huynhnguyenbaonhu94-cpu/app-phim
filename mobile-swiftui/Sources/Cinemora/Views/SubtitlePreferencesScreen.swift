import SwiftUI

struct SubtitlePreferencesEditor: View {
    @Binding var preferences: SubtitlePreferences
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 11 : 15) {
            if !compact {
                SectionEyebrow(text: "SUBTITLE")
                Text("Tùy chỉnh phụ đề")
                    .font(.system(size: 25, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                Text("Thay đổi sẽ áp dụng ngay khi đang xem và được lưu trên thiết bị.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.white.opacity(0.58))
                preview
                fullControls
            } else {
                compactControls
            }
        }
    }

    @ViewBuilder
    private var fullControls: some View {
        row(title: "Hiển thị phụ đề", detail: "Bật hoặc tắt subtitle") {
            Toggle("", isOn: $preferences.enabled).labelsHidden().tint(Color.cinemaAccent)
        }
        row(title: "Phông chữ", detail: preferences.fontName) {
            fontPicker
        }
        row(title: "Chữ đậm", detail: "Tăng độ tương phản") {
            Toggle("", isOn: $preferences.bold).labelsHidden().tint(Color.cinemaAccent)
        }
        sliderRow(title: "Cỡ chữ", value: $preferences.fontSize, range: 12...34, suffix: "pt")
        sliderRow(title: "Khoảng cách phía dưới", value: $preferences.bottomSpacing, range: 20...180, suffix: "pt")
        alignmentRow
        colorRow(title: "Màu chữ", value: preferences.textColorHex) {
            ColorPicker("", selection: colorBinding(for: \.textColorHex)).labelsHidden()
        }
        colorRow(title: "Màu viền", value: preferences.outlineColorHex) {
            ColorPicker("", selection: colorBinding(for: \.outlineColorHex)).labelsHidden()
        }
        sliderRow(title: "Độ dày viền chữ", value: $preferences.outlineWidth, range: 0...5, suffix: "px")
        row(title: "Song ngữ", detail: "Hiển thị thêm dòng song ngữ nếu admin đã cung cấp") {
            Toggle("", isOn: $preferences.bilingual).labelsHidden().tint(Color.cinemaAccent)
        }
        resetButton
    }

    @ViewBuilder
    private var compactControls: some View {
        // Keep the first control visible in the player popover, matching the
        // reference layout instead of nesting a tall form inside the panel.
        alignmentRow
        row(title: "Phông chữ", detail: preferences.fontName) { fontPicker }
        sliderRow(title: "Cỡ chữ", value: $preferences.fontSize, range: 12...34, suffix: "pt")
        row(title: "Chữ đậm", detail: "Tăng độ tương phản") {
            Toggle("", isOn: $preferences.bold).labelsHidden().tint(Color.cinemaAccent)
        }
        HStack(spacing: 10) {
            row(title: "Hiển thị phụ đề", detail: preferences.enabled ? "Đang bật" : "Đang tắt") {
                Toggle("", isOn: $preferences.enabled).labelsHidden().tint(Color.cinemaAccent)
            }
            row(title: "Song ngữ", detail: preferences.bilingual ? "Đang bật" : "Đang tắt") {
                Toggle("", isOn: $preferences.bilingual).labelsHidden().tint(Color.cinemaAccent)
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var alignmentRow: some View {
        row(title: "Căn chỉnh", detail: "Trái · giữa · phải") {
            Picker("Căn chỉnh", selection: $preferences.alignment) {
                ForEach(["Trái", "Giữa", "Phải"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: compact ? 145 : 180)
        }
    }

    private var fontPicker: some View {
        Picker("Phông chữ", selection: $preferences.fontName) {
            ForEach(["System", "Avenir Next", "Georgia", "Menlo"], id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Color.cinemaAccent)
    }

    private func colorRow(title: String, value: String, @ViewBuilder content: () -> some View) -> some View {
        row(title: title, detail: value, content: content)
    }

    private func colorBinding(for keyPath: WritableKeyPath<SubtitlePreferences, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: preferences[keyPath: keyPath]) },
            set: { preferences[keyPath: keyPath] = $0.hexString }
        )
    }

    private var resetButton: some View {
        Button { preferences.reset() } label: {
            Label("Đặt lại mặc định", systemImage: "arrow.counterclockwise")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(Color.cinemaAccent)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.cinemaAccent.opacity(0.1), in: RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("XEM TRƯỚC REALTIME")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.cinemaAccent)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 14)
                    .fill(LinearGradient(colors: [.gray.opacity(0.45), .black.opacity(0.9)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 128)
                subtitleSample.padding(.bottom, 12)
            }
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
    }

    private var subtitleSample: some View {
        VStack(spacing: 3) {
            Text("Đây là phụ đề xem trước")
            if preferences.bilingual { Text("This is a bilingual preview") }
        }
        .font(preferences.font)
        .foregroundStyle(preferences.textColor)
        .multilineTextAlignment(preferences.textAlignment)
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 12)
        .shadow(color: preferences.outlineColor, radius: 0, x: preferences.outlineWidth, y: 0)
        .shadow(color: preferences.outlineColor, radius: 0, x: -preferences.outlineWidth, y: 0)
        .shadow(color: preferences.outlineColor, radius: 0, x: 0, y: preferences.outlineWidth)
        .shadow(color: preferences.outlineColor, radius: 0, x: 0, y: -preferences.outlineWidth)
    }

    private func row<Content: View>(title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: compact ? 11 : 11, weight: .bold)).foregroundStyle(.white)
                Text(detail).font(.system(size: compact ? 8 : 8)).foregroundStyle(.white.opacity(0.48)).lineLimit(1)
            }
            Spacer(minLength: 4)
            content()
        }
    }

    private func sliderRow(title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title).font(.system(size: 11, weight: .bold)).foregroundStyle(.white)
                Spacer()
                Text("\(Int(value.wrappedValue))\(suffix)")
                    .font(.system(size: compact ? 10 : 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.cinemaAccent)
            }
            Slider(value: value, in: range, step: 1).tint(Color.cinemaAccent)
        }
    }
}

struct SubtitlePreferencesScreen: View {
    @EnvironmentObject private var store: CinemaStore
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = SubtitlePreferences()

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                SubtitlePreferencesEditor(preferences: $preferences)
                    .padding(.horizontal, 20)
                    .padding(.top, 58)
                    .padding(.bottom, 42)
            }
        }
        .overlay(alignment: .topLeading) {
            Button { dismiss() } label: {
                Label("Trở lại", systemImage: "chevron.left")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.black.opacity(0.5), in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.leading, 20)
            .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { preferences = store.playbackDefaults.subtitlePreferences }
        .onChange(of: preferences) { _, value in
            store.playbackDefaults.subtitlePreferences = value
            store.savePlaybackDefaults()
        }
    }
}
