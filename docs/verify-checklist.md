# 会话内行为检查清单

以下项目无法用 `verify.sh` 自动断言，需要在 Termux 上启动 `dsh web` 后在会话里逐项执行。
每项都通过才算真机验收完成；失败时保留完整报错原文。

- [ ] **新建文件**：让 agent 用 `write` 创建一个不存在的路径，应成功（验证 SELinux `link(2)` 的 `COPYFILE_EXCL` 兜底）。
- [ ] **重复新建被拒**：对同一路径再次 `write`（create），应被拒并返回 `FS_NOT_OBSERVED`，不得静默覆盖。
- [ ] **读取图片**：`read_image` 读取一张本机 PNG 成功（验证 attachment 的祖先 EACCES 与 hardlink 兜底）。
- [ ] **大输出 spill**：跑 `seq 1 200000`，结果落盘且启动日志中没有 `spilled unsafe root` / `skipped unsafe root`。
- [ ] **会话持久化**：新建会话 → 发一条消息 → 重启 `dsh web` → 会话仍在且可打开（验证 B5 `rename` 发布）。
- [ ] **插件安装（可选）**：`dsh plugin add <包>` 完成后重启，页面正常；若安装把 pristine `@deepseek-ai/*` 拉进 profile 树，再跑 `bash patches/apply.sh --apply` 并重启。
- [ ] **HMR 降级**：修改 profile 的 `cordis.patch.yml` 后不重启，页面不崩；插件操作返回 `restart-required`/`no-hmr` 属预期（Termux 上 HMR 被禁用）。
