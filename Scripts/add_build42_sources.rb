# Append source memberships only. Do not regenerate signing or identity settings.
require 'xcodeproj'
Dir.chdir(File.expand_path('..', __dir__))
p = Xcodeproj::Project.open('CodeGo.xcodeproj')
app = p.targets.find { |t| t.name == 'CodeGo' }
widget = p.targets.find { |t| t.name == 'CodeGoWidget' }
tests = p.targets.find { |t| t.name == 'CodeGoTests' }
plan = {}
%w[ProviderParsing CodexResetCredits OpenCodeGo CommandCode ProviderCardData].each { |n| plan["Shared/#{n}.swift"] = [app, widget] }
%w[OpenCodeGoPanel CommandCodePanel APIUsageAccountCard].each { |n| plan["App/#{n}.swift"] = [app] }
plan['Tests/Build42ProviderTests.swift'] = [tests]
plan.each do |path, targets|
  ref = p.files.find { |f| f.path == path } || p.main_group.new_file(path)
  targets.each { |t| t.source_build_phase.add_file_reference(ref) unless t.source_build_phase.files_references.map(&:path).include?(path) }
end
(p.build_configurations + p.targets.flat_map(&:build_configurations)).each do |c|
  c.build_settings['CURRENT_PROJECT_VERSION'] = '43'
  c.build_settings['MARKETING_VERSION'] = '4.6'
end
p.save
puts 'Added build42 memberships; version 4.5 (42); identity/signing settings preserved'
