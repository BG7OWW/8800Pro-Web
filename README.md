# 8800Pro Web

Web programmer for the Senhaix 8800Pro, built with React, Vite, and TypeScript.

## Features

- Read and write channels, settings, and boot image data
- USB serial and Bluetooth Low Energy support
- New-user friendly workflow with guided pages and inline help
- GitHub Pages friendly build with relative asset paths

## Local development

```bash
pnpm install
pnpm dev
```

## Build

```bash
pnpm build
```

For the self-hosted server version with the备案号 footer, use:

```bash
pnpm build:server
```

## GitHub Pages

This repository includes a GitHub Actions workflow at `.github/workflows/deploy-pages.yml`.
To deploy the site on GitHub Pages, enable Pages for the repository and set the source to GitHub Actions.

