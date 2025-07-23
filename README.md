# HostPreferred

- 一个利用了高并发高安全性的 Rust 后端和优雅简洁的 Flutter 前端构建的
- 用于优化 GitHub 和 Cloudflare 等服务 Host 的桌面工具。未来可能添加其他优选 DNS 服务
- 本程序会修改系统 `hosts` 文件，因此启动时会请求管理员权限。

## 功能特性

- 简洁傻瓜式的操作界面
- 基于高效 DoH 的个性化 DNS 优选
- 几乎最优解前后端组合

## 构建与运行

除了两个可选以外都是 ai 写的，无法保证按照该流程一定就能构建成功

在开始之前，请确保您已安装以下环境：

- [Flutter SDK](https://flutter.dev/docs/get-started/install)
- [Rust](https://www.rust-lang.org/tools/install)
- `flutter_rust_bridge_codegen`: `cargo install flutter_rust_bridge_codegen`
- 作者本人构建环境还额外使用 VS2022 安装了一整套“使用 C++的桌面开发”套件

**构建步骤：**

1.  克隆本仓库：
    ```sh
    git clone https://github.com/ytloe/HostPreferred.git
    cd host_preferred
    ```
2.  生成桥接代码：
    ```sh
    flutter_rust_bridge_codegen generate
    ```
3.  构建 Windows 应用同时补全 flutter 依赖（此处展示最优实现）：
    ```sh
    flutter clean
    flutter build windows --tree-shake-icons
    ```
    可执行文件将位于 `build\windows\x64\runner\Release` 目录下。
4.  （可选）使用[upx](https://github.com/upx/upx/releases/)压缩 dll 体积
    ```sh
    cd build\windows\x64\runner\Release
    <upx.exe文件路径> flutter_windows.dll
    <upx.exe文件路径> rust_lib_host_preferred.dll
    ```
5.  （可选）使用[Enigma Virtual Box](https://www.enigmaprotector.com/en/downloads.html)制作单文件
    - 下载安装，左上角 Language 切换为自己能看懂的语言，重启软件
    - 待封包的主程序右侧“浏览”选中构建好的 host_preferred.exe
    - 剩下的 dll 和 data 文件夹一起放入下方的 Virtual Box Files 里面
    - 文件选项勾选“文件压缩”，执行封包

## 注意事项

- 运行优选之前最好先点击保存当前 Host 备份一次
- 最好去备份路径下检查一遍 hosts.bak.hostpreferred 文件
- 再三强调，修改网络的软件无法做到绝对无害，做好回滚的备份绝对没有错

- 由于该程序依赖于 DoH 动态查询最优 DNS，因此需要在网络环境下运行
- 无需每次访问都运行一次软件，仅在访问不了时进入软件优选一次即可

## 特别感谢

本项目受到[HostsManager](https://github.com/tianjiangqiji/Hosts-Manager-For-Github/)项目的启发，但是架构和运行逻辑完全不同
