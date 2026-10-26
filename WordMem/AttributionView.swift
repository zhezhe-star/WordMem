import SwiftUI

struct AttributionView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Open English WordNet")
                        .font(.headline)
                    Text("""
                        Copyright (c) 2019-present, The Open English WordNet Team. \
                        Licensed under Creative Commons Attribution 4.0 International (CC BY 4.0).
                        """)
                        .font(.footnote)
                    Link("creativecommons.org/licenses/by/4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                        .font(.footnote)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Princeton WordNet")
                        .font(.headline)
                    Text("""
                        Princeton University "About WordNet." WordNet. Princeton University. 2010. \
                        This application is not affiliated with, endorsed by, or sponsored by \
                        Princeton University. Princeton University and Princeton are not used \
                        in advertising or publicity for this application.
                        """)
                        .font(.footnote)
                    Link("wordnet.princeton.edu", destination: URL(string: "https://wordnet.princeton.edu/")!)
                        .font(.footnote)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("WordNetKit")
                        .font(.headline)
                    Text("MIT License. Copyright (c) 2026 Adrian Corscadden.")
                        .font(.footnote)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
        .navigationTitle("第三方词典授权")
        .navigationBarTitleDisplayMode(.inline)
    }
}
