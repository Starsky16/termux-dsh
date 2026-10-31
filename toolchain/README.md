# toolchain — Termux 原生工具链

从 `workflow-sync/linux/` 迁入（2026-10-31）；实体只在本目录维护。

| 脚本 | 用途 |
|---|---|
| `flutter.sh` | 把官方 Flutter 的 glibc/x64 dart-sdk 换成 Termux 原生 dart，并给 flutter_tools 打 4 处 “android 当 linux” 补丁 |
| `flutter-glibc-shims.sh` | 用 proot + arm64 rootfs 给 impellerc / gen_snapshot / flutter_tester 等 glibc 宿主工具垫片 |
| `android-sdk-x86-shims.sh` | qemu-user-x86-64 跑 Android SDK 的 x86-64 aapt2 / zipalign / aapt，并写 `aapt2FromMavenOverride` |
| `gradle-seed.sh` | 用 curl 预置 Gradle 分发包到 wrapper 缓存，绕过 Java 侧 DNS |

详细说明见 [`flutter.md`](flutter.md) 与 [`qemu-x86_64.md`](qemu-x86_64.md)。

能力边界（2026-10-25 实测，未因迁入改变）：`flutter analyze` / `pub get` 可用；
`flutter test`、`flutter build apk` 仍不可用（引擎工件 glibc、NDK 工具链 x86-64）。Flutter 出包与运行验证仍走【WIN】。
