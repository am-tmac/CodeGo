#!/usr/bin/env python3
"""Render actual shipped widget views using the retrieved public wire fixture (no credentials)."""
from pathlib import Path
import subprocess
root = Path(__file__).resolve().parents[1]
out = Path.home()/'.hermes/cache/scratch/codexusage-build34-render'
out.mkdir(parents=True, exist_ok=True)
widget = (root/'Widget/CodexUsageWidget.swift').read_text().replace('@main struct CodexUsageWidgetBundle', 'struct CodexUsageWidgetBundle')
# widgetFamily is read-only outside WidgetKit; only the isolated render copy injects it.
widget = widget.replace('@Environment(\\.widgetFamily) private var family', 'var family: WidgetFamily = .systemSmall')
(out/'Widget.swift').write_text(widget)
(out/'Render.swift').write_text(r'''
import AppKit
import SwiftUI
import WidgetKit
struct FixtureTransport: HTTPTransport {
    let data: Data
    func send(_ request: URLRequest) async throws -> (Data, Int) { (data, 200) }
}
@main struct Render {
    @MainActor static func main() async throws {
        let fixture = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[1]))
        let snapshot = try await TokensCIAPI(transport: FixtureTransport(data: fixture)).profile(username: "Alice39s", token: "tkr_fixture_only")
        let destination = URL(fileURLWithPath: CommandLine.arguments[2])
        for light in [false, true] {
            for medium in [false, true] {
                for empty in [false, true] {
                    let palette: ThemePalette = light ? .light : .dark
                    let view = TokensCIWidgetView(family: medium ? .systemMedium : .systemSmall, snapshot: empty ? nil : snapshot, palette: palette)
                        .frame(width: medium ? 338 : 158, height: 158)
                        .background(palette.background)
                    let renderer = ImageRenderer(content: view)
                    renderer.scale = 3
                    guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
                          let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { fatalError("render failed") }
                    let name = "widget-\(light ? "light" : "dark")-\(medium ? "medium" : "small")-\(empty ? "empty" : "public").png"
                    try png.write(to: destination.appendingPathComponent(name))
                    print(name)
                }
            }
        }
    }
}
''')
command = ['swiftc', '-parse-as-library', '-module-name', 'CodexUsageCore', '-D', 'CODEX_WIDGET', '-target', 'arm64-apple-macos14', *map(str, sorted((root/'Shared').glob('*.swift'))), str(out/'Widget.swift'), str(out/'Render.swift'), '-o', str(out/'render')]
result = subprocess.run(command, capture_output=True, text=True)
print(result.stderr[-5000:])
if result.returncode: raise SystemExit(result.returncode)
subprocess.run([str(out/'render'), str(root/'Tests/Fixtures/tokensci-public.json'), str(out)], check=True)
print(out)
