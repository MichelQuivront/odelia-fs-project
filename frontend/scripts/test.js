const { spawnSync } = require('child_process');

async function chromePath() {
  // 1. CHROME_BIN déjà défini (CI, config perso) : on le respecte
  if (process.env.CHROME_BIN) return process.env.CHROME_BIN;

  // 2. Linux arm64 (devcontainer sur Mac Apple Silicon) : Chromium de Playwright
  if (process.platform === 'linux' && process.arch === 'arm64') {
    try {
      return require('playwright-core').chromium.executablePath();
    } catch {
      console.error('Lance : npx playwright-core install chromium');
      process.exit(1);
    }
  }

  // 3. Le reste (x64, Windows, macOS natif) : Chrome de Puppeteer
  return await require('puppeteer').executablePath();
}

(async () => {
  process.env.CHROME_BIN = await chromePath();
  const args = process.argv.slice(2);
  const watch = args.includes('--watch');
  const rest = args.filter((a) => a !== '--watch');
  const r = spawnSync(
    'npx',
    ['ng', 'test', ...(watch ? [] : ['--watch=false']), ...rest],
    { stdio: 'inherit', shell: true }
  );
  process.exit(r.status ?? 1);
})();