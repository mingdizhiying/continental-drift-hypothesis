import {spawn} from 'node:child_process';
import {fileURLToPath} from 'node:url';
import http from 'node:http';
const root = fileURLToPath(new URL('../', import.meta.url));
const executable = process.argv[2] || process.env.GODOT_BIN || 'godot';
async function run(command, args) {
  await new Promise((resolve, reject) => {
    const child = spawn(command, args, {cwd:root, windowsHide:true, timeout:180000});
    let output = '';
    child.stdout.on('data', data => { output += data; process.stdout.write(data); });
    child.stderr.on('data', data => { output += data; process.stderr.write(data); });
    child.on('error', reject);
    child.on('exit', code => {
      if (code !== 0 || /(?:SCRIPT ERROR:|^ERROR:)/m.test(output)) reject(new Error(`Failed (${code}): ${command} ${args.join(' ')}`));
      else resolve();
    });
  });
}
await run(process.execPath, ['tools/godot-reference.mjs']);
await run(process.execPath, ['--test','tools/web-baseline/world.test.js']);
await run(process.execPath, ['tools/test-godot-proxy.mjs']);
await run(executable, ['--headless','--path','godot','--editor','--import','--quit']);
await run(executable, ['--headless','--path','godot','--script','res://tests/test_world.gd']);
await run(executable, ['--headless','--path','godot','--script','res://tests/test_ui.gd']);
await run(executable, ['--headless','--path','godot','--script','res://tests/test_fog_beacon.gd']);
const server = http.createServer(async (req,res) => {
  let raw = ''; for await (const chunk of req) raw += chunk;
  const input = JSON.parse(raw);
  res.setHeader('Content-Type','application/json');
  if (req.url === '/unavailable') { res.writeHead(503); res.end(JSON.stringify({error:'模拟未配置模型'})); return; }
  if (req.url === '/bad-json') { res.end('not JSON'); return; }
  if (input.task === 'oath') {
    if (req.url === '/reject') res.end(JSON.stringify({accepted:false,reason:'模拟拒绝：该誓约不可实行'}));
    else res.end(JSON.stringify({accepted:true,oath:{type:req.url === '/invalid' ? 'code' : 'food',
      condition:req.url === '/invalid-condition' ? [] : {metric:'trade',min:30},explanation:'繁荣≥30；每轮消耗1繁荣'}}));
  } else if (input.task === 'turn') res.end(JSON.stringify({summary:'模拟代理测试',effects:[{cityId:'ember',delta:{food:req.url === '/invalid' ? 100 : -3},reason:'模拟商路影响'}]}));
  else res.end(JSON.stringify(req.url === '/invalid' ? {title:42} : {title:'模拟代理结局',text:'仅用于测试协议，非真实模型结果。',evidence:['第60轮完成世界结算']}));
});
await new Promise(resolve => server.listen(0,'127.0.0.1',resolve));
try {
  await run(executable, ['--headless','--path','godot','--script','res://tests/test_ai.gd','--',`--proxy=http://127.0.0.1:${server.address().port}`]);
} finally { await new Promise(resolve => server.close(resolve)); }
console.log('Godot checks passed. Live provider credentials were not used.');
