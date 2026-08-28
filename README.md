# DPCommentCapture

大众点评评论抓取越狱插件 — GitHub Actions 自动编译

## GitHub 编译

### 方式1: Fork 后自动编译

1. Fork 本仓库到你的 GitHub 账号
2. 进入仓库 **Actions** 页面
3. 点击 **Build DPCommentCapture** workflow
4. 点击 **Run workflow** 按钮
5. 等待编译完成（约3-5分钟）
6. 在 Artifacts 中下载 `DPCommentCapture-deb`

### 方式2: 本地推送触发

```bash
git init
git add .
git commit -m "DPCommentCapture v1.0"
git branch -M main
git remote add origin https://github.com/<你的用户名>/DPCommentCapture.git
git push -u origin main
```

推送后 GitHub Actions 自动触发编译。

### 方式3: 手动触发

1. 进入仓库 **Actions** 页面
2. 选择 **Build DPCommentCapture**
3. 点击 **Run workflow** → 选择分支 → Run

## 下载 deb

编译成功后:

1. 进入 Actions 运行记录
2. 点击最新一次成功运行
3. 在页面底部 **Artifacts** 区域找到 `DPCommentCapture-deb`
4. 点击下载 → 解压得到 `.deb` 文件

## 安装到设备

```bash
# SSH 安装
scp DPCommentCapture.deb root@<设备IP>:/tmp/
ssh root@<设备IP> "dpkg -i /tmp/DPCommentCapture.deb && killall -9 DPScope"

# 或用 Filza/Sileo 直接安装
```

## 功能

- 悬浮窗 UI（可拖拽）
- 开始/停止评论抓取
- CSV / JSON 导出
- 网络层 + UI层双重抓取

## 抓取原理

### 网络层 Hook
拦截 `NSURLSession`，URL匹配 `reviewlist`/`shopreviewlist`/`commentlist`/`feeddetail` 时解析JSON。

### UI层 Hook
Hook `UILabel setText:` 和 `UITableViewCell layoutSubviews`，文本包含评论关键词时自动抓取。

### 页面 Hook
- `UGCFeedDetailController` — 评论详情页
- `UGCNewReviewListController` — 评论列表页

## 导出路径

```
/var/mobile/Documents/DPCommentCapture/dianping_comments.csv
/var/mobile/Documents/DPCommentCapture/dianping_comments.json
```

## 项目结构

```
DPCommentCapture/
├── .github/workflows/build.yml  # GitHub Actions 编译
├── Makefile                     # Theos 编译配置
├── control                      # deb 包信息
├── DPCommentCapture.plist       # 注入目标配置
├── Tweak.x                      # 主代码(Hook+UI+抓取)
└── README.md
```

## 注意事项

- 需要越狱设备 (checkra1n/unc0ver/palera1n/Dopamine)
- 支持 arm64/arm64e
- 仅注入 `com.dianping.dpscope`
- GitHub Actions 使用 macOS runner + Theos 编译
