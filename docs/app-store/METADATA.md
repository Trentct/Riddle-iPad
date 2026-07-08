# App Store 上架文案（草案）

本文件是提交给 App Store Connect 的文案草案。标 **[Trent 待定]** 的字段是 Trent 需要
最终拍板的（名字、价格已在别处 FLAG 过，这里统一再收口一次）；其余字段是可以直接抄进
App Store Connect 表单的成稿，供 Trent 审阅/微调。

## 名称 [Trent 待定]

- 英文：**Riddle**（沿用仓库名，也是 MaximeRivest/Riddle 的致敬）
- 中文候选：**手泽** / **纸间** / **归野日记** / **墨迹**——建议 **手泽**：既是 App 里第六款
  笔迹的名字（SDT 轨迹字库），也是"信件手泽尚存"的古语，贴合"纸会记得"的产品调性，且不与
  已上架 App 撞名（未做详尽查重，提交前 Trent 需在 App Store Connect 里实测名称可用性）。
- **两个市场分别配置**：中国区用中文名，其余区域用英文名 Riddle——App Store Connect
  支持按 App 信息的本地化语言分别填名称，不需要为两个市场分别建两个 App。

## 副标题 Subtitle（30 字符内，App Store 明面展示）

- 英文：`Write. It writes back.`
- 中文：`写下去，它会回信`

## 促销文本 Promotional Text（170 字符内，可随时改不需要重新审核）

- 英文：
  > No chat bubbles, no buttons. Write on the page with your finger or
  > Apple Pencil, rest your pen, and watch an answer appear in ink —
  > stroke by stroke, then fade away.
- 中文：
  > 没有聊天气泡，没有按钮。用手指或 Apple Pencil 在纸上写字，搁笔，看着回信一笔一笔
  > 浮现，然后淡去。

## 完整描述 Description

### 中文（简体）

```
这是一本会回信的日记。

翻开它，你会看到一页空白的纸——没有输入框，没有发送键，没有聊天气泡。
用手指或 Apple Pencil 写下心事，搁笔片刻，纸上的墨迹会浮现出一封回信，
一笔一笔，像有人正在读你写下的字，然后提笔作答。回信写完，墨迹会慢慢淡去，
就像真正的信——读过了，就留在心里，不必留在屏幕上。

圈起一种字迹，日记便用它回信：
· 归野——温厚的老友，话不多，但句句落在心上
· 沈砚——旧派的读书人，言语持重，礼数周全
· Ashford——住在日记里的存在，永远用英文回信，好奇又体贴

写满一页，双指一划，翻到下一页继续写。想换一种纸，圈住纸角的落款即可合上本子，
换一位笔友重新开始。

这是一个安静的地方。没有点赞，没有关注者，没有人看见你写的字——除了在纸间
回信的那个人。

灵感与核心算法致敬 MaximeRivest/Riddle（开源项目，MIT 协议）。
```

### 英文

```
A diary that writes back.

Open it and you'll find a blank page — no text field, no send button,
no chat bubbles. Write with your finger or Apple Pencil, rest your pen,
and an answer surfaces in ink, stroke by stroke, as if someone were
reading what you wrote and picking up a pen to reply. When the reply is
finished, the ink slowly fades — like a real letter: once read, it
stays with you, not on the screen.

Circle a handwriting style, and the diary replies in it:
· Guīyě — a gentle old friend, few words, all of them landing where it counts
· Shěnyàn — an old-school scholar, measured and courteous
· Ashford — a presence living in the diary, always replies in English,
  curious and warm

Fill a page, swipe with two fingers to turn it, and keep writing. Want
a different paper? Circle the signature in the corner to close the
book and start again with a different hand.

This is a quiet place. No likes, no followers, no one sees what you
write — except whoever writes back.

Handwriting-synthesis algorithm and diary persona are an homage to
MaximeRivest/Riddle (open source, MIT).
```

## 关键词 Keywords（中国区 100 字符内，逗号分隔，无空格）

```
日记,手写,笔记,AI日记,治愈,书信,ApplePencil,墨水,写字,情绪
```

英文区：

```
diary,journal,handwriting,ai,pencil,ink,letter,calm,writing,notebook
```

## 分类 Category [建议，Trent 拍板]

- 主分类：**Lifestyle（生活方式）**
- 副分类：**Entertainment（娱乐）** 或不选

**理由**：App 核心行为是"写日记 + 收到回信"，产品定位更接近私人书写/自我表达工具
（同类：Day One、Reflectly 用 Lifestyle/Health & Fitness），而不是游戏化娱乐；但因为
含 AI 对话生成内容、无生产力工具属性（不导出、不搜索、不打印），归 Productivity 也不够
贴切。避开 Health & Fitness——那个类目审核对"情绪/心理健康"类应用有更严格的免责声明
要求，而 Riddle 不是心理健康工具，不应暗示这类定位。

## 年龄分级 Age Rating（App Store Connect 问卷作答建议）

- **模拟赌博/烟酒毒品/色情/暴力等传统选项**：均选"无"——App 本身不含这些内容，页面
  是纯文字回信。
- **关键项——"未过滤的网络内容 / 用户生成内容 / AI 生成内容"**：
  App Store Connect 近年新增了针对 AI 生成内容的问卷项（"是否包含可能对部分用户
  不适宜的 AI 生成内容"）。Riddle 的回信内容由 Moonshot 大模型生成，persona 有约束
  但**没有客户端内容过滤或人工审核**，理论上模型可能被误导/越狱输出不当内容。
  **建议如实勾选"是"**，并据此对应到 **17+** 分级（"Unrestricted Web Access" /
  "Infrequent/Mild Mature/Suggestive Themes" 视问卷措辞选择最贴近的一项）。
  这不是可选项——如实申报比"蒙混过关后被下架/被要求重新提交"成本低得多。
  详见 `REVIEW_NOTES.md` 的 4.7/内容审核评估。
- 结论：**建议年龄分级 17+**（而非默认的 4+），主要因为 AI 生成内容的不可预测性，
  不是因为 App 本身有成人内容。

## 支持网址 Support URL [Trent 待定，需要 Trent 实际托管]

- 建议：`https://trentct.github.io/riddle/support`（与隐私政策同一个静态站点，见
  `PRIVACY.md` 顶部的 FLAG）。最低限度也可以先用一个 `mailto:` 支持邮箱代替静态页面
  ——App Store Connect 的 Support URL 字段要求是可访问的网页，不接受 mailto 链接，
  所以至少需要一个能打开的网页（哪怕只是一行"联系邮箱：xxx@xxx"的静态页）。

## 营销网址 Marketing URL（可选）[Trent 待定]

- 建议留空，或复用支持页 URL。非必填项，v1 不必单独做落地页。
