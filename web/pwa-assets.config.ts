import { defineConfig, minimal2023Preset } from '@vite-pwa/assets-generator/config';

// Generates favicon, PWA icons (incl. maskable) and the Apple touch icon from
// public/icon.svg: npx pwa-assets-generator
export default defineConfig({
  headLinkOptions: { preset: '2023' },
  preset: {
    ...minimal2023Preset,
    maskable: { ...minimal2023Preset.maskable, resizeOptions: { background: '#1d4e5f' } },
    apple: { ...minimal2023Preset.apple, resizeOptions: { background: '#1d4e5f' } },
  },
  images: ['public/icon.svg'],
});
