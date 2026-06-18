# 森海克斯8800Pro Web手台写频与管理网页

## 除官方外目前全网唯一支持给森海克斯8800Pro正常蓝牙写频的程序（截至2026.6.18）

注：本项目为第三方社区开源项目，与森海克斯品牌无关
8800Pro Web 是一款面向森海克斯 8800Pro 的浏览器写频工具，使用 React、Vite 和 TypeScript 构建。它把常用信道、区域、VFO、功能菜单、DTMF、FM 收音机、卫星预设、备份导入导出等操作放到一个网页里，尽量减少传统写频软件的安装和平台限制。

## 在线使用

- GitHub Pages：适合公开访问和日常快速使用。
- 自建服务器：适合国内访问场景，服务器版本会显示8800.743.world的 ICP 与公安备案，如需部署到自己的服务器请自行删改

浏览器需使用Chromium内核浏览器。Web Bluetooth 和 Web Serial 都要求安全上下文：线上站点需要 HTTPS，本地调试可以使用 `http://localhost`。

## 主要功能

- 通过 USB 写频线读取和写入 8800Pro。
- 通过蓝牙 BLE 读取和写入频率数据，蓝牙写频使用完整 68 字节 GATT 帧并按两块一组等待 ACK。
- 编辑 8 个区域、512 个信道、VFO A/B、功能设置、DTMF 与 FM 收音机。
- 支持中继库、卫星模式、Excel/CSV/JSON 导入导出和本地备份。
- 支持 USB 写入 128 x 128 RGB565 开机图。
- 蓝牙写开机图暂未开放，当前请使用 USB 写频线完成开机图写入。

## 写频建议

1. 先读频，再修改，再写频。
2. 写频前保存一份 JSON 备份，方便回滚。
3. 蓝牙写频完成后建议立刻再读频一次，确认机器内容与页面一致。
4. 如果浏览器提示蓝牙不可用，确认页面是 HTTPS 或 `localhost`，并使用 Chromium 系浏览器。
5. 如果设备中途断开，重新连接后先读频确认机器内数据，再决定是否继续写入。

## 蓝牙写频状态

8800Pro 的 FFE0/FFE1 蓝牙链路可以完成握手、读频和写频。调试过程中曾经出现过 `404.00657`、`412.00757` 这类乱码频率，最终定位到原因不是 FFE1 本身不能写，而是浏览器端把 `57 addr 40 + 64 bytes` 写频帧拆成 18 字节小包后，机器会把后续碎片当成数据落进信道区。

当前实现使用官方 iOS 应用 RadioKit 框架和本地 CoreBluetooth 实机测试对齐后的策略：

- 握手和普通读写块都走 `FFE1`。
- 每个写频块必须作为一次完整的 68 字节 GATT write 写入。
- 相邻两块连续写完后等待一个 `06` ACK。
- 写频前自动保存本地备份，写频后建议读回确认。

## 本地开发

```bash
pnpm install
pnpm dev
```

默认开发地址：

```text
http://localhost:5173/
```

常用命令：

```bash
pnpm test
pnpm build
pnpm build:server
```

`pnpm build` 用于 GitHub Pages 等普通静态部署；`pnpm build:server` 用于自建服务器版本，会保留页面里的备案号显示。

## 部署说明

### GitHub Pages

仓库内置 GitHub Actions 工作流：

```text
.github/workflows/deploy-pages.yml
```

推送到 `main` 或手动触发 workflow 后，会执行 `pnpm build` 并部署到 GitHub Pages。这个版本默认不显示备案号，避免和自建服务器的合规信息混用。

### 自建服务器

自建服务器部署请使用：

```bash
pnpm build:server
```

构建产物位于 `dist/`。服务器版本会显示：

- 粤ICP备2023143201号
- 粤公网安备44011302005027号

## 技术栈

- React 19
- TypeScript
- Vite
- Web Serial API
- Web Bluetooth API
- IndexedDB 本地备份
- xlsx 导入导出

## 致谢

本项目在协议理解和功能实现过程中参考了社区项目与资料，尤其感谢 `SydneyOwl/senhaix-freq-writer-enhanced` 对森海克斯写频生态的探索。

## 免责声明

写频会直接修改设备内存数据。请确认频率、亚音、功率、带宽等参数符合当地无线电管理规定，并在写入前做好备份。因错误配置、连接中断或不当使用造成的数据丢失、设备异常或合规风险，需要由使用者自行承担。
