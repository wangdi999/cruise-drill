"""通过真实 Canvas 点击验证导出的 Godot 游戏，QA 接口只读。"""
import json, os, socket, subprocess, sys, time
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
# 当前工作区可复用已安装的测试工具；交付后可自行 pip 安装 playwright。
local=ROOT/'.test-tools'
if local.exists(): sys.path.insert(0,str(local))
from playwright.sync_api import sync_playwright

with socket.socket() as s:
    s.bind(('127.0.0.1',0));port=s.getsockname()[1]
server=subprocess.Popen(['node','server.cjs'],cwd=ROOT,env={**os.environ,'PORT':str(port)},stdout=subprocess.DEVNULL)
passed=[]; errors=[]
def check(value,name):
    assert value,name
    passed.append(name);print('通过：'+name,flush=True)
try:
    time.sleep(.5)
    with sync_playwright() as pw:
        browser=pw.chromium.launch(executable_path=r'C:\Program Files\Google\Chrome\Application\chrome.exe',headless=True,args=['--use-angle=swiftshader','--enable-unsafe-swiftshader'])
        context=browser.new_context(viewport={'width':1440,'height':1080},accept_downloads=True)
        page=context.new_page()
        page.on('pageerror',lambda error:errors.append(str(error)))
        page.on('console',lambda msg:errors.append(msg.text) if msg.type=='error' else None)
        page.goto(f'http://127.0.0.1:{port}/web/play.html?qa=1')
        try: page.wait_for_function('window.__cruiseQA',timeout=90000)
        except Exception:
            page.screenshot(path=str(ROOT/'artifacts/browser-failure.png'))
            print(errors,flush=True)
            raise
        def state():return page.evaluate('window.__cruiseQA')
        def click(key):
            for attempt in range(10):
                data=state();rect=data['buttons'].get(key)
                assert rect and not rect['disabled'],key+' 缺失或禁用'
                y=rect['y']+rect['h']/2
                if 8<y<data['viewport']['h']-8: break
                page.mouse.move(data['viewport']['w']-45,data['viewport']['h']/2)
                page.mouse.wheel(0,max(-650,min(650,y-data['viewport']['h']/2)))
                page.wait_for_timeout(100)
            else:raise AssertionError(key+' 滚动后不可见')
            page.mouse.click(rect['x']+rect['w']/2,y)
            page.wait_for_timeout(75)
        def day(index):
            click('daySelect')
            # 原生 Godot 弹出菜单不接收 DOM 键盘导航，按实际主题行高点击。
            rect=state()['buttons']['daySelect']
            page.mouse.click(rect['x']+rect['w']/2,rect['y']+rect['h']+18+index*29.2)
            page.wait_for_timeout(150)
        phase_seen=[]
        def fight():
            for _ in range(250):
                data=state()
                if data['profile']['run']['node'] not in ['battle','boss']:return
                if data['profile']['run']['battle'].get('bossEnraged') and not phase_seen:
                    phase_seen.append(True)
                    page.screenshot(path=str(ROOT/'artifacts/06-overload.png'))
                    saved=data['profile']['run']
                    page.reload();page.wait_for_function('window.__cruiseQA',timeout=60000)
                    check(state()['profile']['run']==saved,'首领过载时刷新，阶段、意图、手牌和接力完整恢复')
                    data=state()
                command=data.get('command','')
                if command:
                    click('command_'+command)
                    continue
                plan=data['plan']
                if not plan:click('endTurn')
                else:
                    click('card_'+str(plan['uid']))
                    if plan['target']!='auto':click('target_'+plan['target'])
            raise AssertionError('250 次操作仍未结束')
        check(state()['profile']['tokens']==0,'新用户零代币、默认合法三人队')
        page.screenshot(path=str(ROOT/'artifacts/01-team.png'))
        click('stage_2');check(state()['buttons']['start']['disabled'],'阶段二开放日限制')
        click('stage_1');click('start')
        page.screenshot(path=str(ROOT/'artifacts/02-battle.png'))
        before=state()['profile']['run'];page.reload();page.wait_for_function('window.__cruiseQA',timeout=60000)
        if state()['profile']['run']!=before:
            (ROOT/'artifacts/reload-diff.json').write_text(json.dumps({'before':before,'after':state()['profile']['run']},ensure_ascii=False,indent=2),encoding='utf-8')
        check(state()['profile']['run']==before,'刷新恢复完整战斗存档')
        page.set_viewport_size({'width':430,'height':932});page.wait_for_timeout(400)
        check(all(0<=r['x'] and r['x']+r['w']<=431 for key,r in state()['buttons'].items() if key.startswith('command_')),'窄屏战斗中三种指令均在可视宽度内')
        page.screenshot(path=str(ROOT/'artifacts/07-narrow-battle.png'))
        page.set_viewport_size({'width':1440,'height':1080});page.wait_for_timeout(400)
        fight();check(state()['profile']['run']['node']=='draft','基础战斗由真实出牌完成，进入三选一改装')
        page.screenshot(path=str(ROOT/'artifacts/05-draft.png'))
        draft_before=state()['profile']['run'];page.reload();page.wait_for_function('window.__cruiseQA',timeout=60000)
        check(state()['profile']['run']==draft_before,'刷新保持奖励选项与战斗结算')
        click('draft_ranger');check(state()['profile']['run']['node']=='buff','选定改装后进入增益选择')
        click('buff_shield')
        boss=state()['profile']['run'];piles=boss['battle']
        check(sum(1 for key in ['deck','hand','discard'] for c in piles[key] if c['kind']>=2)==2,'首领牌组包含两张专属牌')
        check(sum(len(piles[k]) for k in ['deck','hand','discard'])==12,'替换基础牌后牌组仍为十二张')
        fight();check(state()['profile']['run']['node']=='complete','阶段一首领战由真实出牌完成')
        click('resultClaim');click('buy_materials');check(state()['profile']['tokens']==20,'首通 100、材料兑换 80，余额 20')
        click('return');day(1);check(state()['profile']['day']==2,'演练日切换至第 2 天')
        click('stage_2');click('start');click('route_A');fight();click('draft_medic');click('buff_healing');fight()
        check(state()['profile']['run']['node']=='complete','阶段二基础战与首领战通关')
        click('resultClaim');click('buy_emotes');check(state()['profile']['tokens']==0,'表情兑换 120，余额归零')
        click('return');day(2);click('stage_3');click('start');click('route_B');fight();click('draft_guard');click('buff_assault');fight()
        check(state()['profile']['run']['node']=='complete','阶段三路线 B、组合增益通关')
        click('return');day(4);click('claim_3');click('buy_frame')
        check(len(state()['profile']['claimed'])==3 and len(state()['profile']['inventory'])==3 and state()['profile']['tokens']==0,'第 8 天补领首通，三项兑换合计 300')
        check(state()['buttons']['start']['disabled'],'第 8 天禁止开启战斗')
        day(5);check(all(state()['buttons']['buy_'+x]['disabled'] for x in ['frame','materials','emotes']),'第 9 天商店关闭')
        page.screenshot(path=str(ROOT/'artifacts/03-rewards.png'))
        with page.expect_download() as info:click('export')
        info.value.save_as(str(ROOT/'artifacts/browser-export.json'))
        exported=json.loads((ROOT/'artifacts/browser-export.json').read_text(encoding='utf-8'))
        check(len(exported['profile']['completed'])==3,'导出演练记录包含三阶段首通')
        page.set_viewport_size({'width':430,'height':932});page.wait_for_timeout(400)
        check(state()['viewport']['w']==430,'窄屏布局重排')
        page.screenshot(path=str(ROOT/'artifacts/04-narrow.png'))
        events=state()['profile']['events']
        check(any(e['type']=='command' for e in events),'完整流程实际使用舰队指令')
        check(sum(e['type']=='draft' for e in events)==3,'三个阶段分别完成改装选择')
        check(bool(phase_seen),'真实首领战触发过载阶段')
        check(not errors,'浏览器无脚本或控制台错误')
        browser.close()
finally:
    server.terminate();server.wait(timeout=5)
    (ROOT/'artifacts/browser-report.json').write_text(json.dumps({'passed':passed,'errors':errors,'note':'桌面 Chrome 自动化点击，非真人试玩；窄屏截图不代表真机验收。'},ensure_ascii=False,indent=2),encoding='utf-8')
