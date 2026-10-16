"""从 OFL 字体生成仅含当前界面文字的子集，便于离线分发。"""
from pathlib import Path
import os
from fontTools import subset
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont

ROOT = Path(__file__).resolve().parents[1]
text = ''.join(chr(i) for i in range(32,127)) + '↑↓←→✓◇◈◉▣☺'
for pattern in ['*.gd','*.json']:
    for file in (ROOT/'godot/cruise').rglob(pattern):
        text += file.read_text(encoding='utf-8')
font = TTFont(os.environ.get('FONT_SOURCE',ROOT/'.tools/NotoSansSC.ttf'))
font = instantiateVariableFont(font,{'wght':400},inplace=True)
options=subset.Options()
options.name_IDs=['*']
options.notdef_glyph=True
subsetter=subset.Subsetter(options=options)
subsetter.populate(text=text)
subsetter.subset(font)
for record in font['name'].names:
    if record.nameID in [1,4,6]:
        value='PortfolioSans' if record.nameID==6 else 'Portfolio Sans'
        record.string=value.encode(record.getEncoding(),errors='replace')
target=ROOT/'godot/cruise/assets/PortfolioSans.ttf'
font.save(target)
print(f'中文界面字体：{target.stat().st_size/1024:.1f} KB')
