# termux-dsh

在 Termux（Android arm64）上一条命令装好 [dsh](https://github.com/deepseek-ai/deepseek-harness)，并打上 Android 必需补丁。

## 安装

```bash
pkg install -y git && git clone https://github.com/Starsky16/termux-dsh.git ~/code/termux-dsh
bash ~/code/termux-dsh/bootstrap.sh
```

## 能力边界

| 能做 | 不能做（走 WIN/CI） |
|---|---|
| dsh web + 插件 + LAN 远程 | Flutter `test` / `build apk` |
| `flutter analyze` / `pub get` | WPF / WinRT 目标 |
| `dotnet build` 插件类（EnableWindowsTargeting） | office 转换（缺 soffice） |

## 结构

```
bootstrap.sh                 一条命令：环境 → 装 dsh → 补丁 → env → 接线 → verify
verify.sh                    真机回归
patches/{manifest.json,apply.sh,core/,compat/,local/}   补丁引擎（check/apply/revert）
profile/{overrides.yml,plugins.sh}                      profile 覆盖与插件按序安装
wiring/link-workspace.sh     两槽记忆/技能/hooks/bin/plans 接线
toolchain/*.sh               flutter / glibc-shims / android-sdk-x86-shims / gradle-seed
```

## 已知问题

见 `PATCHES.md`（每条补丁：症状 → 根因 → 改法 → 适用版本）。

## 关联

- [dsh-compat](https://github.com/Starsky16/dsh-compat)：插件兼容层（L3 垫片 + L4 门禁）；本仓承担 L1 平台补丁与 L2 加载器补丁。
- 分层说明见 workflow-sync 仓 `plans/2026-10-27-termux-dsh自建仓库.md` 与 `plans/2026-10-27-dsh插件兼容层.md`。

## License

MIT。上游与第三方归属见 `NOTICE`。
