import SwiftUI

struct MessageBubbleView: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 6) {
                // Image attachment (if any)
                if let imageData = message.imageData,
                   let uiImage = UIImage(data: imageData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 220, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }

                // Text content
                if !message.content.isEmpty {
                    Group {
                        if message.role == .assistant {
                            MarkdownContentView(message.content, foregroundColor: Color(.label))
                                .font(.system(size: 17))
                                .textSelection(.enabled)
                        } else {
                            Text(message.content)
                                .font(.system(size: 17, weight: .regular, design: .default))
                                .foregroundStyle(.white)
                        }
                    }
                    .padding(message.role == .user ? 12 : 0)
                    .background(
                        message.role == .user
                            ? RoundedRectangle(cornerRadius: 18)
                                .fill(Color.blue)
                            : nil
                    )
                }
            }
            .contextMenu {
                Button("Copy") {
                    UIPasteboard.general.string = message.content
                }
            }

            if message.role == .assistant {
                Spacer(minLength: 0)
            }
        }
    }
}
