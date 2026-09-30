# javafx-jar2exe

一个基于 Flutter 的 Windows 桌面 GUI 工具，封装 JDK 自带的 `jpackage` 命令，将 JavaFX jar 一键打包成 Windows exe。内置 ProGuard 字节码混淆（混淆方法名/字段名）以防反编译。

## 功能特性

- **拖拽上传**：直接拖拽 `.jar` 文件到窗口，或点击选择
- **自动解析入口**：扫描 jar 中的 `MANIFEST.MF`、`main` 方法、JavaFX `Application` 子类，列出所有候选 Main-Class 供选择
- **JavaFX 自动识别**：检测 jar 是否依赖 JavaFX，提示填写 JavaFX SDK 路径，自动配置 module-path
- **ProGuard 混淆**：内置 ProGuard 7.6.1，混淆方法名/字段名；自动保留入口类与 JavaFX Controller 的类名（FXML 靠类名反射实例化），以及 FXML 注入字段、`start`/`init`/`stop` 生命周期方法
- **依赖自动补齐**：用 `jdeps` + 嵌套 jar 分析出应用实际依赖的 JDK 模块（如 `java.logging`、`java.sql`、`jdk.crypto.ec`）并链入 runtime，避免产物运行期抛 `NoClassDefFoundError`
- **可选模块化打包**：可将 class 隐藏进 jimage（体积更小、更难提取）。**默认关闭**，因为命名模块下 `Class.getResource` 不再回退到系统类加载器，应用若用 `new Image("logo/x.png")` 这类非 package 路径加载资源会启动失败
- **可配置参数**：应用名称、版本、图标、输出目录、JDK 路径、Java 选项、应用参数等
- **实时日志**：流式输出 jpackage/ProGuard/jdeps 命令日志，支持自由复制
- **配置持久化**：自动保存上次配置，重启后恢复
- **输出目录默认**：默认输出到 exe 所在目录的 `output` 子目录

## 环境要求

- **JDK 17+**（需包含 `jpackage`、`jlink`、`jdeps`）
- **JavaFX SDK 17**（仅当 jar 是 JavaFX 应用时需要，从 [Gluon](https://gluonhq.com/products/javafx/) 下载）
- **Windows 10/11 x64**

## 快速开始

1. 从 [Releases](../../releases/latest) 下载 `javafx-jar2exe-vX.Y.Z-windows-x64.zip` 并解压
2. 运行解压目录中的 `jpackage_gui.exe`
3. 拖拽你的 `.jar` 文件到窗口
4. 选择 Main-Class 入口（如检测到 JavaFX，填写 JavaFX SDK 路径）
5. 点击「开始打包」

生成的 exe 位于输出目录的 `应用名/应用名.exe`。

### 关于「隐藏 class」

默认走 **classpath 打包**，产物 `app/` 下会保留 jar，但其中的方法名/字段名已被 ProGuard 混淆。若要把 class 真正藏进 jimage，可在参数表单中开启「模块化打包」——但请先确认你的应用**没有**从非 package 目录加载资源，例如：

```java
new Image("logo/x.png")                 // logo/ 下没有 .class，不是 JPMS package
getClass().getResource("config/app.json")  // 同理
```

开启模块化后这类资源会找不到，产物启动即抛 `IllegalArgumentException: Invalid URL or resource not found`。

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
│   ├── nested_jar_analyzer.dart # 嵌套 jar（lib/*.jar）的模块依赖分析
│   ├── modularizer.dart      # jdeps 模块化（可选）+ 依赖分析
│   ├── jpackage_service.dart # jpackage 打包
│   ├── pipeline.dart         # 打包流水线
│   ├── jdk_detector.dart     # JDK 检测
│   ├── config_storage.dart   # 配置持久化
│   └── log_types.dart        # 日志类型
├── theme/
│   └── app_theme.dart        # 主题与设计系统（色板/卡片/渐变按钮）
├── viewmodels/
│   └── pack_viewmodel.dart   # MVVM ViewModel
└── widgets/
    ├── main_screen.dart      # 主界面布局
    ├── jar_drop_zone.dart    # 拖拽区
    ├── param_form.dart       # 参数表单
    ├── action_bar.dart       # 操作按钮
    ├── log_console.dart      # 日志控制台
    └── about_dialog.dart     # 关于对话框（版本信息）
```

## License

[MIT](LICENSE)
