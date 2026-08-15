# HongGuoFullScreen

适用于红果短剧（Bundle ID: `com.phoenix.video`）的 TrollStore 插件，精简底部 Tab 栏，只保留「首页」和「我的」，让浏览体验更简洁。

## ✨ 功能

- **精简 Tab 栏**：移除「剧场」「商城」「福利」三个底部按钮，只保留「首页」和「我的」
- **自动均匀布局**：保留的两个按钮由系统自动重新分配宽度，视觉均匀美观
- **可随时开关**：双指双击屏幕弹出控制菜单，可随时开启/关闭精简功能
- **默认页面设置**：支持设置应用启动时默认打开「首页」或「我的」
- **无侵入设计**：安装即生效，不影响应用其他功能
- **专为最新版优化**：基于红果短剧最新版本测试，向下兼容

## 📱 效果预览

| 修改前 | 修改后 |
|--------|--------|
| 首页 \| 剧场 \| 商城 \| 福利 \| 我的 | 首页 \| 我的（均匀分布） |

## 🎮 控制菜单

- **双指双击屏幕任意位置**，弹出控制菜单
- 菜单选项：
  - **开启/关闭功能**：切换精简状态（需重启生效）
  - **设置默认打开页面**：选择启动时进入「首页」或「我的」
  - **立即重启**：切换设置后可直接重启应用

## 📦 安装方法

### 使用 TrollStore + TrollFools

1. 下载 `HongGuoFullScreen.deb` 文件
2. 打开 **TrollFools** 应用
3. 在应用列表中找到 **红果短剧**
4. 点击「注入」，选择下载的 `.deb` 文件
5. 注入完成后，**彻底关闭红果短剧**（上划卡片强制退出）
6. 重新打开红果短剧，插件即生效

## 🔨 编译方法

### 云端编译（推荐，无需 Mac）

1. Fork 或克隆本仓库到 GitHub
2. 进入仓库的 **Actions** 页面
3. 手动触发 `Build HongGuo Tweak` 工作流（或在修改 `Tweak.xm` 后自动触发）
4. 构建完成后，在 **Artifacts** 中下载 `HongGuoFullScreen.deb`
5. 解压得到 `.deb` 文件

### 本地编译（需要 Mac + Theos）

```bash
# 1. 安装 Theos
git clone --recursive https://github.com/theos/theos.git "$HOME/theos"

# 2. 进入项目目录
cd HongGuoFullScreen

# 3. 编译打包
make package FINALPACKAGE=1

# 4. 产物在 packages/ 目录下
ls -la packages/
```

## 📁 文件结构

```
HongGuoFullScreen/
├── .github/
│   └── workflows/
│       └── build.yml          # GitHub Actions 自动编译（仅 Tweak.xm 变更时触发）
├── Tweak.xm                   # 核心代码（Hook SSTabBar & SSTabBarController）
├── Makefile                   # Theos 编译配置
├── HongGuoFullScreen.plist    # 过滤配置（仅注入红果短剧）
├── control                    # Debian 包描述
└── README.md                  # 本文件
```

## 🛠️ 技术原理

- **Hook `SSTabBar` 的 `setItems:animated:`**：在 TabBar 设置按钮时，过滤掉「剧场」「商城」「福利」，只保留「首页」和「我的」
- **Hook `SSTabBarController` 的 `setSelectedIndex:`**：拦截索引切换，检测到选中「剧场」时自动重定向到「我的」，解决过滤后点击「我的」跳转错乱的问题
- **Hook `UIWindow` 添加双指双击手势**：用于弹出控制菜单
- **利用 `NSUserDefaults` 存储设置**：开关状态和默认页面设置持久化
- **系统自动布局**：不手动调整 frame，由系统均匀分配剩余按钮

## ⚠️ 注意事项

- 本插件仅适配红果短剧（Bundle ID: `com.phoenix.video`），其他应用版本可能需要调整
- 注入后如未生效，请彻底关闭红果短剧后台（上划卡片强制退出）再重新打开
- 切换功能或默认页面后，**需要重启应用才能生效**（菜单中提供「立即重启」选项）
- 如需卸载，在 TrollFools 中点击「移除注入」即可恢复原始界面

## 📄 许可证

本项目仅供学习交流使用，请勿用于商业用途。

## 🤝 贡献

欢迎提交 Issue 和 Pull Request 改进本项目。
