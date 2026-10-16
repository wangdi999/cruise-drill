"""使用项目内 Godot 4.3 导出 Windows 与 Web，保留完整日志。"""
import os
import locale
import subprocess
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
ENGINE=Path(os.environ.get('GODOT_BIN',ROOT/'.tools/godot/Godot_v4.3-stable_win64.exe'))
TEMPLATES=Path(os.environ.get('GODOT_TEMPLATES',ROOT/'.tools/templates'))
for folder in ['artifacts','build/windows','web']:
    (ROOT/folder).mkdir(parents=True,exist_ok=True)

def run(label,args,timeout=180):
    result=subprocess.run([str(ENGINE),'--headless','--path',str(ROOT/'godot'),*args],cwd=ROOT,capture_output=True,timeout=timeout)
    raw=result.stdout+b'\n'+result.stderr
    try: output=raw.decode('utf-8')
    except UnicodeDecodeError: output=raw.decode('gb18030',errors='replace')
    (ROOT/'artifacts'/f'{label}.log').write_text(output,encoding='utf-8')
    print(output[-5000:],flush=True)
    if result.returncode or 'SCRIPT ERROR:' in output or 'ERROR:' in output:
        raise RuntimeError(label+' 未通过，请查看日志')

presets='''[preset.0]
name="Web"
platform="Web"
runnable=true
export_filter="all_resources"
include_filter="cruise/data.json"
exclude_filter="cruise/tests/*"
export_path="../web/play.html"

[preset.0.options]
custom_template/release="WEB_TEMPLATE"
variant/extensions_support=false
variant/thread_support=false
vram_texture_compression/for_desktop=true
vram_texture_compression/for_mobile=false
html/export_icon=false
html/canvas_resize_policy=2
html/focus_canvas_on_start=true
progressive_web_app/enabled=false

[preset.1]
name="Windows"
platform="Windows Desktop"
runnable=true
export_filter="all_resources"
include_filter="cruise/data.json"
exclude_filter="cruise/tests/*"
export_path="../build/windows/CruiseDemo.exe"

[preset.1.options]
custom_template/release="WINDOWS_TEMPLATE"
binary_format/embed_pck=true
texture_format/s3tc_bptc=true
texture_format/etc2_astc=false
codesign/enable=false
application/modify_resources=false
'''.replace('WEB_TEMPLATE',(TEMPLATES/'web_release.zip').as_posix()).replace('WINDOWS_TEMPLATE',(TEMPLATES/'windows_release_x86_64.exe').as_posix())
(ROOT/'godot/export_presets.cfg').write_text(presets,encoding='utf-8')
run('runtime-import',['--editor','--import'])
run('godot-core',['res://cruise/tests/test_suite.tscn'])
run('web-export',['--export-release','Web',str(ROOT/'web/play.html')])
run('windows-export',['--export-release','Windows',str(ROOT/'build/windows/CruiseDemo.exe')])
(ROOT/'web/play.html').write_text((ROOT/'web/play.html').read_text(encoding='utf-8').replace('lang="en"','lang="zh-CN"'),encoding='utf-8')
print('网页与 Windows 导出完成。')
