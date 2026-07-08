# 提交清单

按顺序执行。标 **[代码已就绪]** 的项本次任务（或此前的付费/后端任务）已经在代码里
做完，不需要再改代码，只需要 Trent 做账号侧操作；标 **[Trent 账号操作]** 的是必须
由 Trent 本人在 Apple 开发者账号 / App Store Connect / 第三方服务后台完成的步骤，
Claude 无法代为操作（涉及登录凭证、付费、身份认证）。

## 0. 前置条件

- [x] **Apple Developer Program 账号**——假定已具备（未验证，若还没有需先在
      developer.apple.com 注册，$99/年）。[Trent 账号操作]

## 1. App Store Connect：创建 App 记录

- [ ] 登录 App Store Connect → 我的 App → 新建 App。
  - Bundle ID：`com.trent.Riddle`（与 `project.yml` 的 `bundleIdPrefix: com.trent`
    + target 名 `Riddle` 一致，[代码已就绪]，Trent 只需在 Apple Developer
    后台注册这个 Bundle ID 并在 App Store Connect 里选择它）。
  - App 名称：见 `METADATA.md`——**Trent 需要先拍板中文名**（建议"手泽"）。
  - 主要语言：建议中文（简体），再加英文本地化。
  [Trent 账号操作]

## 2. App 内购买（IAP）

- [ ] 在 App Store Connect 的这个 App 下创建一个**非消耗型（Non-Consumable）**
      内购项目：
  - Product ID：**必须精确等于** `com.trent.Riddle.unlimited`（代码里
    `StoreManager.unlockProductID` 硬编码了这个值，见 `Riddle/StoreManager.swift`
    第 11 行的 FLAG 注释——如果 App Store Connect 里的 Product ID 拼错或不一致，
    购买会加载不出商品）。
  - 定价：**[Trent 待定]**——`Configuration.storekit`（本地模拟器测试用）里当前是
    占位价格 ¥68.00，仅供开发测试参考，**正式定价需要 Trent 在 App Store Connect
    里选定价格等级**，不必与占位价一致。
  - 本地化的显示名称/描述：可参考 `Configuration.storekit` 里已经写好的中文文案
    （"解锁无限" / "解锁无限次回信，纸与笔不再有尽头。"）直接抄进去。
  [Trent 账号操作，产品 ID 固定，价格 Trent 拍板]

## 3. 后端部署（如果决定走 `USE_BACKEND=YES` 生产路径）

- [ ] `cd ~/Desktop/项目/riddle-backend && railway login && railway init &&
      railway add --plugin redis`
- [ ] 设置 Railway 环境变量：`MOONSHOT_API_KEY`、`APP_SHARED_SECRET`（一个长随机串，
      需要与 App 侧 `Secrets.xcconfig` 的 `APP_SHARED_SECRET` 保持一致）。
- [ ] `railway up && railway domain` 拿到正式域名。
- [ ] 把域名填进 `Secrets.xcconfig` 的 `BACKEND_URL`，并把 `USE_BACKEND` 改成 `YES`。
  [Trent 账号操作——涉及 Railway 账号登录与付费部署；域名/密钥回填后的 xcconfig
  改动本身很简单，但不建议 Claude 在没有 Trent 确认的情况下改动生产开关]
- [ ] **如果暂时不想上后端**，也可以先以 `USE_BACKEND=NO`（直连 Moonshot，key 打包进
      App 二进制）提交 v1——**但请注意**：这意味着 Moonshot API Key
      会随 App 二进制分发，存在被反编译提取的风险（`riddle-backend/README.md`
      "Security honest-truth" 一节已经讨论过对应的风险权衡）。是否接受这个风险
      上线 v1、还是先部署后端再提交，是 Trent 的产品决策。[Trent 决策]

## 4. 隐私政策 / 使用条款托管

