# javafx-jar2exe

一个基于 Flutter 的 Windows 桌面 GUI 工具，封装 JDK 自带的 `jpackage` 命令，将 JavaFX jar 一键打包成 Windows exe。内置 ProGuard 字节码混淆，支持 class 文件隐藏/加密。

## 功能特性

- **拖拽上传**：直接拖拽 `.jar` 文件到窗口，或点击选择
- **自动解析入口**：扫描 jar 中的 `MANIFEST.MF`、`main` 方法、JavaFX `Application` 子类，列出所有候选 Main-Class 供选择
- **JavaFX 自动识别**：检测 jar 是否依赖 JavaFX，提示填写 JavaFX SDK 路径，自动配置 module-path
- **ProGuard 混淆**：内置 ProGuard 7.6.1，支持类名/方法名混淆，自动保留 JavaFX Controller、FXML 注入字段、`start`/`init`/`stop` 生命周期方法
- **智能模块化**：优先尝试 `jdeps` 模块化打包（class 隐藏在 jimage 中），失败时自动回退到非模块化模式
- **可配置参数**：应用名称、版本、图标、输出目录、JDK 路径、Java 选项、应用参数等
- **实时日志**：流式输出 jpackage/ProGuard/jdeps 命令日志，支持自由复制
- **配置持久化**：自动保存上次配置，重启后恢复
- **输出目录默认**：默认输出到 exe 所在目录的 `output` 子目录
<img width="1920" height="1069" alt="image" src="https://github.com/user-attachments/assets/0a8b4186-40a8-445f-921a-a65080ee32e6" />


## 环境要求

- **JDK 17+**（需包含 `jpackage`、`jlink`、`jdeps`）
- **JavaFX SDK 17**（仅当 jar 是 JavaFX 应用时需要，从 [Gluon](https://gluonhq.com/products/javafx/) 下载）
- **Windows 10/11 x64**

## 快速开始

1. 下载 [Release](../../releases) 中的 `jpackage_gui.exe`
2. 运行 exe，拖拽你的 `.jar` 文件到窗口
3. 选择 Main-Class 入口（如检测到 JavaFX，填写 JavaFX SDK 路径）
4. 点击「开始打包」

生成的 exe 位于输出目录的 `应用名/应用名.exe`。

## 截图

<!-- TODO: 添加截图 -->

## 技术栈

- **Flutter** — Windows 桌面 UI
- **jpackage** (JDK 自带) — Java 应用打包
- **jlink** (JDK 自带) — 最小化 JRE 生成
- **jdeps** (JDK 自带) — 模块化依赖分析
- **ProGuard 7.6.1** — 字节码混淆

## 开发

```bash
flutter pub get
flutter run -d windows
```

构建 release：

```bash
flutter build windows --release
```

## 项目结构

```
lib/
├── main.dart                 # 入口，主题配置
├── models/
│   ├── pack_config.dart      # 打包参数模型
│   └── jar_info.dart         # jar 解析结果
├── services/
│   ├── jar_analyzer.dart     # jar 字节码解析（扫描 main 入口）
│   ├── proguard_service.dart # ProGuard 混淆
│   ├── modularizer.dart      # jdeps 模块化
│   ├── jpackage_service.dart # jpackage 打包
│   ├── pipeline.dart         # 打包流水线
│   ├── jdk_detector.dart     # JDK 检测
│   ├── config_storage.dart   # 配置持久化
│   └── log_types.dart        # 日志类型
├── viewmodels/
│   └── pack_viewmodel.dart   # MVVM ViewModel
└── widgets/
    ├── main_screen.dart      # 主界面布局
    ├── jar_drop_zone.dart    # 拖拽区
    ├── param_form.dart       # 参数表单
    ├── action_bar.dart       # 操作按钮
    └── log_console.dart      # 日志控制台
```

## License

[MIT](LICENSE)
