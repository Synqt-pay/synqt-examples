import SynqtSDK
#if canImport(SynqtSDKCard)
import SynqtSDKCard // the card add-on, linked only by SynqtDemoCard.xcodeproj
#endif
import SwiftUI
import UIKit

// The Payment Web App rejects non-https returnUrls, so PaymentWebView catches this one before it loads.
let returnURL = "https://example.com/synqt/return"
let callbackURL = "https://example.com/synqt/callback" // nothing listens; fine for testing

@main
struct SynqtDemoApp: App {
    init() {
        #if canImport(SynqtSDKCard)
        SynqtCard.enable() // adds CARD to the sheet, as a PCI DSS compliant merchant's app would when it starts
        #endif
    }

    var body: some Scene {
        WindowGroup { DemoView() }
    }
}

/**
 Test screen. Fields are filled by scripts/sandbox-token.sh (Paste from script), or by hand. For merchants without an
 RSA key yet, a token can be minted here from the (deprecated) Merchant secret key.
 Plain system controls on purpose, so the SDK's own payment sheet styling stands out.
 */
struct DemoView: View {
    @State private var environment = Synqt.Environment.sandbox
    @State private var fields: [String: String] = ["currencyCode": "ZAR", "amount": "100.00"]
    @State private var secret = ""
    // Filled from the payin's own options; empty until they are fetched.
    @State private var methods: [PaymentOption] = []
    @State private var method = ""
    @State private var output = ""
    @State private var webURL: URL?
    @State private var pill: (text: String, color: Color) = ("No payin", .gray)
    // The payin ID a payment was sent for, or the Payment Web App shown for; SYNQT has nothing to report before that.
    @State private var opened = ""

    // Field key to label.
    private let keys = [
        ("merchantCode", "Merchant code"), ("idPayin", "Payin ID"), ("token", "Token"), ("amount", "Amount"),
        ("currencyCode", "Currency"), ("emailAddress", "Customer email"), ("firstName", "Customer first name"),
        ("lastName", "Customer last name"),
    ]

