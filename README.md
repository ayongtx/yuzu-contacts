# 柚柚通讯录（ContactsPro）

一款 iOS 本地通讯录应用：苹果通讯录的核心体验 + 四个实用创意功能。
数据全部存本机，不联网、不注册、不上传任何服务器。

| 项目 | 说明 |
|---|---|
| 最低系统 | iOS 17 |
| 数据框架 | SwiftData（本地存储） |
| 界面 | SwiftUI 原生 |
| 交付物 | 未签名 IPA → 用爱思助手自签安装 |

---

## 功能清单

### 基础（对齐苹果通讯录）
- 联系人列表：A-Z 拼音分组 + 右侧索引条（支持滑动快速定位）
- 搜索：姓名 / 公司 / 号码 / 拼音全拼 / 拼音首字母（如输 `zs` 找到张三）
- 联系人详情：多号码（可设主号）、邮箱、地址、纪念日、备注、标签
- 新建 / 编辑 / 删除；一键拨号、短信、邮件
- 常用联系人置顶；滑动标星、滑动删除
- 文字头像自动生成（按名字哈希配色，稳定不闪变）
- 6 套主题色可切换

### 创意功能
1. **T9 九宫格检索**——数字键直接找联系人：`94264`→张、`726`→三、`97`→张三首字母；输号码 `138` 也能按号码命中；没匹配到时可直接拨打输入的号码
2. **隐私保险箱**——把指定联系人锁起来：主列表、搜索、九宫格、雷达里全都看不见；支持面容 ID / 触控 ID，附 PIN 兜底（自签证书偶尔拿不到生物识别权限时仍可进入）；退出 App 自动上锁
3. **名片二维码**——把自己的名片做成二维码，对方用相机一扫即存；支持保存到相册
4. **雷达**——近期 60 天生日倒计时 + 自动生成四种风格的祝福文案（可复制/直接发短信）；超过设定天数没联系的人会提醒，点一下就能拨打
5. **通讯录体检 + 智能去重**——给通讯录打健康分，自动揪出：重复联系人（同名/同号码，一键合并）、没有号码的、没有姓名的、号码位数可疑的、信息太单薄的
6. **备份互通**——导出/导入标准 vCard（.vcf），可和系统通讯录、Outlook、Google 通讯录互通；支持一键从系统通讯录导入

---

## 怎么把它变成 IPA（GitHub 云编译，免费）

> 原理：GitHub 免费提供 macOS 云服务器。把代码传上去，它自动用 Xcode 编译，产出「未签名 IPA」给你下载。全程不需要 Mac。

### 第 1 步：把项目传到 GitHub

**方式 A：网页上传（不会命令行用这个）**
1. 打开 github.com，注册/登录
2. 右上角 **+** → **New repository**，名字随便（如 `contacts-pro`），选 Private 或 Public 都行，点 **Create repository**
3. 仓库页面点 **uploading an existing file**
4. 把 `ContactsPro` 文件夹里的**所有内容**拖进去（注意：`.github` 是隐藏文件夹，先在资源管理器勾选「显示隐藏项目」才能看到）
5. 点 **Commit changes**，等待上传完成

**方式 B：命令行（推荐，以后改代码方便）**
```bash
cd ContactsPro
git init
git add .
git commit -m "init"
# 在 GitHub 建好空仓库后（不要勾 README）：
git remote add origin https://github.com/你的用户名/contacts-pro.git
git branch -M main
git push -u origin main
```

### 第 2 步：跑编译

1. 仓库页面顶部点 **Actions** 标签
2. 左侧选 **Build Unsigned IPA**
3. 右侧点 **Run workflow** → **Run workflow**
4. 等待 3~5 分钟，出现绿色 ✓
5. 点进这次运行，页面底部 **Artifacts** 里下载 **ContactsPro-unsigned-ipa**
6. 下载的是 zip，解压得到 **ContactsPro-unsigned.ipa**

> 以后改了代码 push 上去，会自动重新编译，不用手动点。

---

## 怎么用爱思助手自签安装

1. 电脑安装[爱思助手](https://www.i4.cn/)，iPhone 用数据线连上电脑
2. 爱思助手顶部 → **工具箱** → **IPA 自签**（有的版本叫「IPA 签名」）
3. 选「**使用 Apple ID 签名**」：
   - Apple ID：输入你的普通 Apple ID 邮箱（不用开发者账号）
   - 密码：⚠️ 需要的是 **App 专用密码**，不是登录密码。去 [appleid.apple.com](https://appleid.apple.com) 登录 → 登录和安全 → App 专用密码 → 生成一个，粘贴进来
4. 选择下载好的 `ContactsPro-unsigned.ipa`
5. 点**开始签名**，完成后点**安装**，装到手机
6. 手机上第一次打开会提示「不受信任的开发者」：
   **设置 → 通用 → VPN 与设备管理** → 找到你的 Apple ID → 点**信任**
7. 打开 App，完成

### 必须知道的限制（免费个人签名的规则）
| 规则 | 说明 |
|---|---|
| 证书 7 天有效 | 7 天后 App 打不开，重新连爱思助手签一次即可。**数据不会丢**（存在 App 沙盒里，重签不影响） |
| 最多 3 个自签 App | 免费 Apple ID 同时只能签 3 个不同的 App |
| 换设备/重签 | 每次签名建议用同一个 Apple ID，Bundle ID 会保持 `com.cenglou.contactspro` |

---

## 目录结构

```
ContactsPro/
├── project.yml                     # XcodeGen 工程定义（含 Info.plist 配置）
├── .github/workflows/build-ipa.yml # 云编译脚本
├── tools/make_icon.py              # 图标生成脚本（纯 Python，无依赖）
└── ContactsPro/                    # Swift 源码
    ├── App/                        # 入口、主框架、示例数据
    ├── Models/                     # 数据模型（SwiftData）
    ├── Services/                   # 拼音 / T9 / 去重 / 体检 / vCard / 安全
    ├── Views/                      # 各页面
    └── Assets.xcassets/            # 图标、主题色
```

## 常见问题

**编译失败？**
- 看 Actions 里的红色 ✗，点进去看日志最后 30 行。99% 是源码笔误，把报错行号发给我即可修。

**安装后闪退？**
- iOS 17 以下不支持。到 设置→通用→关于本机 确认版本。

** Face ID 不可用？**
- 正常现象，自签证书有时拿不到该权限。App 已内置 PIN 兜底：保险箱 → 设置 4 位 PIN。

**想把数据搬到新手机？**
- 更多 → 导出备份（.vcf）→ 新手机装好本 App → 更多 → 从 .vcf 文件导入。

## 修改 App 名字

改 `project.yml` 里的 `CFBundleDisplayName`（默认「柚柚通讯录」），push 后自动重新编译。
