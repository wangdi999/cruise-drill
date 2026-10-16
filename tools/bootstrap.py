"""获取官方便携引擎及导出模板；只写入当前项目目录。"""
import concurrent.futures
import io
import json
import time
import zipfile
from pathlib import Path
import requests

ROOT = Path(__file__).resolve().parents[1]
TOOLS = ROOT / '.tools'
TOOLS.mkdir(exist_ok=True)
BASE = 'https://github.com/godotengine/godot-builds/releases/download/4.3-stable/'

def download(url, target):
    if target.exists() and target.stat().st_size > 1000:
        return
    with requests.get(url, stream=True, timeout=(30,180)) as response:
        response.raise_for_status()
        with target.open('wb') as output:
            for block in response.iter_content(1024*256):
                output.write(block)
    print('下载完成：' + target.name, flush=True)

def engine():
    archive = TOOLS / 'Godot_v4.3-stable_win64.exe.zip'
    download(BASE + archive.name, archive)
    with zipfile.ZipFile(archive) as source:
        source.extractall(TOOLS / 'godot')
    # 只调整本工程的便携编辑器配置，避免影响系统设置。
    (TOOLS/'godot/_sc_').touch()
    settings=TOOLS/'godot/editor_data/editor_settings-4.3.tres'
    settings.parent.mkdir(parents=True,exist_ok=True)
    settings.write_text('[gd_resource type="EditorSettings" format=3]\n\n[resource]\nfilesystem/on_save/safe_save_on_backup_then_rename = false\n',encoding='utf-8')

def font():
    target = TOOLS / 'NotoSansSC.ttf'
    download('https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/NotoSansSC%5Bwght%5D.ttf', target)
    license = ROOT / 'godot/cruise/assets/OFL.txt'
    license.parent.mkdir(parents=True,exist_ok=True)
    download('https://raw.githubusercontent.com/google/fonts/main/ofl/notosanssc/OFL.txt', license)

class RemoteArchive(io.RawIOBase):
    def __init__(self,url):
        self.session=requests.Session()
        # 独立查询参数避免缓存把不同字节区间混为同一个响应。
        self.url=url+'?range='+str(int(time.time()))
        metadata=self.session.head(self.url,allow_redirects=True,timeout=(30,180))
        metadata.raise_for_status()
        self.size=int(metadata.headers['Content-Length'])
        response=self.session.get(self.url,headers={'Range':f'bytes={self.size-65536}-{self.size-1}'},stream=True,timeout=(30,180))
        if response.status_code!=206:
            response.close()
            raise RuntimeError('镜像不支持分段读取，未下载完整多平台模板包')
        self.size=int(response.headers['Content-Range'].split('/')[-1])
        self.tail=response.content
        self.offset=0
    def seekable(self): return True
    def readable(self): return True
    def tell(self): return self.offset
    def seek(self,offset,whence=0):
        self.offset=offset if whence==0 else self.offset+offset if whence==1 else self.size+offset
        return self.offset
    def read(self,size=-1):
        if size<0: size=self.size-self.offset
        size=min(size,self.size-self.offset)
        if size<=0:return b''
        start=self.offset;self.offset+=size
        if start>=self.size-len(self.tail):return self.tail[start-(self.size-len(self.tail)):start-(self.size-len(self.tail))+size]
        response=self.session.get(self.url+'&start='+str(start),headers={'Range':f'bytes={start}-{start+size-1}'},timeout=(30,180))
        response.raise_for_status()
        if response.status_code!=206:raise RuntimeError('模板分段响应异常')
        return response.content

def templates():
    remote=RemoteArchive(BASE+'Godot_v4.3-stable_export_templates.tpz')
    folder=TOOLS/'templates';folder.mkdir(exist_ok=True)
    with zipfile.ZipFile(remote) as source:
        for name in ['web_release.zip','windows_release_x86_64.exe']:
            member=next(n for n in source.namelist() if n.endswith('/'+name))
            (folder/name).write_bytes(source.read(member))
            print('模板已提取：'+name,flush=True)

with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:
    jobs={pool.submit(fn):name for name,fn in [('引擎',engine),('字体',font),('模板',templates)]}
    results={}
    for future in concurrent.futures.as_completed(jobs):
        name=jobs[future]
        try:future.result();results[name]='完成'
        except Exception as error:results[name]=str(error);print(name+'：'+str(error),flush=True)
(TOOLS/'bootstrap-result.json').write_text(json.dumps(results,ensure_ascii=False,indent=2),encoding='utf-8')
