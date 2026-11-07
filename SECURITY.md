# Security

## 支持范围

当前维护的是最新 Release（当前 `v0.2.1-rc.5-tdsh.5`，pre-release）与 `main` 分支。
更早的 `tdsh.1` / `tdsh.2` 已因原生 addon / libc++ 问题被取代，不再建议使用。

## 报告漏洞

优先使用 GitHub 的私密漏洞报告：

<https://github.com/Starsky16/termux-dsh/security/advisories/new>

如果该入口不可用，请开一个**不含敏感信息**的 issue，说明影响范围与复现方式，
维护者会再约私密通道。不要在公开 issue 中粘贴 token、cookie、API key、完整
profile 配置或设备上的私密路径。

## 范围

本仓关心的问题包括：

- repack 产物被篡改（tag / asset / sha256 不一致）；
- 补丁绕过 dsh 的权限、sandbox 或 web-fetch 边界；
- 原生 addon / node-pty / koffi 的内存安全或符号解析问题；
- `bootstrap.sh` / `wiring` 脚本的路径、软链、权限或下载校验问题；
- CI 供应链问题（npm 源、NDK、第三方源码 pin）。

第三方插件自身的问题请报给插件作者或 `dsh-compat`，不在本仓范围。

## 已知边界

- HMR 在 Termux 上被禁用；插件操作需要重启 `dsh web`。
- `sharp` 使用 wasm32 路径，不是 Android native 包。
- 本仓不提供密钥管理；不要在任何日志/issue 中暴露密钥。
