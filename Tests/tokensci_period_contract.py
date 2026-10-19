"""Same reported calendar-day semantics in App/widget; no claimed intra-day conversion."""
import pathlib
import unittest
R = pathlib.Path(__file__).resolve().parents[1]
class PeriodContracts(unittest.TestCase):
    def test_same_day_rows_and_clear_labels(self):
        source = (R/'Shared/TokensCI.swift').read_text()
        self.assertIn('for day in todayContributions', source)
        panel = (R/'App/TokensCIPanel.swift').read_text() + (R/'App/TokensCIAnalyticsView.swift').read_text()
        widget = (R/'Widget/CodeGoWidget.swift').read_text()
        for text in (panel, widget):
            self.assertIn('client.displayName', text)
            self.assertIn('client.topModel?.cost', text)
            self.assertIn('value.todayTokens', text)
            self.assertIn('累计', text)
            self.assertNotIn('今日 Token · UTC', text)
        self.assertIn('上报日', panel)
        self.assertIn('periodLabel', widget)
        self.assertNotIn('max(0.04, share)', widget)
    def test_explicit_supported_route(self):
        source = (R/'Shared/TokensCI.swift').read_text()
        self.assertIn('period=all', source)
        self.assertNotIn('period=daily', source)
if __name__ == '__main__': unittest.main()
