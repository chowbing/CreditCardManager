import SwiftUI

// MARK: - 卡片颜色选择器
/// 预设色板网格，选中项带强调色描边。
/// 供「编辑卡片」表单与卡片列表的快速改色面板共用。
struct CardColorPicker: View {
    @Binding var selected: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(CardPalette.colors, id: \.self) { hex in
                Circle()
                    .fill(Color(hex: hex))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .strokeBorder(Color.accentColor, lineWidth: selected == hex ? 3 : 0)
                    )
                    .overlay(
                        // 选中时在色块中心显示对勾，弱光环境下也能看清
                        Group {
                            if selected == hex {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.white)
                                    .shadow(radius: 1)
                            }
                        }
                    )
                    .contentShape(Circle())
                    .onTapGesture { selected = hex }
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 列表行内可点击的色块（点击进入快速改色）
struct CardColorChip: View {
    let hex: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 7)
                .fill(Color(hex: hex))
                .frame(width: 34, height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "paintpalette.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .shadow(radius: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("修改卡片颜色")
    }
}
