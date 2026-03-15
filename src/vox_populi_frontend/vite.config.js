import { fileURLToPath, URL } from 'url';
import { execSync } from 'child_process';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import environment from 'vite-plugin-environment';
import dotenv from 'dotenv';

dotenv.config({ path: '../../.env' });

function resolveGitReleaseRef() {
  try {
    return execSync('git describe --tags --always', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
  } catch {
    // Fallback para entornos sin metadata git (por ejemplo, ciertos builds en CI/CD).
    return 'main';
  }
}

const rawGithubReleaseTag = (process.env.VITE_GITHUB_RELEASE_TAG || '').trim();
const autoGithubReleaseTag = resolveGitReleaseRef();
const githubReleaseTag =
  rawGithubReleaseTag &&
  rawGithubReleaseTag !== '<release-tag>' &&
  rawGithubReleaseTag !== '<release_tag>'
    ? rawGithubReleaseTag
    : autoGithubReleaseTag;

export default defineConfig({
  define: {
    'import.meta.env.VITE_GITHUB_RELEASE_TAG': JSON.stringify(githubReleaseTag),
    'import.meta.env.VITE_GITHUB_RELEASE_TAG_AUTO': JSON.stringify(autoGithubReleaseTag),
  },
  build: {
    emptyOutDir: true,
  },
  optimizeDeps: {
    esbuildOptions: {
      define: {
        global: "globalThis",
      },
    },
  },
  server: {
    proxy: {
      "/api": {
        target: "http://127.0.0.1:4943",
        changeOrigin: true,
      },
    },
  },
  plugins: [
    react(),
    environment("all", { prefix: "CANISTER_" }),
    environment("all", { prefix: "DFX_" }),
  ],
  resolve: {
    alias: [
      {
        find: "declarations",
        replacement: fileURLToPath(
          new URL("../declarations", import.meta.url)
        ),
      },
      // --- NUEVO ALIAS PARA SRC ---
      {
        find: "@",
        replacement: fileURLToPath(
          new URL("./src", import.meta.url)
        ),
      },
    ],
    dedupe: ['@icp-sdk/core'],
  },
});