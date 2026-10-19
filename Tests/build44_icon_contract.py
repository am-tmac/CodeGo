import json, struct, unittest
from pathlib import Path
ROOT = Path(__file__).resolve().parents[1]
ICON = ROOT/'App/Assets.xcassets/AppIcon.appiconset'
def png_info(p):
    b = p.read_bytes()
    assert b[:8] == b'\x89PNG\r\n\x1a\n'
    w, h, depth, ctype = struct.unpack('>IIBB', b[16:26])
    return w, h, ctype
class IconContract(unittest.TestCase):
    def test_three_appearances_1024(self):
        images = json.loads((ICON/'Contents.json').read_text())['images']
        looks = {(i.get('appearances') or [{'value': 'any'}])[0]['value']: i['filename'] for i in images}
        self.assertEqual(set(looks), {'any', 'dark', 'tinted'})
        for name in looks.values():
            w, h, _ = png_info(ICON/name)
            self.assertEqual((w, h), (1024, 1024), name)
    def test_primary_icon_has_no_alpha(self):
        # App Store rejects an alpha channel on the primary 1024 icon. PNG colour type 2 = RGB.
        self.assertEqual(png_info(ICON/'AppIcon.png')[2], 2)
    def test_sources_kept_and_old_generator_gone(self):
        for n in ['appicon-light.svg', 'appicon-dark.svg', 'appicon-tinted.svg', 'codego-symbol-color.svg']:
            self.assertTrue((ROOT/'Design/logo/final'/n).exists(), n)
        self.assertFalse((ROOT/'Scripts/draw_icon.swift').exists())
if __name__ == '__main__': unittest.main()
