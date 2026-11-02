# E5Keeper

给 macOS 用的 Microsoft 365 E5 开发者订阅保活小工具。原生 SwiftUI，菜单栏常驻，1.7 MB，无 Electron、无 Docker、无后台守护进程。

![界面](docs/screenshot.png)

> 背景：官方的 **E5 Renew Plus** 只有 Windows 版（.NET 6 WinForms），没有 macOS 版，也没开源；
> 前身 **E5 Renew X** 的源码虽是公开的（C#/.NET Web 服务），但要么装 .NET 运行时、要么上 Docker，都谈不上"轻量"。
> 这个是我按同样思路重写的 macOS 原生版，只保留最核心的保活逻辑。

## 功能

- 随机间隔调用 Microsoft Graph（默认 120–480 秒随机，每轮 1–8 个接口）
- 43 个只读接口随机组合，顺序、内容、间隔都随机
- 可选"写入模式"：在 OneDrive 根目录建一个临时 txt 再删掉（默认关闭）
- 可选"只在指定时段运行"
- 设备代码登录（不用配重定向 URI，浏览器输个码就行）
- refresh_token 自动轮换并落盘，access_token 过期前自动续
- 连续 3 次鉴权失败自动暂停，防止账号被风控
- 菜单栏图标：运行中 / 已暂停一眼可见

## 上手三步

**1. 注册一个 Azure 应用**（用你的 E5 管理员账号）

1. 打开 <https://entra.microsoft.com> → 应用注册 → 新注册
2. 名称随便填，账户类型选"仅此组织目录中的账户"
3. 重定向 URI 留空；注册完进「身份验证」→ 打开 **允许公共客户端流** = 是
4. 「API 权限」→ 添加权限 → Microsoft Graph → **委派权限**，至少勾：
   `User.Read`、`User.Read.All`、`Files.Read.All`、`Mail.Read`、`Calendars.Read`、
   `Contacts.Read`、`Notes.Read`、`Tasks.Read`、`Sites.Read.All`、`Directory.Read.All`
   勾完点「代表 你的组织 授予管理员同意」
   （要写入模式再加 `Files.ReadWrite.All`）
5. 记下「概述」里的 **应用程序(客户端) ID** 和 **目录(租户) ID**
6. 想用机密客户端的话，再去「证书和密码」建一个客户端密码；用公共客户端可以不建

**2. 填进 app**

打开 E5Keeper 设置窗口（首次启动会自动弹出；之后从菜单栏图标的「设置…」进），
填租户和客户端 ID，点 **设备代码登录**。

**3. 浏览器授权**

浏览器会自动打开 <https://microsoft.com/devicelogin>，输入窗口里显示的 9 位代码，
用 E5 账号登录并同意。回来后 app 会自动保存 refresh_token 并开始跑。

> 建议单独建一个不带管理员权限的用户来做保活，别用全局管理员账号。
> 一定不要给这个账号开双重验证，否则刷新令牌拿不到。

## 关于安全

- 令牌和客户端密码存在 `~/Library/Application Support/E5Keeper/secrets.json`，权限 `600`（仅本人可读）
- 默认全程只读，不会往你邮箱/网盘里塞垃圾；写入模式会自己把文件删掉
- 没有任何外发上报，日志只在本机

## 编译与安装

```bash
cd E5Keeper
./install.sh        # 编译 + 安装到 /Applications + 启动
```

只想要产物不安装：`./build.sh`，产物在 `build/E5Keeper.app`，自己拖到哪都行。

要求：macOS 14+、装了 Xcode 或 Command Line Tools。脚本用 `swift build` 编译，ad-hoc 签名，
不需要开发者账号。想开机自启就把 `/Applications/E5Keeper.app` 加进「系统设置 → 通用 → 登录项」。

配置和令牌存在用户目录（`~/Library/Application Support/E5Keeper`），换位置、重编译都不会丢，不用重新登录。

## 已知局限

- **续订本身是玄学**。这类工具只是把"活跃度"做上去，提高概率，没有任何保证。
- Mac 合盖就睡，睡眠期间不会调用。想要 7×24 就挂服务器 / NAS，或者用 `caffeinate` 顶着。
- 抓不到 401/403 的接口（比如缺 `Directory.Read.All`）只会在日志里记一条，不影响其他调用。
- 只在 macOS 14+ 测试过；没有沙盒化，没上架 App Store（也不需要）。

## 目录

```
E5Keeper/
├── Sources/
│   ├── App.swift          # 入口、菜单栏、设置窗口
│   ├── Engine.swift       # 调度循环、OAuth、调用逻辑
│   ├── GraphAPI.swift     # 接口池与 HTTP
│   ├── SettingsView.swift # 设置界面
│   ├── Store.swift        # 本地存储
│   ├── Models.swift       # 数据结构
│   └── Snapshot.swift     # 开发用：--snapshot 离屏渲染界面
├── Info.plist
├── make_icon.swift        # 生成图标
├── build.sh
└── install.sh
```

## 声明

非官方工具，与 Microsoft 无任何关系。仅用于让你自己的开发者订阅保持活跃，
是否续订由微软单方面判断，本项目不做任何承诺。使用风险自负，别拿它挂重要数据。

