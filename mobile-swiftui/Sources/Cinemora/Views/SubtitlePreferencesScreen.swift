import SwiftUI

struct SubtitlePreferencesEditor: View {
    @Binding var preferences: SubtitlePreferences
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: compact ? 12 : 16) {
            if !compact {
                SectionEyebrow(text: "SUBTITLE")
                AuroraGradientText(text: "Tùy chỉnh phụ đề", font: .auroraDisplay(26))
                Text("Thay đổi sẽ áp dụng ngay khi đang xem và được lưu trên thiết bị.")
                    .font(.auroraBody(11))
                    .foregroundStyle(Color.auroraTextSecondary)
                preview
                fullControls
            } else {
                // Fullscreen dùng cùng một bộ điều khiển với mục Lưu để mọi
                // thay đổi đều có hiệu lực và được phản ánh ngay trong player.
                fullControls
            }
        }
    }

    @ViewBuilder
    private var fullControls: some View {
        row(icon: "captions.bubble.fill", tint: .auroraViolet, title: "Hiển thị phụ đề", detail: "Bật hoặc tắt subtitle") {
            Toggle("", isOn: $preferences.enabled).labelsHidden().tint(Color.auroraViolet)
        }
        row(icon: "textformat", tint: .auroraSky, title: "Phông chữ", detail: preferences.fontName) {
            fontPicker
        }
        row(icon: "bold", tint: .auroraMint, title: "Chữ đậm", detail: "Tăng độ tương phản") {
            Toggle("", isOn: $preferences.bold).labelsHidden().tint(Color.auroraViolet)
        }
        sliderRow(icon: "textformat.size", tint: .auroraViolet, title: "Cỡ chữ", value: $preferences.fontSize, range: 12...34, suffix: "pt")
        sliderRow(icon: "arrow.down.to.line", tint: .auroraSky, title: "Khoảng cách phía dưới", value: $preferences.bottomSpacing, range: 20...180, suffix: "pt")
        alignmentRow
        colorRow(icon: "paintpalette.fill", tint: .auroraPink, title: "Màu chữ", value: preferences.textColorHex) {
            ColorPicker("", selection: colorBinding(for: \.textColorHex)).labelsHidden()
        }
        colorRow(icon: "scribble", tint: .auroraAmber, title: "Màu viền", value: preferences.outlineColorHex) {
            ColorPicker("", selection: colorBinding(for: \.outlineColorHex)).labelsHidden()
        }
        sliderRow(icon: "lineweight", tint: .auroraAmber, title: "Độ dày viền chữ", value: $preferences.outlineWidth, range: 0...5, suffix: "px")
        resetButton
    }

    private var alignmentRow: some View {
        row(icon: "text.aligncenter", tint: .auroraMint, title: "Căn chỉnh", detail: "Trái · giữa · phải") {
            Picker("Căn chỉnh", selection: $preferences.alignment) {
                ForEach(["Trái", "Giữa", "Phải"], id: \.self) { Text($0).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: compact ? 150 : 185)
        }
    }

    private var fontPicker: some View {
        Picker("Phông chữ", selection: $preferences.fontName) {
            ForEach(["System", "Avenir Next", "Georgia", "Menlo"], id: \.self) { Text($0).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .tint(Color.auroraViolet)
    }

    private func colorRow(icon: String, tint: Color, title: String, value: String, @ViewBuilder content: () -> some View) -> some View {
        row(icon: icon, tint: tint, title: title, detail: value, content: content)
    }

    private func colorBinding(for keyPath: WritableKeyPath<SubtitlePreferences, String>) -> Binding<Color> {
        Binding(
            get: { Color(hex: preferences[keyPath: keyPath]) },
            set: { preferences[keyPath: keyPath] = $0.hexString }
        )
    }

    private var resetButton: some View {
        AuroraGhostButton(title: "Đặt lại mặc định", icon: "arrow.counterclockwise", tint: .auroraViolet) {
            withAnimation(Motion.gentle) { preferences.reset() }
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("XEM TRƯỚC REALTIME")
                .font(.system(size: 8, weight: .black, design: .rounded))
                .tracking(1)
                .foregroundStyle(Color.auroraViolet)
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LinearGradient(colors: [Color.auroraSky.opacity(0.34), .black.opacity(0.92)], startPoint: .top, endPoint: .bottom))
                    .frame(height: 136)
                subtitleSample
                    // Thu nhỏ theo preview nhưng vẫn phản ánh đúng chiều
                    // hướng của khoảng cách phía dưới trong player.
                    .padding(.bottom, min(max(preferences.bottomSpacing * 0.55, 4), 100))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LinearGradient.auroraVeil, lineWidth: 0.8)
            }
        }
    }

    private var subtitleSample: some View {
        Text("Đây là phụ đề xem trước")
            .font(preferences.font)
            .foregroundStyle(preferences.textColor)
            .multilineTextAlignment(preferences.textAlignment)
            .frame(maxWidth: .infinity, alignment: preferences.frameAlignment)
            .padding(.horizontal, 12)
            .shadow(color: preferences.outlineColor, radius: 0, x: preferences.outlineWidth, y: 0)
            .shadow(color: preferences.outlineColor, radius: 0, x: -preferences.outlineWidth, y: 0)
            .shadow(color: preferences.outlineColor, radius: 0, x: 0, y: preferences.outlineWidth)
            .shadow(color: preferences.outlineColor, radius: 0, x: 0, y: -preferences.outlineWidth)
    }

    private func iconTile(_ icon: String, tint: Color) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(tint.opacity(0.16))
                .frame(width: compact ? 28 : 32, height: compact ? 28 : 32)
            Image(systemName: icon)
                .font(.system(size: compact ? 12 : 13, weight: .semibold))
                .foregroundStyle(tint)
        }
    }

    private func row<Content: View>(icon: String, tint: Color, title: String, detail: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 11) {
            iconTile(icon, tint: tint)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.auroraLabel(11, weight: .bold))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.auroraBody(8))
                    .foregroundStyle(Color.auroraTextTertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            content()
        }
    }

    private func sliderRow(icon: String, tint: Color, title: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 11) {
                iconTile(icon, tint: tint)
                Text(title)
                    .font(.auroraLabel(11, weight: .bold))
                    .foregroundStyle(.white)
                Spacer()
                Text("\(Int(value.wrappedValue))\(suffix)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.auroraViolet)
            }
            Slider(value: value, in: range, step: 1)
                .tint(Color.auroraViolet)
                .padding(.leading, compact ? 0 : 43)
        }
    }
}

struct SubtitlePreferencesScreen: View {
    @Environment(CinemaStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var preferences = SubtitlePreferences()

    var body: some View {
        ZStack {
            CinemaBackground()
            ScrollView {
                SubtitlePreferencesEditor(preferences: $preferences)
                    .padding(.horizontal, 20)
                    .padding(.top, 58)
                    .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .overlay(alignment: .topLeading) {
            AuroraBackButton(title: "Trở lại") { dismiss() }
                .padding(.leading, 20)
                .padding(.top, 8)
        }
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { preferences = store.playbackDefaults.subtitlePreferences }
        .onChange(of: preferences) { _, value in
            // Đợi SwiftUI hoàn tất transaction của Toggle/Slider rồi mới
            // cập nhật EnvironmentObject, tránh lỗi văng khi bật nền.
            DispatchQueue.main.async {
                store.playbackDefaults.subtitlePreferences = value
                store.savePlaybackDefaults()
            }
        }
    }
}
