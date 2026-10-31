# 从 workflow-sync/linux/flutter-termux/README.md 迁入（2026-10-31）

# Flutter on Termux（原生 arm64）

官方 Linux 包在本机跑不起来，原因是两个「x64 + glibc」假设：

| 组件 | 问题 | 处理 |
|---|---|---|
| `bin/cache/dart-sdk` | glibc 二进制，exec 报 `Exec format error` | 换成 Termux 原生 `dart-sdk`（**版本必须一致**：3.47.8 ↔ Dart 3.13.7） |
| `bin/cache/flutter_tools.snapshot` | 预编译成 `x64 linux` VM 快照，arm64 VM 拒绝加载 | 用 Termux dart 重编该快照 |
| `flutter_tools` 源码 | 只认 linux/macos/windows，`android` 直接抛 `Unsupported host platform` | 打 4 处「android 当 linux」补丁（见 `flutter.sh`） |
| `platform-tools/adb` | SDK 自带 x86_64 版 | 换成 Termux 的 `adb`（`apply` 后手动 `ln -sf`，否则 doctor 报多份 adb） |

```bash
pkg install dart which unzip xz-utils openjdk-21
# 解包官方 flutter_linux_3.47.8-stable.tar.xz 到 ~/flutter 后：
./flutter.sh
export ANDROID_HOME=$HOME/Android/Sdk
flutter doctor
```

## 能力边界（2026-10-25 实测）

| 命令 | 结果 |
|---|---|
| `flutter --version` / `flutter doctor` | ✅ 全绿（Chrome 缺失无关） |
| `flutter pub get` | ✅ 走 pub.flutter-io.cn |
| `flutter analyze` | ✅ MistakePrint 实测 `No issues found`（9.6s） |
| `flutter test` | ❌ `FlutterTester supports only Linux, Windows and MacOS`；且宿主机引擎工件只有 glibc 版 |
| `flutter build apk` | ❌ SDK 的 `aapt2`/`zipalign` 是 **x86_64 glibc** 二进制，arm64 跑不了；要本地出包需 qemu-x86_64 + x86_64 rootfs（慢 5–20 倍） |

⇒ 本机定位：**静态检查 / 依赖解析 / 代码浏览**；出包仍按规则走 CI（`dev-build`）或云端 WIN。

## 进一步：把 Linux 宿主工具也垫起来（flutter-glibc-shims.sh）

Flutter 的宿主工具（`impellerc` / `gen_snapshot` / `flutter_tester`）是 **arm64 但 glibc 链接**——
架构对、运行时不对。`flutter-glibc-shims.sh` 用 proot + 一份 arm64 rootfs 让它们原生执行（无 CPU 模拟）：

```bash
./flutter-glibc-shims.sh        # 幂等；原文件保留为 <name>.glibc
```

垫上之后 `flutter build apk --debug` 能一路走到 **Gradle → AGP → aapt2(垫) → Flutter assemble → shader 编译**，
最后仍停在 NDK 的 x86-64 CMake（见 `qemu-x86_64.md` 的边界说明）。
`flutter precache --force` 会覆盖这些垫片，重跑 `flutter-glibc-shims.sh` 即可。
上游若改坏锚点，`flutter.sh` 会明确报「找不到唯一锚点」，按提示更新锚点即可。
