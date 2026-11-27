# Azure TTS Cached for PopClip

[English README](README.md)

这是一个 PopClip 扩展：将选中的文字发送到 Azure AI Speech 生成语音，把 MP3 缓存在本地，并通过 VLC 播放。

## 功能

- 使用 Azure 神经网络语音合成，区域、语言和声音均可配置
- 本地缓存生成的 MP3，相同文字和设置不会重复请求 Azure
- 提供 `1.0x` 和 `0.8x` 两种播放速度
- 通过 VLC 原生远程控制实现暂停和继续
- 播放时 PopClip 控制按钮保持显示
- Azure 订阅密钥以 PopClip 隐藏字段保存

## 使用要求

- 安装了 [PopClip](https://www.popclip.app/) 的 macOS
- [VLC media player](https://www.videolan.org/vlc/)
- Azure AI Speech 资源及其订阅密钥

扩展会在以下位置查找 VLC：

```text
/Applications/VLC.app/Contents/MacOS/VLC
/opt/homebrew/bin/vlc
/usr/local/bin/vlc
```

## 安装

1. 下载或克隆此仓库。
2. 在 Finder 中双击 `AzureTTSCached.popclipext`。
3. 在 PopClip 中确认安装。
4. 打开扩展设置，填写 Azure 订阅密钥。

修改扩展文件后，需要重新安装扩展包。

## 配置项

| 配置 | 默认值 | 说明 |
| --- | --- | --- |
| Azure Region | `eastus` | Azure Speech 资源所在区域 |
| Azure Subscription Key | — | Speech 资源 API 密钥，以隐藏字段保存 |
| Audio Output | `audio-16khz-32kbitrate-mono-mp3` | Azure 音频输出格式 |
| Locale | `en-US` | 语音合成语言 |
| Voice | `en-US-JennyMultilingualNeural` | Azure 神经网络声音名称 |

## 使用方法

选中文字后，PopClip 会显示三个动作：

| 图标 | 功能 |
| --- | --- |
| 波形 | 使用 `1.0x` 从头播放 |
| 播放/暂停 | 暂停或继续当前 VLC 播放 |
| 乌龟 | 使用 `0.8x` 从头播放 |

点击新的 `1.0x` 或 `0.8x` 会停止之前的播放。暂停和继续控制同一个 VLC 进程，因此可以保留播放位置。

## 缓存与运行状态

生成的音频和播放器状态保存在：

```text
~/Library/Caches/PopClipAzureTTS
```

播放速度不参与音频缓存键计算，因此两种速度会复用同一份 MP3。缓存键包含选中文字、Azure 区域、语言、声音和输出格式。

如需清理语音缓存，请先停止播放，再删除该缓存目录中的内容。

## 故障排查

- **点击后显示 X：**确认 VLC 已安装，并检查 Azure 密钥和区域。
- **新文字无法播放：**确认 Mac 可以访问所配置的 Azure Speech 服务地址。
- **缓存文字能播放，新文字不能播放：**通常是 Azure 请求失败，请检查密钥、区域、额度和网络。
- **暂停/继续无响应：**确认防火墙或安全工具没有阻止 VLC 的本机回环控制端口。

VLC 远程控制仅绑定 `127.0.0.1`，并从 `43177–43197` 范围选择空闲端口。

## 项目结构

```text
AzureTTSCached.popclipext/
├── Config.yaml  # PopClip 动作与设置
└── azure.sh     # Azure 请求、缓存、VLC 播放与控制
```
