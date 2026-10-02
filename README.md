\# HarmonyOS 拼图对战



基于 ArkTS 的 HarmonyOS 拼图游戏，支持单人闯关、在线房间对战与蓝牙面对面双人对战，

配套 Node 服务端提供账号、排行榜与实时对战能力。



\## 功能



\- 账号：邮箱验证码注册登录，JWT 签发与校验

\- 单人：三档难度，计时与步数统计

\- 在线对战：WebSocket 房间，实时同步双方进度与胜负

\- 蓝牙对战：设备扫描、配对连接、进度同步，不依赖网络

\- 排行榜：按难度分别统计积分，SQLite 持久化

\- 其他：新手教程、背景音乐与音效管理



\## 技术栈



\- 客户端：ArkTS + ArkUI（HarmonyOS），@ohos.router / @ohos.bluetooth

\- 服务端：Node.js + Express + WebSocket(ws) + SQLite3 + Redis

\- 认证：JWT + Nodemailer 邮件验证码



\## 运行



服务端：



&#x20;   cd server

&#x20;   npm install

&#x20;   cp env.example .env    # 填入自己的邮箱与密钥

&#x20;   node server.js



客户端：DevEco Studio 打开 `client` 目录，编译运行到 HarmonyOS 设备或模拟器。



\## 说明



\- 仓库不含任何真实账号数据，数据库文件与密钥已在 `.gitignore` 中排除

\- 蓝牙对战需要两台真机，模拟器不支持

