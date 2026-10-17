require 'xcodeproj'
root = File.expand_path('..', __dir__)
Dir.chdir(root)
p = Xcodeproj::Project.open('CodexUsage.xcodeproj')
app = p.targets.find { |t| t.name == 'CodexUsage' }
widget = p.targets.find { |t| t.name == 'CodexUsageWidget' }
plan = { 'Shared/TokensCIHistory.swift' => [app, widget], 'App/TokensCIAnalyticsView.swift' => [app] }
plan.each do |path, targets|
  ref = p.files.find { |f| f.path == path } || p.main_group.new_file(path)
  targets.each { |t| t.source_build_phase.add_file_reference(ref) unless t.source_build_phase.files_references.map(&:path).include?(path) }
end
p.build_configurations.each { |c| c.build_settings['CURRENT_PROJECT_VERSION'] = '37'; c.build_settings['MARKETING_VERSION'] = '4.0' }
p.targets.each { |t| t.build_configurations.each { |c| c.build_settings['CURRENT_PROJECT_VERSION'] = '37'; c.build_settings['MARKETING_VERSION'] = '4.0' } }
p.save
puts 'Added analytics memberships and set 4.0 (37); private settings preserved'
