import { fileURLToPath, URL } from 'url';
import { execSync } from 'child_process';
import { readFileSync } from 'fs';
import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';
import environment from 'vite-plugin-environment';
import dotenv from 'dotenv';

dotenv.config({ path: '../../.env' });

function resolveMainnetCanisterId(canisterName) {
  try {
    const ids = JSON.parse(readFileSync(new URL('../../canister_ids.json', import.meta.url)));
    return ids?.[canisterName]?.ic || '';
  } catch {
    return '';
  }
}

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

function resolveGitTagRef() {
  try {
    return execSync('git describe --tags --exact-match', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
  } catch {
    return '';
  }
}

function resolveGitCommitRef() {
  try {
    return execSync('git rev-parse --short HEAD', { stdio: ['ignore', 'pipe', 'ignore'] })
      .toString()
      .trim();
  } catch {
    return 'unknown';
  }
}

const mainnetBackendCanisterId = resolveMainnetCanisterId('vox_populi_backend');
const mainnetFrontendCanisterId = resolveMainnetCanisterId('vox_populi_frontend');


const rawGithubReleaseTag = (process.env.VITE_GITHUB_RELEASE_TAG || '').trim();
const autoGitTagRef = resolveGitTagRef();
const autoGitCommitRef = resolveGitCommitRef();
const autoGithubReleaseTag = resolveGitReleaseRef();
const githubReleaseTag =
  rawGithubReleaseTag &&
  rawGithubReleaseTag !== '<release-tag>' &&
  rawGithubReleaseTag !== '<release_tag>'
    ? rawGithubReleaseTag
    : autoGithubReleaseTag;

export default defineConfig({
  define: {
    // DFX_NETWORK fijado a "ic" para que la declaración generada por dfx
    // no llame fetchRootKey() al cargar el módulo en producción.
    'process.env.DFX_NETWORK': JSON.stringify('ic'),
    'process.env.CANISTER_ID_VOX_POPULI_BACKEND': JSON.stringify(mainnetBackendCanisterId),
    'process.env.CANISTER_ID_VOX_POPULI_FRONTEND': JSON.stringify(mainnetFrontendCanisterId),
    'import.meta.env.CANISTER_ID_VOX_POPULI_BACKEND': JSON.stringify(mainnetBackendCanisterId),
    'import.meta.env.CANISTER_ID_VOX_POPULI_FRONTEND': JSON.stringify(mainnetFrontendCanisterId),
    'import.meta.env.VITE_GITHUB_RELEASE_TAG': JSON.stringify(githubReleaseTag),
    'import.meta.env.VITE_GITHUB_RELEASE_TAG_AUTO': JSON.stringify(autoGithubReleaseTag),
    'import.meta.env.VITE_GITHUB_GIT_TAG_AUTO': JSON.stringify(autoGitTagRef),
    'import.meta.env.VITE_GITHUB_COMMIT_SHORT_AUTO': JSON.stringify(autoGitCommitRef),
    'import.meta.env.VITE_BACKEND_CANISTER_ID_IC': JSON.stringify(mainnetBackendCanisterId),
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