- [ ] 把 `PRIVACY.md` 的正文（去掉"给 Trent 的落地提示"一节）转成一个可公开访问的
      网页——最简单的方式是用 GitHub Pages（新建一个仓库或用现有的
      `trentct.github.io`，加一个 `riddle/privacy.html`）。
- [ ] 使用条款：本次任务未提供成稿模板，`AboutLinks.termsURL` 目前指向占位地址
      `https://trentct.github.io/riddle/terms`——**需要 Trent 补一份使用条款文本**
      （可以很短：免责声明"回信由 AI 生成，仅供陪伴/记录用途，不构成专业建议"+
      "不对 AI 生成内容的准确性负责"+ 引用隐私政策）。[Trent 待定内容 + 账号操作]
- [ ] 把两个真实 URL 回填到 `Riddle/AboutView.swift` 的 `AboutLinks`
      （当前是占位符 `https://trentct.github.io/riddle/privacy` /
      `.../terms`），以及 App Store Connect 的"隐私政策 URL"字段。
  [Trent 待定 URL 内容，回填这一步是简单的代码改动，Trent 确认好 URL 后可以让
  Claude 代为改这一行]

## 5. 截图

- [ ] 按 `SCREENSHOTS.md` 的分镜清单，在 iPad Pro 13"（或 12.9"）与 iPad Pro 11"
      两组尺寸下各拍 4-6 张。
  [可由 Claude 用模拟器辅助拍摄静态截图；回信书写动画的中间帧建议 Trent 用真机 +
  Apple Pencil 补拍一版更真实的]

## 6. 年龄分级问卷

- [ ] 按 `METADATA.md`"年龄分级"一节的建议作答，尤其是"AI 生成内容"那一项如实
      勾选，预期落在 **17+**。[Trent 账号操作，内容已给出建议]

## 7. Build 归档与上传

- [ ] 确认 `Secrets.xcconfig`（正式发布用的那份，不是 `.example`）已填入真实
      `MOONSHOT_API_KEY` / `MOONSHOT_BASE_URL` / `MOONSHOT_MODEL`，以及（如走后端
      路径）`BACKEND_URL` / `APP_SHARED_SECRET` / `USE_BACKEND=YES`。
- [ ] `xcodegen generate` 确保工程文件是最新的。
- [ ] Xcode 里选 Release 配置 → Product → Archive。
- [ ] Organizer 里 Validate App → 通过后 Distribute App → App Store Connect。
- [ ] 签名方式：`project.yml` 当前是 `CODE_SIGN_STYLE: Automatic`，首次 Archive
      时 Xcode 会提示选 Team——**需要 Trent 登录自己的 Apple Developer 账号**。
  [Trent 账号操作——签名与上传必须用 Trent 的开发者账号身份]

## 8. 提交审核

- [ ] App Store Connect 里选择刚上传的 build，填入 `METADATA.md` 的文案、
      `SCREENSHOTS.md` 的截图、`REVIEW_NOTES.md` 的内容粘贴进"App Review
      Information → Notes"字段。
- [ ] 提交审核（Submit for Review）。
  [Trent 账号操作]

---

## 速览：代码侧 vs Trent 账号侧

| 已在代码里做完（本次或此前任务） | 只能 Trent 做（账号/账单/内容拍板） |
|---|---|
| About/设置页（音效开关、恢复购买、致谢、隐私/条款入口） | 最终 App 名称（中文名候选见 METADATA.md） |
| StoreKit 商品 ID 常量 `com.trent.Riddle.unlimited` | IAP 实际定价 |
| 后端可切换开关 `USE_BACKEND` + `riddle-backend` 项目本身 | Railway 部署 + 环境变量 |
| 隐私政策/使用条款成稿草案（`PRIVACY.md`） | 托管这些文本到真实 URL + 回填代码里的占位链接 |
| 审核备注成稿（`REVIEW_NOTES.md`） | App Store Connect 账号操作、年龄分级问卷作答、提交审核 |
| 截图分镜清单（`SCREENSHOTS.md`） | 真机补拍回信动画中间帧（可选，提升质感） |
