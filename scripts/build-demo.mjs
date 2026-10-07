import { mkdir, readFile, readdir, writeFile, copyFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root = fileURLToPath(new URL('../', import.meta.url));
const destination = path.join(root, 'dist');
const assets = ['index.html', 'app.js', 'barrier.js', 'world.js', 'style.css', '策划案.md'];
await mkdir(destination, { recursive: true });
// Only these public files may be packaged. Refuse stale/unexpected files.
for (const file of await readdir(destination)) {
  if (!assets.includes(file)) throw new Error(`Unexpected public asset: ${file}`);
}
for (const file of assets.filter(file => file !== 'index.html')) {
  await copyFile(path.join(root, file), path.join(destination, file));
}
let html = await readFile(path.join(root, 'index.html'), 'utf8');
const originalToggle = '<label><input type="checkbox" id="ai"> 使用真实 AI 接口</label>';
if (!html.includes(originalToggle)) throw new Error('AI control changed; review public build before publishing.');
html = html.replace('<html lang="zh-CN">', '<html lang="zh-CN" data-mode="simulation">')
  .replace('<title>大陆漂移假说</title>', '<title>大陆漂移假说 · 在线试玩</title>')
  .replace(originalToggle, '<input type="checkbox" id="ai" hidden disabled><strong>在线试玩 · 本地模拟</strong>')
  .replace('本地支持五种守护与禁火、禁谎、偿债三种法则。真实AI将自然语言映射为同样的可执行能力。', '本试玩版支持五种守护与禁火、禁谎、偿债三种法则。无需账号或密钥，所有游戏运算在你的浏览器中进行。')
  .replace('60轮结算 · 每6轮自动迁城 · 立誓不推进时间', '60轮结算 · 每6轮自动迁城 · 刷新会重新开始，可先导出历史');
await writeFile(path.join(destination, 'index.html'), html, 'utf8');
console.log(`Static demo ready: ${assets.length} public files in dist/`);
