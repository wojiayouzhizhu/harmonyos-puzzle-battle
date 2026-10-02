require('dotenv').config();
const express = require('express');
const nodemailer = require('nodemailer');
const jwt = require('jsonwebtoken');
const fs = require('fs');  // ✅ 添加这一行

const app = express();

// 中间件：打印每次请求的时间、方法、路径、body
app.use((req, res, next) => {
    console.log(`[${new Date().toLocaleString()}] 收到请求: ${req.method} ${req.url}`);
    if (Object.keys(req.body || {}).length > 0) {
        console.log('请求体:', req.body);
    }
    next();
});

// 解析JSON请求体
app.use(express.json());

// 环境变量调试（生产环境可注释）
console.log('SMTP_USER:', process.env.SMTP_USER);
console.log('SMTP_PASS:', process.env.SMTP_PASS ? '******' : undefined);
console.log('JWT_SECRET:', process.env.JWT_SECRET ? '******' : undefined);

if (!process.env.SMTP_USER || !process.env.SMTP_PASS || !process.env.JWT_SECRET) {
    console.error('请确认 .env 文件中 SMTP_USER, SMTP_PASS 和 JWT_SECRET 已正确配置！');
    process.exit(1);
}

// 内存验证码存储
const codes = {};

// 配置 QQ 邮箱 SMTP
const transporter = nodemailer.createTransport({
    host: 'smtp.qq.com',
    port: 465,
    secure: true,
    auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS
    }
});

// 发送验证码接口
app.post('/api/send-code', async (req, res) => {
    const { email } = req.body;
    if (!email) {
        return res.status(400).json({ error: '邮箱不能为空' });
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expireTime = Date.now() + 5 * 60 * 1000;

    try {
        await transporter.sendMail({
            from: process.env.SMTP_USER,
            to: email,
            subject: '您的登录验证码',
            text: `验证码：${code}（5分钟内有效）`
        });

        codes[email] = { code, expire: expireTime };
        return res.json({ success: true });
    } catch (error) {
        console.error('邮件发送失败:', error);
        return res.status(500).json({ error: '邮件发送失败' });
    }
});

// 登录接口
app.post('/api/login', (req, res) => {
    const { email, code } = req.body;
    if (!email || !code) {
        return res.status(400).json({ error: '邮箱和验证码不能为空' });
    }

    const record = codes[email];
    if (!record) {
        return res.status(401).json({ error: '验证码不存在或已过期' });
    }

    if (record.code !== code) {
        return res.status(401).json({ error: '验证码错误' });
    }

    if (Date.now() > record.expire) {
        delete codes[email];
        return res.status(401).json({ error: '验证码已过期' });
    }

    const token = jwt.sign({ email }, process.env.JWT_SECRET, { expiresIn: '7d' });
    delete codes[email];
    return res.json({ token });
});

// 测试接口
app.get('/api/test', (req, res) => {
    res.json({ message: '服务器连接成功！' });
});
// 假设关卡数据存放在文件 puzzles.json 中
const puzzles = require('./gamedata.json');

// 验证答案接口
app.post('/api/verify', (req, res) => {
    const { difficulty, id, answer } = req.body;

    if (!difficulty || !id || !answer) {
        return res.status(400).json({ error: 'difficulty, id 和 answer 都不能为空' });
    }

    // 查找关卡
    const level = puzzles[difficulty];
    if (!level) {
        return res.status(400).json({ error: '难度等级不存在' });
    }

    const puzzle = level.find(p => p.id === id);
    if (!puzzle) {
        return res.status(404).json({ error: '关卡不存在' });
    }

    // 检查答案是否正确
    const isCorrect = puzzle.solution.every((row, rowIndex) =>
    row.every((cell, colIndex) => cell === answer[rowIndex][colIndex])
    );

    return res.json({ correct: isCorrect });
});

// -------------------- 游戏关卡 API --------------------
// 读取 gamedata.json
let gameData = {};
try {
    const rawData = fs.readFileSync("./gamedata.json", "utf-8");
    gameData = JSON.parse(rawData);
} catch (err) {
    console.error("读取 gamedata.json 失败:", err);
}

// 获取关卡
app.get("/api/game", (req, res) => {
    const difficulty = req.query.difficulty || "easy";

    if (!gameData[difficulty]) {
        return res.status(400).json({ error: "无效的难度参数" });
    }

    const puzzles = gameData[difficulty];
    const randomPuzzle = puzzles[Math.floor(Math.random() * puzzles.length)];

    res.json(randomPuzzle);
});

// 启动服务器
const port = process.env.PORT || 3000;
app.listen(port, '0.0.0.0', () => {
    console.log(`Server running on http://0.0.0.0:${port}`);
});
