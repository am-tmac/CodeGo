import pathlib
import unittest
R = pathlib.Path(__file__).resolve().parents[1]
class TokensCIContracts(unittest.TestCase):
    def test_usage_tab_between_status_and_settings(self):
        app = (R/'App/CodeGoApp.swift').read_text()
        self.assertIn('case status, usage, settings', app)
        self.assertEqual(app.count('TokensCIPanel(model: model, onConnect:'), 1)
        self.assertLess(app.index('.tag(AppTab.status)'), app.index('.tag(AppTab.usage)'))
        self.assertLess(app.index('.tag(AppTab.usage)'), app.index('.tag(AppTab.settings)'))
        self.assertNotIn('TokensCIPanel', app[app.index('@ViewBuilder var settingsSections'):])
    def test_shared_model_and_card_errors(self):
        panel = (R/'App/TokensCIPanel.swift').read_text()
        self.assertNotIn('@State private var profiles', panel)
        self.assertNotIn('@State private var snapshots', panel)
        self.assertIn('model.refreshErrors[.tokensCI(name)]', panel)
        self.assertIn('.fixedSize(horizontal: false, vertical: true)', panel)
        self.assertIn('model.refresh(target: .tokensCI(name))', panel)
    def test_widget_padding_theme_and_honest_cache_dispatch(self):
        widget = (R/'Widget/CodeGoWidget.swift').read_text()
        self.assertNotIn('provider != "tokensci"', widget[:widget.index('struct DashboardWidgetView')])
        self.assertIn('provider == "tokensci" ? id.flatMap { TokensCIStore.snapshot($0) } : nil', widget)
        self.assertIn('struct TokensCIWidgetRoot', widget)
        self.assertIn('.padding(16)', widget[widget.index('struct TokensCIWidgetView'):])
        self.assertIn('scheme: scheme', widget[widget.index('struct TokensCIWidgetRoot'):])
        self.assertIn('case "tokensci": _ = try await TokensCIService.shared.refresh(username: id, widget: true)',
                      (R/'Shared/WidgetRefreshLogic.swift').read_text())
    def test_versions(self):
        project = (R/'CodeGo.xcodeproj/project.pbxproj').read_text()
        # 6.3 / 51: Nowdex widget presentation; refresh semantics are unchanged.
        self.assertIn('MARKETING_VERSION = 6.3;', project)
        self.assertIn('CURRENT_PROJECT_VERSION = 51;', project)
if __name__ == '__main__': unittest.main()
