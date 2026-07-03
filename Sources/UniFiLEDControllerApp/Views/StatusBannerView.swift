import SwiftUI

struct AppStatusBanner: Equatable {
    enum Kind {
        case success
        case warning
        case error
    }

    let kind: Kind
    let message: String
}

struct StatusBannerView: View {
    let banner: AppStatusBanner
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)

            Text(banner.message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            Button(action: dismiss) {
                Image(systemName: "xmark")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var iconName: String {
        switch banner.kind {
        case .success:
            return "checkmark.circle.fill"
        case .warning:
            return "exclamationmark.triangle.fill"
        case .error:
            return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch banner.kind {
        case .success:
            return .green
        case .warning:
            return .orange
        case .error:
            return .red
        }
    }

    private var backgroundColor: Color {
        switch banner.kind {
        case .success:
            return Color.green.opacity(0.08)
        case .warning:
            return Color.orange.opacity(0.08)
        case .error:
            return Color.red.opacity(0.08)
        }
    }
}
