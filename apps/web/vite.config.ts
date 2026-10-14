import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import legacy from '@vitejs/plugin-legacy';
import { transformAsync } from '@babel/core';

// The legacy plugin's separately built SystemJS/polyfill asset can inherit
// Vite's modern target. Normalize every emitted legacy chunk, including that
// asset, after it is generated so old WebKit TVs never receive modern syntax.
const legacySyntax = {
  name: 'glukwave-legacy-syntax',
  enforce: 'post' as const,
  async generateBundle(_options: unknown, bundle: Record<string, {type: string; code?: string; source?: string | Uint8Array}>) {
    for (const [name, item] of Object.entries(bundle)) {
      if (!name.includes('-legacy-') || !name.endsWith('.js')) continue;
      const code = item.type === 'chunk' ? item.code : item.source;
      if (typeof code !== 'string') continue;
      const result = await transformAsync(code, {
        babelrc: false, configFile: false, compact: true, comments: true,
        presets: [['@babel/preset-env', {targets: {ie: '11'}, modules: false}]],
      });
      if (result?.code) {
        if (item.type === 'chunk') item.code = result.code;
        else item.source = result.code;
      }
    }
  },
};
export default defineConfig({
  plugins: [react(), legacy({ targets: ['Chrome >= 38', 'Safari >= 7', 'IE >= 11'], modernPolyfills: ['es.array.at', 'es.promise.all-settled'] }), legacySyntax],
  server: { host: '127.0.0.1', port: 5173, strictPort: true, proxy: { '/api': 'http://127.0.0.1:4000', '/socket.io': { target: 'http://127.0.0.1:4000', ws: true } } },
  build: { minify: 'terser', terserOptions: { ecma: 5, format: { ecma: 5 }, compress: { ecma: 5 } }, rollupOptions:{input:{main:'index.html',mini:'mini.html'}} }
});
