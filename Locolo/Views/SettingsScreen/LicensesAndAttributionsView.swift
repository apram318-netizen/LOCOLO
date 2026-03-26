//
//  LicensesAndAttributionsView.swift
//  Locolo
//
//  Created by Apramjot Singh on 16/11/2025.
//



import SwiftUI

struct LicensesAndAttributionsView: View {
    @State private var licenseText: String = "Loading..."

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text(licenseText)
                    .font(.system(.body, design: .monospaced)) // Easier to read legal text
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
        .navigationTitle("Licenses & Attributions")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            loadLicenseText()
        }
    }

    private func loadLicenseText() {
        guard let url = Bundle.main.url(forResource: "LicensesAndAttributions", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            licenseText = "Failed to load licenses text."
            return
        }
        licenseText = text
    }
}
