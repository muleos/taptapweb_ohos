# TapTapWeb

鸿蒙网页封装（原 nas_nav_hormony），把 TapTap 网页当独立应用使用。

- 主页地址：https://www.taptap.cn/（可在应用内下拉修改为任意网址）
- 包名：com.hmos.taptapweb
- 应用名：TapTapWeb

## 功能

1. 下拉点设置按钮，填写主页地址，点保存即可。
2. 下拉默认为刷新及功能按钮（3秒缩回）。
3. 侧滑返回上一页。
4. 网页深浅色模式自动适配系统；设置中可打开"强制深色模式"。
5. 网页内跳转第三方应用链接（如 taptap:// 等应用深链）时自动拉起对应外部应用；未安装时提示。
6. 可以最多开启5个分身。
7. 其它的自行摸索。

## 构建

本地 AppScope/app.json5 已声明 bundleName `com.hmos.taptapweb`；若使用自有工程外壳，请把 bundleName 同步改为 `com.hmos.taptapweb`。

安装：用小白安装。
