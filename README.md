# 巡航演练 · 接力改装

三人小队回合制卡牌原型：轮换队员出牌积累舰队指令，战后改装关键队员的专属牌，再应对首领的过载变招。保留原有三阶段活动奖励闭环。

**[在线试玩](https://wangdi999.github.io/cruise-drill/) · [下载 Windows / 网页离线版](https://github.com/wangdi999/cruise-drill/releases/latest)**

![实际战斗画面](artifacts/02-battle.png)

## 开始试玩

在线版使用现代桌面浏览器打开，首次访问会自动刷新一次以准备运行环境；完整加载约需 33 MB 运行资源。

Releases 中的 Windows ZIP 解压后双击 `巡航演练.exe`。网页离线 ZIP 解压后双击 `开始游戏.bat`，使用 Windows 自带 PowerShell 启动，不需要安装开发工具。

玩法：六名固定试用角色选三人，至少一名输出；三人组成 12 张牌，每回合 3 能量、抽 5 张。先选手牌，再选目标；群体牌直接施放。每阶段为基础战、专属改装三选一、增益选择、首领战。阶段在第 1 / 2 / 4 天开放，顶部演练日用于快速展示时间边界。首通各 100，总额 300，对应三项兑换价格 100 / 80 / 120。第 8 天停止战斗，第 9 天停止兑换并转换剩余代币。

## v1.1 新玩法与设计依据

- **三人接力**：三名不同队员各出一张牌，蓄满一次免费舰队指令。齐射对敌全体造成 8 伤害；屏障给存活队员各 9 护盾；补给给存活队员各恢复 6 并抽 1 张。进度与就绪状态跨回合保存，使用后清空，每回合限一次，不叠加储存。三名不同队员无需按固定顺序；同一队员重复出牌不重复计数，倒下队员不可出牌或复活。轮换积累接力与原有同角色连续增伤形成顺序取舍。
- **专属改装**：六位角色各有两种新专属牌，共十二种。基础战后每位队员按本局种子提供一种，三选一；首领战将该队员两张基础牌替换为两张专属牌，保持十二张牌。强化仅在本局生效，重试重新生成种子，刷新不重抽。改装牌均为一费，通常提供基础效果约 1.3～1.8 倍或一项副效果，方便轮换蓄能；不是无限扩张卡池。
- **首领过载**：新挑战中首领生命到一半及以下且未死亡时，攻击 +3，群攻从每三回合改为偶数回合。切换阶段立即更新本回合意图，玩家可以继续出牌或用指令应对；变招不会立即额外攻击。群攻伤害为增强后攻击的 55%，四舍五入，至少 6。

数值依据：基础一费攻击约 8、单体治疗 10、防护 10。齐射的总收益随敌人数变化（单首领 8 / 双敌 16）；屏障最多 27 但回合后失效；补给最多恢复 18 且不能超上限。三种指令随敌方意图和队伍缺血产生不同价值。基础战与首领战重新计算接力，防止战前囤积。半血阶段只增加 3 点基础攻击，避免一轮突变直接压垮原三能量框架。这些是原型初值，自动通关不代表真人难度已平衡。

机制参考：[Slay the Spire 官方商店](https://store.steampowered.com/app/646570/Slay_the_Spire/)的局内组牌与协同构筑、[Monster Train 官方商店](https://store.steampowered.com/app/1102190/Monster_Train/)的组合策略与重复挑战。接力指令、三队员替换牌、过载预告为本项目组合设计；参考机制不等于证明单一机制导致市场成功，未复制其素材与代码。

旧存档继续保留：已完成阶段、代币和兑换不变；升级前进行中的挑战保留原战斗与节点，下次出发使用新规则。浏览器存档为本机记录，没有账号或在线排名。

## 源码与构建

Godot **4.3 stable** 导入 `godot/project.godot` 后运行。`godot/cruise/data.json` 配置角色、技能、关卡与增益，`rules.gd` 实现战斗和奖励，`main.gd` 实现中文界面与存档。

本地网页预览（需要 Node.js）：

```sh
node server.cjs
```

打开 http://127.0.0.1:8090 。构建 Windows / Web 需要 Python，脚本仅在项目目录下载官方便携引擎与导出模板：

```sh
python -m pip install requests fonttools brotli playwright
python tools/bootstrap.py
python tools/subset_font.py
python tools/build.py
python tools/browser_test.py
```

可通过环境变量 `GODOT_BIN`、`GODOT_TEMPLATES`、`FONT_SOURCE` 复用已有引擎、模板和原字体。

`build.py` 重建常规 Web 导出；GitHub Pages 版 `web/play.html` 另有隔离环境入口适配，重新导出后运行 `node tools/prepare-pages.cjs` 恢复适配。编译后的 Web 运行文件已包含在仓库，可直接部署；Windows 大文件放在 Releases。

## 改造与归属

上游：[guladam/deck_builder_tutorial](https://github.com/guladam/deck_builder_tutorial)，固定提交 `91b408bc660e9b7389892dd4242a4d76e5bc9e77`，作者 Adam Gulacsi，MIT。

实际复用 Card、CardPile、Stats、CharacterStats、RNG 与修正器基础代码。7 个脚本原样保留，CharacterStats 的遗物类型只做一行兼容调整；新增队伍、卡牌效果、活动控制器和 GUI。原地图、拖拽界面、遗物及原战斗场景没有接入当前流程。代码在 AI 辅助下实现，详见 [改造说明](docs/改造说明.md)、[复用审计](artifacts/source-audit.json) 与 [差异文件](artifacts/upstream-changes.diff)。

新增代码 MIT 许可见根目录 LICENSE；上游声明见 `godot/LICENSE`，引擎第三方声明见 `LICENSES/`。中文字体来自 Noto Sans SC，子集改名 Portfolio Sans，采用 SIL OFL。GitHub Pages 隔离环境由 [coi-serviceworker](https://github.com/gzuidhof/coi-serviceworker) 提供，MIT 声明保留在 `LICENSES/`。

## 验证范围

v1.1 包含 47 项核心检查（含接力、三种指令、十二种专属牌、奖励存档、过载预告及旧档兼容）、默认队伍固定策略 50 局完整战斗和 Chrome 三阶段实际点击检查；证据见 `artifacts/`。自动化不代表真人难度或线上运营结论，手机为桌面浏览器视口模拟。存档只在本机，演练日可手动切换，兑换品为原型占位。
