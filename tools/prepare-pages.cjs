// 为 GitHub Pages 添加浏览器隔离环境；离线服务本身已有正确响应头。
const fs=require('node:fs'),path=require('node:path');
const file=path.resolve(__dirname,'../web/play.html');
let html=fs.readFileSync(file,'utf8');
if(html.includes('coi-serviceworker.js')){console.log('Pages 入口已准备。');process.exit(0);}
html=html.replace('<script src="play.js"></script>','<script>window.coi={quiet:true};</script>\n<script src="../coi-serviceworker.js"></script>\n<script src="play.js"></script>');
html=html.replace('const engine = new Engine(GODOT_CONFIG);','');
html=html.replace('(function () {','function startCruise() {\n const engine = new Engine(GODOT_CONFIG);');
html=html.replace('}());',`}
if (window.crossOriginIsolated) {
  startCruise();
} else {
  const status=document.getElementById('status'),notice=document.getElementById('status-notice');
  status.style.visibility='visible';notice.style.display='block';
  notice.textContent='正在准备试玩环境，首次打开将自动刷新一次。';
  setTimeout(()=>{notice.textContent='若长时间未进入游戏，请刷新页面，或从仓库 Releases 下载离线版。';},15000);
}`);
fs.writeFileSync(file,html,'utf8');
console.log('Pages 入口已准备。');
