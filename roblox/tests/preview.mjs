// Renders the actual client instance tree captured by service doubles.
// This is a layout approximation, not a Roblox Studio rendering test.
import { execFileSync } from 'node:child_process';
import { mkdir, writeFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { fileURLToPath, URL } from 'node:url';
import process from 'node:process';
import console from 'node:console';
import { chromium } from '@playwright/test';
const root = fileURLToPath(new URL('../', import.meta.url));
const interpreter = process.argv[2] || 'lua';
const output = resolve(root, 'dist/previews');
await mkdir(output, { recursive: true });
const escape = (value) =>
  String(value)
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
const rgb = (c) => `rgb(${c.r},${c.g},${c.b})`;
const dimension = (d) => `calc(${d.Scale * 100}% + ${d.Offset}px)`;
function render(node) {
  const children = Object.values(node.children || {});
  if (
    node.Visible === false ||
    ['UICorner', 'UIGradient', 'UIStroke'].includes(node.ClassName)
  )
    return '';
  const css = ['position:absolute', 'box-sizing:border-box'];
  if (node.ClassName === 'ScreenGui' || node.ClassName === 'PlayerGui')
    css.push('inset:0');
  if (node.Size)
    css.push(
      `width:${dimension(node.Size.X)}`,
      `height:${dimension(node.Size.Y)}`,
    );
  if (node.Position)
    css.push(
      `left:${dimension(node.Position.X)}`,
      `top:${dimension(node.Position.Y)}`,
    );
  const transforms = [];
  if (node.AnchorPoint && (node.AnchorPoint.X || node.AnchorPoint.Y))
    transforms.push(
      `translate(${-node.AnchorPoint.X * 100}%,${-node.AnchorPoint.Y * 100}%)`,
    );
  if (node.Rotation) transforms.push(`rotate(${node.Rotation}deg)`);
  const uiScale = children.find((c) => c.ClassName === 'UIScale');
  if (uiScale && uiScale.Scale !== 1)
    transforms.push(`scale(${uiScale.Scale})`);
  if (transforms.length) css.push(`transform:${transforms.join(' ')}`);
  const padding = children.find((c) => c.ClassName === 'UIPadding');
  if (padding)
    css.push(
      `padding-left:${padding.PaddingLeft?.Offset ?? 0}px`,
      `padding-right:${padding.PaddingRight?.Offset ?? 0}px`,
    );
  const sizeLimit = children.find((c) => c.ClassName === 'UISizeConstraint');
  if (sizeLimit?.MaxSize)
    css.push(
      `max-width:${sizeLimit.MaxSize.X}px`,
      `max-height:${sizeLimit.MaxSize.Y}px`,
    );
  if (node.ZIndex || node.DisplayOrder)
    css.push(`z-index:${node.ZIndex || node.DisplayOrder}`);
  if (node.BackgroundColor3 && node.BackgroundTransparency !== 1) {
    const c = node.BackgroundColor3;
    css.push(
      `background:rgba(${c.r},${c.g},${c.b},${1 - (node.BackgroundTransparency || 0)})`,
    );
    const gradient = children.find((c) => c.ClassName === 'UIGradient');
    const stops = gradient?.Transparency?.Keypoints;
    if (gradient && gradient.Enabled !== false && stops) {
      const first = gradient.Color?.first ?? c;
      const last = gradient.Color?.last ?? c;
      const mix = (x, y, t) => Math.round(x + (y - x) * t);
      const base = 1 - (node.BackgroundTransparency || 0);
      const parts = Object.values(stops).map((k) => {
        const r = mix((c.r * first.r) / 255, (c.r * last.r) / 255, k.Time);
        const g = mix((c.g * first.g) / 255, (c.g * last.g) / 255, k.Time);
        const b = mix((c.b * first.b) / 255, (c.b * last.b) / 255, k.Time);
        return `rgba(${r},${g},${b},${base * (1 - k.Value)}) ${k.Time * 100}%`;
      });
      css.push(
        `background:linear-gradient(${(gradient.Rotation || 0) + 90}deg,${parts.join(',')})`,
      );
    } else if (
      gradient &&
      gradient.Enabled !== false &&
      !node.BackgroundTransparency
    )
      css.push(
        `background:linear-gradient(${(gradient.Rotation || 0) + 90}deg,${rgb(gradient.Color.first)},${rgb(gradient.Color.last)})`,
      );
  }
  const corner = children.find((c) => c.ClassName === 'UICorner');
  if (corner)
    css.push(
      `border-radius:${corner.CornerRadius.Scale >= 0.5 ? 9999 : corner.CornerRadius.Offset}px`,
    );
  const stroke = children.find((c) => c.ClassName === 'UIStroke');
  if (stroke)
    css.push(`outline:${stroke.Thickness}px solid ${rgb(stroke.Color)}`);
  if (node.ClipsDescendants) css.push('overflow:hidden');
  if (node.ClassName === 'ScrollingFrame')
    css.push('overflow-x:auto', 'overflow-y:hidden');
  let content = '';
  if (node.Text !== undefined && node.TextTransparency !== 1) {
    css.push(
      'display:flex',
      'align-items:center',
      `justify-content:${node.TextXAlignment === 'TextXAlignment.Left' ? 'flex-start' : 'center'}`,
      `text-align:${node.TextXAlignment === 'TextXAlignment.Left' ? 'left' : 'center'}`,
      'white-space:pre-wrap',
      `font-size:${node.TextSize || 16}px`,
      `font-weight:${node.Font?.includes('Bold') ? 700 : 500}`,
    );
    if (
      node.TextStrokeTransparency !== undefined &&
      node.TextStrokeTransparency < 1 &&
      node.TextStrokeColor3
    ) {
      const t = node.TextStrokeColor3;
      const a =
        (1 - node.TextStrokeTransparency) * (1 - (node.TextTransparency || 0));
      css.push(
        `-webkit-text-stroke:2px rgba(${t.r},${t.g},${t.b},${a})`,
        'paint-order:stroke fill',
      );
    }
    if (node.TextColor3)
      css.push(
        `color:rgba(${node.TextColor3.r},${node.TextColor3.g},${node.TextColor3.b},${1 - (node.TextTransparency || 0)})`,
      );
    content = escape(node.Text);
  }
  content += children.map(render).join('');
  return `<div data-name="${escape(node.Name || node.ClassName)}" style="${css.join(';')}">${content}</div>`;
}
const only = process.env.PREVIEW_ONLY?.split(',');
const browser = await chromium.launch({ channel: 'chrome', headless: true });
try {
  for (const [name, width, height, mode] of [
    ['home', 1440, 900, 'home'],
    ['desktop', 1440, 900, 'play'],
    ['phone', 390, 844, 'kitty'],
    ['landscape', 844, 390, 'play'],
    ['shop', 1280, 720, 'shop'],
    ['tier', 1440, 900, 'tier'],
    ['flight', 1440, 900, 'flight:flower'],
    ['impact-tomato', 1440, 900, 'impact:tomato'],
    ['impact-bomb', 1440, 900, 'impact:bomb'],
    ['impact-rose', 1440, 900, 'impact:flower'],
    ['impact-trophy', 1440, 900, 'impact:cheer'],
    ['settle', 1440, 900, 'settle'],
    ['settle-phone', 390, 844, 'settle'],
    ['squad', 1440, 900, 'squad'],
    ['squad-phone', 390, 844, 'squad'],
    ['waiting', 1440, 900, 'waiting'],
    ['waiting-phone', 390, 844, 'waiting'],
    ['stats-phone', 390, 844, 'stats'],
    ['chat', 1440, 900, 'chat'],
    ['chat-phone', 390, 844, 'chat'],
    ['tier-phone', 390, 844, 'tier'],
    ['home-phone', 390, 844, 'home'],
    ['private-picker', 1440, 900, 'private'],
    ['private-picker-phone', 390, 844, 'private'],
    ['tier-landscape', 844, 390, 'tier'],
    ['ten-player', 1440, 900, 'multi'],
    ['ten-player-phone', 390, 844, 'multi'],
    ['ten-player-short', 1280, 620, 'multi'],
  ]) {
    // PREVIEW_ONLY=name,name renders a subset (each capture replays the client suite).
    if (only && !only.includes(name)) continue;
    const snapshot = execFileSync(
      interpreter,
      [
        'roblox/tests/client.lua',
        'snapshot',
        String(width),
        String(height),
        mode,
      ],
      {
        cwd: resolve(root, '..'),
        encoding: 'utf8',
        maxBuffer: 64 * 1024 * 1024,
      },
    );
    const tree = JSON.parse(snapshot);
    const html = `<!doctype html><meta charset="utf-8"><style>html,body{margin:0;width:100%;height:100%;overflow:hidden;font-family:Arial,sans-serif}*{scrollbar-width:thin;scrollbar-color:#edc272 transparent}</style>${render(tree)}`;
    await writeFile(resolve(output, `${name}.html`), html);
    const page = await browser.newPage({ viewport: { width, height } });
    await page.setContent(html);
    if (mode === 'home') {
      await page
        .locator('[data-name="ModeTitle"]')
        .filter({ hasText: 'PLAY TRACTOR' })
        .waitFor();
      if (
        await page
          .locator('[data-name="HomeHeader"] [data-name="PlayerName"]')
          .count()
      )
        throw new Error('Mode selection still contains a player profile');
    }
    await page.screenshot({ path: resolve(output, `${name}.png`) });
    await page.close();
    console.log(`Rendered ${name}: ${width}×${height}`);
  }
} finally {
  await browser.close();
}
