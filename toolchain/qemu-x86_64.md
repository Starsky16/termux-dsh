# 从 workflow-sync/linux/qemu-x86_64/README.md 迁入（2026-10-31）

# x86_64 垫片（qemu-user）

在 arm64 Termux 上跑 **x86_64 Linux 工具**。主要用途是 Android SDK 里只有 x86-64 构建的
`aapt2` / `zipalign` / `aapt`——没有它，本地 `flutter build apk` / Gradle 打包会在
`Exec format error` 处直接死掉。

## 原理

```
proot 不需要：aapt2 只是普通 ELF，缺的是 x86_64 的 glibc 与 ld.so
qemu-x86_64 -L <amd64 rootfs> <x86_64 二进制>
```

- `qemu-x86_64`：Termux 包 `qemu-user-x86-64`（11.1.2，Bionic 原生，直接跑）
- `<amd64 rootfs>`：Ubuntu base amd64（约 29MB 下载 / 110MB 解包），只当 sysroot 提供
  `lib/x86_64-linux-gnu/libc.so.6`、`lib64/ld-linux-x86-64.so.2` 等
- shim：`~/Android/Sdk/toolchain-shims/{aapt2,zipalign,aapt}`，内部就是
  `exec env -u LD_PRELOAD qemu-x86_64 -L <rootfs> <真二进制> "$@"`
  （`-u LD_PRELOAD` 必须：Termux 的 `libtermux-exec-ld-preload.so` 是 arm64，
  在 x86_64 进程里加载会刷一堆告警）
- AGP 接线：`~/.gradle/gradle.properties` 里
  `android.aapt2FromMavenOverride=<shim>/aapt2`

## 安装

```bash
pkg install -y qemu-user-x86-64
./android-sdk-x86-shims.sh          # 幂等；rootfs 与 shim 已存在会跳过
~/Android/Sdk/toolchain-shims/aapt2 version   # → Android Asset Packaging Tool (aapt) 2.20-…
```

## 已验证 / 限制

- ✅ `aapt2 version` 0.21s；`zipalign` 正常
- ⚠️ 速度：小输入基本无感；大资源表会明显变慢（qemu 用户态模拟，非 KVM）
- ⚠️ rootfs 解包会报两条硬链接错误（`perl5.38.2`、`uncompress`）——SELinux 禁硬链接所致，
  `android-sdk-x86-shims.sh` 已容错并补成普通副本，对本用途无影响
- 只解决 **CPU 架构**差异，不提供容器隔离；进程仍在 Termux 里跑，共享 home 与网络
- ❌ **NDK 的 C++ 工具链没垫**：`cmake`/`ninja`/`clang` 也都是 x86-64，AGP 直接按绝对路径调用，
  没法像 aapt2 那样用一个 gradle 属性改掉 ⇒ 带原生代码（`jni` 插件）的 Flutter 工程**仍无法本地出 APK**，
  会停在 `:jni:configureCMakeDebug[...]`。

## 配套：Gradle 分发包预置

Java 的 DNS 在本机解析不了 `mirrors.cloud.tencent.com`（报 `UnknownHostException`），
而 curl 能下。用 `gradle-seed.sh <仓库目录>` 把 zip 放进 wrapper 缓存
（目录名 = base36(md5(distributionUrl))，与 Gradle 的 PathAssembler 一致）。
