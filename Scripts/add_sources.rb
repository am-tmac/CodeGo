# Adds new sources to the existing project without regenerating it (the generator would
# rewrite signing settings). Mirrors how generate_project.rb lays out file references:
# Shared/*.swift compiles into App + Widget, App/*.swift into the App only.
require 'xcodeproj'
root = File.expand_path('..', __dir__)
Dir.chdir(root)
p = Xcodeproj::Project.open('CodeGo.xcodeproj')
app = p.targets.find { |t| t.name == 'CodeGo' }
widget = p.targets.find { |t| t.name == 'CodeGoWidget' }
tests = p.targets.find { |t| t.name == 'CodeGoTests' }
plan = { 'Shared/KeychainCapabilityResolver.swift' => [app, widget], 'Tests/KeychainCapabilityResolverTests.swift' => [tests], 'Shared/IncomingIPACleaner.swift' => [app, widget], 'App/IncomingIPACleanupView.swift' => [app], 'Shared/StorageDiagnosticsScanner.swift' => [app, widget], 'App/StorageDiagnosticsView.swift' => [app], 'Tests/CacheMaintenanceTests.swift' => [tests], 'Shared/CacheMaintenance.swift' => [app, widget], 'App/CacheSettingsCard.swift' => [app], 'Shared/CardOrder.swift' => [app, widget], 'Shared/Antigravity.swift' => [app, widget], 'App/ExtraProviderPanels.swift' => [app], 'App/AntigravityLogin.swift' => [app], 'Shared/OllamaCloud.swift' => [app, widget], 'Shared/OpenRouter.swift' => [app, widget], 'Shared/Qoder.swift' => [app, widget], 'Shared/OAuthLoopback.swift' => [app, widget], 'Shared/ProviderPreferences.swift' => [app, widget], 'App/OllamaCloudPanel.swift' => [app], 'App/OpenRouterPanel.swift' => [app], 'App/QoderPanel.swift' => [app], 'Tests/Build45OAuthTests.swift' => [tests], 'Tests/Build45ProviderTests.swift' => [tests] }
existing = p.files.map(&:path)
plan.each do |path, targets|
  ref = existing.include?(path) ? p.files.find { |f| f.path == path } : p.main_group.new_file(path)
  targets.each do |target|
    already = target.source_build_phase.files_references.map(&:path)
    next if already.include?(path)
    target.source_build_phase.add_file_reference(ref)
    puts "added #{path} -> #{target.name}"
  end
end
p.save
puts 'saved'
