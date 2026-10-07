import SwiftUI
import MessageUI

enum Feedback {
    /// Where Send Feedback goes: the developer, from the person's own Mail app. Clausage has no server.
    static let address = "counter@clausage.ai"
}

/// Mail's compose sheet.
struct MailComposer: UIViewControllerRepresentable {
    static var canSend: Bool { MFMailComposeViewController.canSendMail() }

    let to: String
    let subject: String
    let body: String
    let attachments: [UIImage]
    let done: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(done: done) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let vc = MFMailComposeViewController()
        vc.mailComposeDelegate = context.coordinator
        vc.setToRecipients([to])
        vc.setSubject(subject)
        vc.setMessageBody(body, isHTML: false)
        for (i, img) in attachments.enumerated() {
            if let data = img.pngData() { vc.addAttachmentData(data, mimeType: "image/png", fileName: "clausage-\(i + 1).png") }
        }
        return vc
    }

    func updateUIViewController(_ vc: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let done: (Bool) -> Void
        init(done: @escaping (Bool) -> Void) { self.done = done }
        func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
            done(result == .sent)
        }
    }
}
