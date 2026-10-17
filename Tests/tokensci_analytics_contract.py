"""Approved build37 App analytics: real history, private storage, no widget redesign."""
from pathlib import Path
import unittest, json, hashlib
R=Path(__file__).resolve().parents[1]
class AnalyticsContracts(unittest.TestCase):
 def test_native_app_charts_and_section_order(self):
  s=(R/'App/TokensCIAnalyticsView.swift').read_text()
  self.assertIn('import Charts',s)
  names=['hero.id','activity.id','tiles.id','usageChart.id','rankings.id','composition.id','habits.id']
  self.assertEqual(sorted(names,key=s.index),names)
  for marker in ['Picker("图表单位"','Picker("统计范围"','selectedDay = key','allModels.toggle()','allProviders.toggle()','缓存读取占比','非请求命中率']:
   self.assertIn(marker,s)
  self.assertIn('.chartLegend(.hidden)',s)
  self.assertIn('其他',s)
  project=(R/'CodexUsage.xcodeproj/project.pbxproj').read_text()
  # One PBXBuildFile and one Sources entry only => App membership, not Widget.
  self.assertEqual(project.count('TokensCIAnalyticsView.swift in Sources'),2)
 def test_history_privacy_and_widget_bytes(self):
  s=(R/'Shared/TokensCIHistory.swift').read_text()
  self.assertIn('.applicationSupportDirectory',s)
  self.assertNotIn('appendingPathComponent(username)',s)
  self.assertIn('guard !SharedStorage.isWidget',s)
  shared=(R/'Shared/TokensCI.swift').read_text()
  self.assertIn('minimal.history = nil',shared)
  baseline=json.loads((R/'Logs/build37-widget-baseline.json').read_text())
  for name,digest in baseline.items():self.assertEqual(hashlib.sha256((R/name).read_bytes()).hexdigest(),digest,name)
 def test_production_no_preview(self):
  for d in ['App','Shared','Widget']:
   for p in (R/d).glob('*.swift'):
    for bad in ['PREVIEW_SECTION','tkr_fixture','Alice39s','Build37PreviewRoot']:self.assertNotIn(bad,p.read_text(),str(p))
if __name__=='__main__':unittest.main()
