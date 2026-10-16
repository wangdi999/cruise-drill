const http = require('node:http');
const fs = require('node:fs/promises');
const path = require('node:path');
const root = __dirname;
const port = Number(process.env.PORT || 8090);
const types = {'.html':'text/html; charset=utf-8','.js':'text/javascript; charset=utf-8','.css':'text/css; charset=utf-8','.json':'application/json; charset=utf-8','.md':'text/plain; charset=utf-8','.wasm':'application/wasm','.png':'image/png'};
const server = http.createServer(async (req,res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url,'http://localhost').pathname);
    if(pathname==='/favicon.ico'){res.writeHead(204);res.end();return;}
    let file = path.resolve(root, '.'+pathname);
    if (!file.startsWith(root+path.sep) && file!==root) throw Error();
    if (path.relative(root,file).split(/[\\/]/).some(p=>p.startsWith('.'))) throw Error();
    if ((await fs.stat(file)).isDirectory()) file=path.join(file,'index.html');
    const data=await fs.readFile(file);
    res.writeHead(200,{'Content-Type':types[path.extname(file)]||'application/octet-stream','Cache-Control':'no-store','Cross-Origin-Opener-Policy':'same-origin','Cross-Origin-Embedder-Policy':'require-corp'});
    res.end(data);
  } catch (_) { res.writeHead(404);res.end('页面不存在'); }
});
server.on('error',e=>{console.error(e.code==='EADDRINUSE'?'端口已占用，请设置 PORT 后重试。':e.message);process.exitCode=1;});
server.listen(port,'127.0.0.1',()=>console.log(`巡航演练：http://127.0.0.1:${port}\n按 Ctrl+C 停止。`));
