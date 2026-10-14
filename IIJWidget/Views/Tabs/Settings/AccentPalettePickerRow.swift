import SwiftUI

struct AccentPalettePickerRow: View {
    let title: String
    @Binding var selection: AccentPalette
    @State private var isPresenting = false
    @ScaledMetric(relativeTo: .subheadline) private var paletteInfoWidth: CGFloat = 150

    var body: some View {
        Button {
            isPresenting = true
        } label: {
            HStack {
                Text(title)
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    AccentPaletteSwatch(palette: selection)
                        .frame(width: 48)
                    Text(selection.displayName)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                }
                .frame(width: paletteInfoWidth, alignment: .leading)
            }
        }
        .sheet(isPresented: $isPresenting) {
            NavigationStack {
                VStack {
                    Picker("", selection: $selection) {
                        ForEach(AccentPalette.allCases) { palette in
                            HStack(spacing: 10) {
                                AccentPaletteSwatch(palette: palette)
                                Text(palette.displayName)
                            }
                            .tag(palette)
                        }
                    }
                    .pickerStyle(.wheel)
                    .padding(.horizontal)
                }
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { isPresenting = false }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct AccentPaletteSwatch: View {
    let palette: AccentPalette

    var body: some View {
        RoundedRectangle(cornerRadius: 6)
            .fill(
                LinearGradient(
                    colors: palette.chartGradient,
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .frame(width: 32, height: 16)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
    }
}