    var body: some View {
        NavigationView {
            Form {
                Picker("Environment", selection: $environment) {
                    ForEach(Synqt.Environment.allCases, id: \.self) { Text($0.rawValue.uppercased()).tag($0) }
                }
                .pickerStyle(.segmented)
                Section {
                    ForEach(keys, id: \.0) { key, label in
                        TextField(label, text: Binding(get: { fields[key] ?? "" }, set: { fields[key] = $0 }))
                            .textInputAutocapitalization(.never)
                            .disableAutocorrection(true)
                    }
                    SecureField("Merchant secret key (only without a private key)", text: $secret)
                }
                Section {
                    action("Paste from script") { pasteFromScript() }
                    action("Get token with secret key") { try await tokenFromSecret() }
                    action("Open Payment Web App") { try await payWithPaymentApp() }
                    action("Available payment options") { try await loadOptions() }
                    action("Payment operators") { try await paymentOperators() }
                }
                Section("Direct API payment method") {
                    Picker("Method", selection: $method) {
                        ForEach(methods, id: \.code) { Text($0.name ?? $0.code).tag($0.code) }
                    }
                    action("Enter details and pay (SDK sheet)") { try await payWithSheet() }
                    action("Get status") { "\(try await payin().status())" }
                }
                Section { Text(output).font(.system(.footnote, design: .monospaced)).textSelection(.enabled) }
            }
            .navigationTitle("Synqt Demo")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Text(pill.text).font(.caption.weight(.semibold)).foregroundColor(.white)
                        .padding(.horizontal, 10).padding(.vertical, 4).background(Capsule().fill(pill.color))
                        .fixedSize()
                        .accessibilityLabel("Payment status: \(pill.text)")
                }
            }
        }
        // Restarts whenever the payin on screen changes.
        .task(id: [environment.rawValue, value("idPayin"), value("token"), opened]) { await followStatus() }
        .task {
            // For screenshots without a token: `SIMCTL_CHILD_SYNQT_DEMO_SHEET=CAPITEC_PAY xcrun simctl launch …` opens
            // the sheet at once. Paying then fails with SYNQT's 401, shown in the sheet.
            guard let code = ProcessInfo.processInfo.environment["SYNQT_DEMO_SHEET"] else { return }
            fields["idPayin"] = "preview-1"
            fields["token"] = "preview"
            method = code
            try? await Task.sleep(nanoseconds: 500_000_000) // let the window settle before presenting
            run { try await payWithSheet() }
        }
        // A direct-API GET redirect (bank login and the like); the Payment Web App uses the SDK's own presentPaymentApp.
        .sheet(item: $webURL) { url in
            PaymentWebView(url: url) {
                webURL = nil
                run { "Back from the redirect.\n\n" + (try await latestStatus(payin())) }
            }
        }
    }

    private func payWithSheet() async throws -> String {
        guard !method.isEmpty else { throw DemoError("No payment method yet. Tap \"Available payment options\" first.") }
        let payin = try payin()
        guard let top = topViewController() else { throw DemoError("No view controller to present from") }
        guard let sheetResult = try await payin.presentPaymentSheet(from: top, paymentMethodCode: method, prefill: prefill(),
                                                                    onPresented: { output = "Payment sheet on screen." },
                                                                    onPaymentStarted: {
                                                                        opened = payin.id
                                                                        output = "Payment sent to SYNQT."
                                                                    }) else {
            return "Payment sheet closed without paying.\n\n\(await latestStatus(payin))"
        }
        let result: String
        switch sheetResult {
        case let .redirect(httpMethod, url, formData):
            if httpMethod == "GET" { webURL = URL(string: url) }
            result = "Redirect \(httpMethod) \(url)\n\(formData)"
        case let .instructions(paymentMethod, _):
            result = "\(paymentMethod)"
        }
        return "\(await latestStatus(payin))\n\n\(result)"
    }

    private func payWithPaymentApp() async throws -> String {
        let payin = try payin()
        guard let top = topViewController() else { throw DemoError("No view controller to present from") }
        // The Payment Web App has no first or last name parameter; accountName takes the full name.
        let name = [value("firstName"), value("lastName")].filter { !$0.isEmpty }.joined(separator: " ")
        let email = value("emailAddress")
        // KeyValuePairs can only be built from a literal, so each empty value is left out case by case.
        let details: KeyValuePairs<String, String> = switch (email.isEmpty, name.isEmpty) {
        case (false, false): ["emailAddress": email, "accountName": name]
        case (false, true): ["emailAddress": email]
        case (true, false): ["accountName": name]
        case (true, true): [:]
        }
        // Opens on the picked method, if any; the payer can still choose another.
        let result = await payin.presentPaymentApp(from: top, merchantCode: value("merchantCode"),
                                                   paymentMethodCode: method.isEmpty ? nil : method,
                                                   prefill: details,
                                                   onPresented: {
                                                       opened = payin.id
                                                       output = "Payment Web App on screen."
                                                   })
        let how = result == .closed ? "Payment Web App closed by the payer." : "Payment Web App returned to the app."
        return "\(how)\n\n\(await latestStatus(payin))"
    }

    /// Keeps the status pill current: every 5 seconds until the status can no longer change.
    private func followStatus() async {
        guard !value("idPayin").isEmpty, !value("token").isEmpty, let payin = try? payin() else {
            pill = ("No payin", .gray)
            return
        }
        guard opened == payin.id else {
            pill = ("Not started", .gray)
            return
        }
        while !Task.isCancelled {
            do {
                let status = try await payin.status().status
                let colors: [PayinStatus.Status: Color] = [.success: .green, .failed: .red, .refused: .red, .processing: .orange]
                pill = (status.rawValue, colors[status] ?? .gray)
                if status.isFinal { return }
            } catch let error as SynqtAPIError {
                // SYNQT answers 410 Gone for a payin ID it doesn't have: the Payment Web App before Pay, or a refused payment.
                pill = error.httpCode == 410 ? ("Not started", .gray) : ("HTTP \(error.httpCode)", .gray)
            } catch {
                if Task.isCancelled { return }
                pill = ("Offline", .gray)
            }
            try? await Task.sleep(nanoseconds: 5_000_000_000)
        }
    }

    /// Where the payin stands once the sheet closes. For display only: an order is paid when the backend says so.
    private func latestStatus(_ payin: Payin) async -> String {
        do {
            let payinStatus = try await payin.status()
            return "Status: \(payinStatus.status.rawValue)" + (payinStatus.failureReason.map { "\n\($0.payerMessage) (\($0.code))" } ?? "")
        } catch let error as SynqtAPIError {
            return "Status unavailable: HTTP \(error.httpCode) " + error.errors.map(\.code).joined(separator: ", ")
        } catch {
            return "Status unavailable: could not reach SYNQT"
        }
    }

    /// The order being tested, from the fields on screen.
    private func payin() throws -> Payin {
        guard let amount = Decimal(string: value("amount"), locale: Locale(identifier: "en_US_POSIX")) else {
            throw DemoError("Amount must be a number, for example 100.00")
        }
        return try Synqt(environment).payin(token: value("token"), payinID: value("idPayin"),
                                            money: Money(amount: amount, currencyCode: value("currencyCode")),
                                            returnURL: returnURL, callbackURL: callbackURL)
    }

    /// What the SDK sheet fills in for the payer, keyed by field path.
    private func prefill() -> [String: String] {
        ["emailAddress": value("emailAddress"), "customerName.firstName": value("firstName"), "customerName.lastName": value("lastName")]
            .filter { !$0.value.isEmpty }
    }

    /// Fills the method picker with what SYNQT offers for this payin. A nil name means the SDK sheet can't show it.
    private func loadOptions() async throws -> String {
        let options = try await payin().availablePaymentOptions()
        methods = options.filter { $0.name != nil }
        method = methods.first?.code ?? ""
        return "\(methods.count) of \(options.count) offered methods can use the SDK sheet\n\n" + options.map { "\($0)" }.joined(separator: "\n")
    }

    /// Needs a token with GET /payment-operators: the secret-key button asks for it, a PAYIN_CREATE token does not have it.
    private func paymentOperators() async throws -> String {
        do {
            let operators = try await Synqt(environment).paymentOperators(token: value("token"))
            return "\(operators.count) payment operators\n\n" + operators.map { op in
                let providers = op.externalProviders.map { "\($0.code) (\($0.name))" }.joined(separator: ", ")
                return "\(op.code)  \(op.name)" + (providers.isEmpty ? "" : "\n    providers: \(providers)")
            }.joined(separator: "\n")
        } catch let error as SynqtAPIError where error.httpCode == 403 {
            return "HTTP 403: this token cannot list payment operators. Use \"Get token with secret key\", which asks for GET /payment-operators."
        }
    }

    /// Same request as the WordPress plugin's secret fallback: POST /auth-tokens scoped to one payin, plus GET /payment-operators.
    /// Kept out of the SDK on purpose: a merchant secret must never ship in a real app.
    private func tokenFromSecret() async throws -> String {
        // A payin ID is used once, so every token gets a fresh one; reusing it would return the earlier attempt.
        let id = "test-\(Int(Date().timeIntervalSince1970 * 1000))"
        fields["idPayin"] = id
        let money = try payin().money
        let body: [String: Any] = [
            "merchantCode": value("merchantCode"), "secret": secret, "validitySecs": 1800,
            "operations": ["POST /payins/!availablePaymentOptions", "POST /payins/\(id)", "GET /payins/\(id)", "GET /merchant-info", "GET /payment-operators"],
            "money": ["amount": money.amount as NSDecimalNumber, "currencyCode": money.currencyCode],
        ]
        var request = URLRequest(url: URL(string: environment.apiBaseURL + "/auth-tokens")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2", forHTTPHeaderField: "X-API-Version")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200...299).contains(code), let token = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["token"] as? String else {
            throw DemoError("Token request failed: HTTP \(code)\n\(String(decoding: data, as: UTF8.self))") // test screen only
        }
        fields["token"] = token
        let options = (try? await loadOptions()) ?? "Could not load payment options"
        return "Token issued for \(id) on \(environment.rawValue)\n\n\(options)"
    }

    /// scripts/sandbox-token.sh copies its values as JSON; the Simulator shares the Mac's clipboard.
    private func pasteFromScript() -> String {
        guard let data = UIPasteboard.general.string?.data(using: .utf8),
              let values = (try? JSONSerialization.jsonObject(with: data)) as? [String: String] else {
            return "The clipboard holds no values from scripts/sandbox-token.sh."
        }
        if let env = values["environment"].flatMap(Synqt.Environment.init(rawValue:)) { environment = env }
        for (key, value) in values where key != "environment" { fields[key] = value }
        return "Pasted \(values.keys.sorted().joined(separator: ", "))"
    }

    private func value(_ key: String) -> String { (fields[key] ?? "").trimmingCharacters(in: .whitespaces) }

    private func action(_ label: String, _ block: @escaping () async throws -> String) -> some View {
        Button(label) { run(block) }
    }

    private func run(_ block: @escaping () async throws -> String) {
        output = "…"
        Task {
            do {
                output = try await block()
            } catch let error as SynqtAPIError {
                output = "HTTP \(error.httpCode)\n" + error.errors.map { "\($0.code) \($0.field ?? "") \($0.description ?? "")" }.joined(separator: "\n")
            } catch {
                output = error.localizedDescription
            }
        }
    }
}

struct DemoError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

/// The topmost view controller, to present the SDK's sheet over.
@MainActor
func topViewController() -> UIViewController? {
    let window = UIApplication.shared.connectedScenes.compactMap { ($0 as? UIWindowScene)?.keyWindow }.first
    var top = window?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
}
