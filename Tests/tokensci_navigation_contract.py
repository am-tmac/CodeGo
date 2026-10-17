"""Build35: usage connection is a routed sheet, never an inline form."""
from pathlib import Path
import unittest
R = Path(__file__).resolve().parents[1]

class UsageConnectionContracts(unittest.TestCase):
    def test_usage_plus_routes_directly_before_refresh(self):
        app = (R/'App/CodexUsageApp.swift').read_text()
        header = app.split('var navigationBar: some View {', 1)[1].split('// MARK: - 状态', 1)[0]
        self.assertIn('if tab == .usage {', header)
        self.assertIn('Button { connect = .tokensCI }', header)
        self.assertLess(header.index('connect = .tokensCI'), header.index('await model.refresh()'))
        self.assertIn('accessibilityIdentifier("connectTokensCI")', header)
        self.assertEqual(app.count('.sheet(item: $connect)'), 1)
        self.assertIn('case .tokensCI: TokensCIConnectSheet(model: model)', app)
        self.assertIn('case tokensCI', (R/'App/ConnectViews.swift').read_text())

    def test_inline_page_only_has_cards_and_empty_connect_action(self):
        panel = (R/'App/TokensCIPanel.swift').read_text()
        self.assertIn('struct TokensCIConnectSheet: View {', panel)
        display, form = panel.split('struct TokensCIConnectSheet: View {', 1)
        self.assertNotIn('TextField(', display)
        self.assertNotIn('SecureField(', display)
        self.assertNotIn('@State private var token', display)
        self.assertIn('if model.tokensCIIDs.isEmpty {', display)
        self.assertIn('Button("连接 tokens.ci", action: onConnect)', display)
        self.assertIn('model.refreshErrors[.tokensCI(name)]', display)
        self.assertIn('TokensCIService.shared.remove(name)', display)
        self.assertIn('SecureField(', form)
        self.assertIn('.onDisappear { clearCredentials() }', form)
        self.assertIn('if phase != .active { clearCredentials(); dismiss() }', form)
        self.assertIn('username = ""; token = ""; consent = false', form)

if __name__ == '__main__': unittest.main()
