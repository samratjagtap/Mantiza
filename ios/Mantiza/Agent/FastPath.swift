import Contacts
import Foundation

/// Shortcuts that skip tapping (PRD 4.5): open the target app at the right place with a URL while Mantiza is still
/// in front, so the agent only does what is left (for a message: check it and tap Send, with approval).
enum FastPath {
    struct Match: Equatable {
        var name: String
        var phones: [String]
    }

    /// A URL that starts the task further along, or nil.
    static func url(for s: Subtask, contacts: [Match]) -> (url: URL, note: String)? {
        let app = (s.app ?? "").lowercased()
        let text = s.inputs.first ?? ""
        switch app {
        case "messages":
            // Exactly one contact with a phone number; otherwise the agent searches in Messages itself.
            guard s.contact != nil, contacts.count == 1, let phone = contacts[0].phones.first,
                  let url = smsURL(phone: phone, body: text) else { return nil }
            return (url, "Opened Messages to \(contacts[0].name)" + (text.isEmpty ? "" : " with the message already typed"))
        case "maps":
            guard !text.isEmpty, let url = URL(string: "maps://?q=" + encode(text)) else { return nil }
            return (url, "Opened Maps searching for \(text)")
        case "shortcuts":
            guard !text.isEmpty, let url = URL(string: "shortcuts://run-shortcut?name=" + encode(text)) else { return nil }
            return (url, "Ran the shortcut \(text)")
        default:
            return nil
        }
    }

    static func smsURL(phone: String, body: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        guard !digits.isEmpty else { return nil }
        return URL(string: "sms:\(digits)" + (body.isEmpty ? "" : "&body=" + encode(body)))
    }

    static func encode(_ s: String) -> String {
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=+?#")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }

    /// Contacts whose name matches (asks for Contacts access the first time).
    static func findContacts(_ name: String) async -> [Match] {
        let store = CNContactStore()
        guard (try? await store.requestAccess(for: .contacts)) == true else { return [] }
        let keys = [CNContactGivenNameKey, CNContactFamilyNameKey, CNContactPhoneNumbersKey] as [CNKeyDescriptor]
        let found = (try? store.unifiedContacts(matching: CNContact.predicateForContacts(matchingName: name), keysToFetch: keys)) ?? []
        return found.map { c in
            Match(name: [c.givenName, c.familyName].filter { !$0.isEmpty }.joined(separator: " "),
                  phones: c.phoneNumbers.map { $0.value.stringValue })
        }.filter { !$0.phones.isEmpty }
    }
}
