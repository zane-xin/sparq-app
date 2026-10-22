# Sparq 安装包

该目录是可以直接部署的 Sparq 默认应用，不包含数据库、日志、上传文件、已安装插件或主题。

首次运行前不需要手动创建 `run/` 或 `storage/`，Web 安装流程会完成基础目录和配置初始化。默认配置位于 `config/app.yaml`，完整配置参考位于 `config/app.example.yaml`。

macOS 或 Linux：

```bash
./sparq
```

Windows：

```powershell
.\sparq.exe
```

启动后按照终端输出访问安装页面。安装完成后，运行数据会保存在 `sparq` 可执行文件所在目录的 `storage/`，插件和主题分别保存在同级的 `plugins/` 与 `themes/`；从其他工作目录启动也会使用该目录。升级或重新解压安装包时不要覆盖这些用户资产。

`manifest.json` 描述安装包版本、目标平台和文件摘要，`checksums.txt` 可用于校验包内文件是否完整。
