from pathlib import Path
import unittest
ROOT = Path(__file__).resolve().parents[1]
class Build43Contract(unittest.TestCase):
    def test_footer_and_identity_removal(self):
        views = (ROOT/'Shared/UsageViews.swift').read_text()
        self.assertIn('Text("重置积分 "', views)
        self.assertNotIn('showResetCredits', views)
        for folder in ['App', 'Shared', 'Widget']:
            for path in (ROOT/folder).glob('*.swift'):
                source = path.read_text()
                for forbidden in ['account'+'Label', 'showFull'+'AccountInWidget', 'snapshot'+'Label(', 'WidgetIdentity'+'Display', '重置额度']:
                    self.assertNotIn(forbidden, source, str(path))
    def test_name_and_version(self):
        project = (ROOT/'CodeGo.xcodeproj/project.pbxproj').read_text()
        self.assertIn('MARKETING_VERSION = 4.6;', project)
        self.assertIn('CURRENT_PROJECT_VERSION = 43;', project)
        self.assertFalse((ROOT/'CodexUsage.xcodeproj').exists())
if __name__ == '__main__': unittest.main()
