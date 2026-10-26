// Живой запуск AO Bible на Windows (запускает значок на панели задач — tool/live.vbs, и ведущая сессия Claude).
// flutter run в режиме отладки; окно обновляется само: правка в lib/ или assets/ — через 1,5 с тишины горячее
// обновление («r»). Вручную: записать «r» (обновить) или «R» (перезапустить) в tool/.reload. Журнал — tool/live.log.
import { spawn } from 'node:child_process';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const SDK = path.resolve(ROOT, '..', 'flutter-sdk');
const T = path.join(ROOT, 'tool', '.reload');
fs.writeFileSync(T, '');
const env = {
  ...process.env,
  PUB_CACHE: path.join(SDK, 'pub-cache'),
  FLUTTER_SUPPRESS_ANALYTICS: 'true',
  PATH: path.join(SDK, 'flutter', 'bin') + ';' + process.env.PATH,
};
const p = spawn('cmd.exe', ['/c', 'flutter', 'run', '-d', 'windows'], { cwd: ROOT, env, stdio: ['pipe', 'inherit', 'inherit'] });

let ready = false; // до первой сборки обновлять нечего
setTimeout(() => (ready = true), 90000);
const send = (c) => {
  try {
    p.stdin.write(c);
  } catch {}
};

// ручное обновление
fs.watchFile(T, { interval: 400 }, () => {
  const c = fs.readFileSync(T, 'utf8').trim();
  if (c) send(c === 'R' ? 'R' : 'r');
});

// само: правки в lib/ и assets/ → «r» после 1,5 с тишины (несколько файлов подряд — одно обновление)
let timer = null;
const onChange = (_, file) => {
  if (!file || !/\.(dart|json|ttf|png|svg)$/i.test(file)) return;
  clearTimeout(timer);
  timer = setTimeout(() => {
    if (!ready) return;
    console.log(`\n[живое окно] изменён ${file} — обновляю`);
    send('r');
  }, 1500);
};
for (const dir of ['lib', 'assets']) fs.watch(path.join(ROOT, dir), { recursive: true }, onChange);

p.on('exit', (c) => process.exit(c ?? 0));
