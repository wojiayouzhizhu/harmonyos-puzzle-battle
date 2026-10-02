require('dotenv').config();
const express = require('express');
const nodemailer = require('nodemailer');
const jwt = require('jsonwebtoken');
const fs = require('fs');
const http = require('http');
const WebSocket = require('ws');
const sqlite3 = require('sqlite3').verbose();
const cors = require('cors');

const app = express();
const server = http.createServer(app);

// 添加CORS中间件
app.use(cors());

// 创建WebSocket服务器，与HTTP服务器共享同一端口
const wss = new WebSocket.Server({ server });
const rooms = new Map(); // 用来管理房间

// 初始化数据库
const db = new sqlite3.Database('./game.db', (err) => {
    if (err) {
        console.error('打开数据库失败:', err);
    } else {
        console.log('成功连接到SQLite数据库');
        // 创建Player表（如果不存在），包含不同难度的积分字段
        db.run(`CREATE TABLE IF NOT EXISTS Player (
            email TEXT PRIMARY KEY,
            easy_score INTEGER DEFAULT 0,
            normal_score INTEGER DEFAULT 0,
            hard_score INTEGER DEFAULT 0,
            created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
            updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
        )`, (err) => {
            if (err) {
                console.error('创建表失败:', err);
            } else {
                console.log('Player表已就绪');
            }
        });
    }
});

// 中间件：打印每次请求的时间、方法、路径、body
app.use((req, res, next) => {
    console.log(`[${new Date().toLocaleString()}] 收到HTTP请求: ${req.method} ${req.url}`);
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

// 获取或创建用户积分记录
function getUserScore(email, callback) {
    db.get("SELECT * FROM Player WHERE email = ?", [email], (err, row) => {
        if (err) {
            console.error('查询用户积分失败:', err);
            return callback(err, null);
        }

        if (!row) {
            // 创建新用户记录
            db.run("INSERT INTO Player (email, easy_score, normal_score, hard_score) VALUES (?, 0, 0, 0)", [email], function(err) {
                if (err) {
                    console.error('创建用户记录失败:', err);
                    return callback(err, null);
                }
                console.log(`创建新用户积分记录: ${email}`);
                callback(null, { email, easy_score: 0, normal_score: 0, hard_score: 0 });
            });
        } else {
            callback(null, row);
        }
    });
}

// 更新用户积分 - 根据难度更新对应的积分字段
function updateUserScore(email, points, difficulty, callback) {
    let fieldName;
    switch(difficulty) {
        case 'easy':
            fieldName = 'easy_score';
            break;
        case 'normal':
            fieldName = 'normal_score';
            break;
        case 'hard':
            fieldName = 'hard_score';
            break;
        default:
            return callback(new Error('无效的难度级别'));
    }

    db.run(`UPDATE Player SET ${fieldName} = ${fieldName} + ?, updated_at = CURRENT_TIMESTAMP WHERE email = ?`,
        [points, email], function(err) {
            if (err) {
                console.error('更新用户积分失败:', err);
                return callback(err);
            }

            if (this.changes === 0) {
                // 用户不存在，创建新记录
                const initialScores = {
                    easy_score: 0,
                    normal_score: 0,
                    hard_score: 0
                };
                initialScores[fieldName] = points;

                db.run("INSERT INTO Player (email, easy_score, normal_score, hard_score) VALUES (?, ?, ?, ?)",
                    [email, initialScores.easy_score, initialScores.normal_score, initialScores.hard_score],
                    function(err) {
                        if (err) {
                            console.error('创建用户记录失败:', err);
                            return callback(err);
                        }
                        console.log(`创建用户 ${email} 积分记录: ${points} (${difficulty})`);
                        callback(null);
                    });
            } else {
                console.log(`用户 ${email} ${difficulty} 积分更新: +${points}`);
                callback(null);
            }
        });
}

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

// 发送验证码接口 - 添加详细日志
app.post('/api/send-code', async (req, res) => {
    console.log('收到发送验证码请求:', req.body);
    const { email } = req.body;

    if (!email) {
        console.log('请求缺少邮箱参数');
        return res.status(400).json({ error: '邮箱不能为空' });
    }

    // 验证邮箱格式
    if (!email.endsWith('@qq.com')) {
        console.log('邮箱格式不正确:', email);
        return res.status(400).json({ error: '请输入QQ邮箱' });
    }

    const code = Math.floor(100000 + Math.random() * 900000).toString();
    const expireTime = Date.now() + 5 * 60 * 1000;

    try {
        console.log('尝试发送邮件到:', email);
        await transporter.sendMail({
            from: process.env.SMTP_USER,
            to: email,
            subject: '您的登录验证码',
            text: `验证码：${code}（5分钟内有效）`
        });

        codes[email] = { code, expire: expireTime };
        console.log('验证码已发送并保存:', email);
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

    // 确保用户积分记录存在
    getUserScore(email, (err, userScoreRecord) => {
        if (err) {
            return res.status(500).json({ error: '服务器内部错误' });
        }

        const token = jwt.sign({ email }, process.env.JWT_SECRET, { expiresIn: '7d' });
        delete codes[email];
        return res.json({
            token,
            easy_score: userScoreRecord.easy_score,
            normal_score: userScoreRecord.normal_score,
            hard_score: userScoreRecord.hard_score
        });
    });
});

// 添加获取头像的接口
app.get('/api/avatar', (req, res) => {
    const { email } = req.query;

    if (!email) {
        return res.status(400).json({ error: '邮箱不能为空' });
    }

    // 如果是 QQ 邮箱
    if (email.endsWith('@qq.com')) {
        const qqNumber = email.split('@')[0];
        const avatarUrl = `https://q1.qlogo.cn/g?b=qq&nk=${qqNumber}&s=100`;
        return res.json({ avatarUrl });
    }

    // 其他邮箱使用 Gravatar
    const crypto = require('crypto');
    const md5Hash = crypto.createHash('md5').update(email.trim().toLowerCase()).digest('hex');
    const avatarUrl = `https://www.gravatar.com/avatar/${md5Hash}?s=100&d=identicon`;

    return res.json({ avatarUrl });
});

// 获取用户积分接口
app.get('/api/user-score', (req, res) => {
    const authHeader = req.headers['authorization'];
    const token = authHeader && authHeader.split(' ')[1];

    if (!token) {
        return res.status(401).json({ error: '访问令牌不存在' });
    }

    jwt.verify(token, process.env.JWT_SECRET, (err, user) => {
        if (err) {
            return res.status(403).json({ error: '访问令牌无效或已过期' });
        }

        getUserScore(user.email, (err, userScore) => {
            if (err) {
                return res.status(500).json({ error: '获取用户积分失败' });
            }
            return res.json({
                email: user.email,
                easy_score: userScore.easy_score,
                normal_score: userScore.normal_score,
                hard_score: userScore.hard_score
            });
        });
    });
});

// 获取排行榜接口 - 按难度分别获取
app.get('/api/leaderboard', (req, res) => {
    const { difficulty } = req.query;

    if (!difficulty || !['easy', 'normal', 'hard'].includes(difficulty)) {
        return res.status(400).json({ error: '需要有效的难度参数: easy, normal 或 hard' });
    }

    const fieldName = `${difficulty}_score`;
    db.all(`SELECT email, ${fieldName} as score FROM Player ORDER BY ${fieldName} DESC LIMIT 100`, (err, rows) => {
        if (err) {
            console.error('获取排行榜失败:', err);
            return res.status(500).json({ error: '获取排行榜失败' });
        }
        return res.json(rows);
    });
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
// 获取正确答案并标记错误的接口
app.post('/api/getCorrectAnswer', (req, res) => {
    // 从请求体获取参数
    const { difficulty, id, userAnswerState } = req.body;

    // 验证必要参数
    if (!difficulty || !id || !userAnswerState) {
        return res.status(400).json({
            error: 'difficulty, id 和 userAnswerState 都不能为空'
        });
    }

    // 查找对应的关卡数据
    const level = puzzles[difficulty];
    if (!level) {
        return res.status(400).json({ error: '难度等级不存在' });
    }

    const puzzle = level.find(p => p.id === id);
    if (!puzzle) {
        return res.status(404).json({ error: '关卡不存在' });
    }

    // 验证答案矩阵结构是否匹配
    if (
        userAnswerState.length !== puzzle.solution.length ||
        userAnswerState.some((row, index) => row.length !== puzzle.solution[index].length)
    ) {
        return res.status(400).json({ error: '答案矩阵结构与关卡不匹配' });
    }

    // 返回正确答案和错误信息
    return res.json({
        correct: false,  // 保持与verify接口格式兼容
        correctAnswer: puzzle.solution,  // 返回完整正确答案
        message: '已返回正确答案'
    });
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
    const levelId = parseInt(req.query.levelId) || 1;

    if (!gameData[difficulty]) {
        return res.status(400).json({ error: "无效的难度参数" });
    }

    const puzzles = gameData[difficulty];

    // 查找指定ID的关卡
    const puzzle = puzzles.find(p => p.id === levelId);

    if (!puzzle) {
        return res.status(404).json({ error: "关卡不存在" });
    }

    // 添加总关卡数信息
    const response = {
        ...puzzle,
        totalLevels: puzzles.length
    };

    res.json(response);
});


// 为房间选择随机谜题的辅助函数
function getRandomPuzzleForRoom(difficulty) {
    if (!gameData[difficulty]) {
        console.error(`难度 ${difficulty} 不存在`);
        return null;
    }

    const puzzles = gameData[difficulty];
    if (!puzzles || puzzles.length === 0) {
        console.error(`难度 ${difficulty} 下没有可用的谜题`);
        return null;
    }

    // 随机选择一个谜题
    const randomIndex = Math.floor(Math.random() * puzzles.length);
    const selectedPuzzle = puzzles[randomIndex];

    console.log(`为难度 ${difficulty} 随机选择谜题: ID ${selectedPuzzle.id}, 总谜题数: ${puzzles.length}`);

    return selectedPuzzle;
}

// WebSocket连接处理
wss.on('connection', function connection(ws, req) {
    console.log('WebSocket客户端已连接');

    ws.on('message', function message(data) {
        try {
            const msg = JSON.parse(data);
            console.log('收到WebSocket消息: ', msg);

            // 根据消息类型处理
            switch (msg.type) {
                case 'join':
                    // 处理加入房间逻辑
                    if (!rooms.has(msg.roomId)) {
                        rooms.set(msg.roomId, {
                            players: new Set(),
                            finishTimes: new Map(),
                            timer: null, // 添加计时器属性
                            puzzle: null // 初始时不分配谜题
                        });
                        console.log(`创建房间 ${msg.roomId}`);
                    }
                    const room = rooms.get(msg.roomId);
                    room.players.add(ws);
                    ws.roomId = msg.roomId;
                    ws.playerId = msg.playerId;

                    console.log(`玩家 ${msg.playerId} 加入房间 ${msg.roomId}, 当前房间人数: ${room.players.size}`);

                    // 获取当前房间所有玩家ID
                    const playerIds = Array.from(room.players).map(c => c.playerId || 'unknown');

                    // 通知房间内其他玩家
                    room.players.forEach(client => {
                        if (client.readyState === WebSocket.OPEN) {
                            client.send(JSON.stringify({
                                type: 'room_joined',
                                roomId: msg.roomId,
                                players: playerIds
                            }));
                        }
                    });

                    // 通知所有玩家有新玩家加入
                    room.players.forEach(client => {
                        if (client !== ws && client.readyState === WebSocket.OPEN) {
                            client.send(JSON.stringify({
                                type: 'player_joined',
                                playerId: msg.playerId,
                                roomId: msg.roomId
                            }));
                        }
                    });

                    // 在 server.js 的 join case 中添加
                    if (room.players.size === 2) {
                        console.log(`房间 ${msg.roomId} 已有两名玩家，发送游戏开始消息`);

                        // 为房间随机选择一个谜题
                        const roomPuzzle = getRandomPuzzleForRoom(msg.roomId);
                        if (!roomPuzzle) {
                            console.error(`无法为房间 ${msg.roomId} 获取谜题`);
                            // 通知所有玩家游戏无法开始
                            room.players.forEach(client => {
                                if (client.readyState === WebSocket.OPEN) {
                                    client.send(JSON.stringify({
                                        type: 'error',
                                        message: '无法获取游戏题目，请稍后重试'
                                    }));
                                }
                            });
                            return;
                        }

                        // 保存谜题到房间
                        room.puzzle = roomPuzzle;
                        console.log(`房间 ${msg.roomId} 分配谜题 ID: ${roomPuzzle.id}`);

                        // 收集所有玩家信息
                        const players = Array.from(room.players).map(client => ({
                            id: client.playerId,
                            status: 'playing'
                        }));

                        room.players.forEach(client => {
                            if (client.readyState === WebSocket.OPEN) {
                                console.log(`向玩家 ${client.playerId} 发送 game_start 消息和谜题`);
                                client.send(JSON.stringify({
                                    type: 'game_start',
                                    players: players,
                                    roomId: msg.roomId,
                                    puzzle: room.puzzle // 发送相同的谜题给所有玩家
                                }));
                            }
                        });
                    }
                    break;

                // 修改 player_finished 处理
                case 'player_finished':
                    // 广播完成消息给同房间的人
                    const targetRoom = rooms.get(ws.roomId);
                    if (targetRoom) {
                        // 记录完成时间和时间戳
                        targetRoom.finishTimes.set(ws.playerId, {
                            time: msg.time,
                            timestamp: Date.now()
                        });

                        // 广播完成消息
                        targetRoom.players.forEach(client => {
                            if (client.readyState === WebSocket.OPEN) {
                                client.send(JSON.stringify({
                                    type: 'player_finished',
                                    playerId: msg.playerId,
                                    time: msg.time,
                                    roomId: ws.roomId
                                }));
                            }
                        });

                        // 如果是第一个完成的玩家，启动5秒倒计时
                        if (targetRoom.finishTimes.size === 1) {
                            console.log(`玩家 ${ws.playerId} 第一个完成，启动5秒倒计时`);

                            // 设置5秒后检查是否第二个玩家完成
                            targetRoom.timer = setTimeout(() => {
                                console.log(`5秒倒计时结束，检查房间 ${ws.roomId} 的状态`);

                                // 如果仍然只有一个玩家完成，则这个玩家获胜
                                if (targetRoom.finishTimes.size === 1) {
                                    const winner = Array.from(targetRoom.finishTimes.keys())[0];
                                    console.log(`玩家 ${winner} 获胜`);

                                    // 更新积分 - 使用数据库，根据房间难度更新积分
                                    updateUserScore(winner, 2, ws.roomId, (err) => {
                                        if (err) {
                                            console.error('更新积分失败:', err);
                                        }
                                    });

                                    // 发送胜负消息
                                    targetRoom.players.forEach(client => {
                                        if (client.readyState === WebSocket.OPEN) {
                                            const isWinner = client.playerId === winner;
                                            client.send(JSON.stringify({
                                                type: 'game_result',
                                                result: isWinner ? 'win' : 'lose',
                                            }));
                                        }
                                    });

                                    // 重置完成时间记录
                                    targetRoom.finishTimes.clear();
                                }
                            }, 5000); // 5秒倒计时
                        }
                        // 如果第二个玩家在5秒内完成
                        else if (targetRoom.finishTimes.size === 2) {
                            console.log(`第二个玩家在5秒内完成，判断是否平局`);

                            // 清除可能存在的倒计时
                            if (targetRoom.timer) {
                                clearTimeout(targetRoom.timer);
                                targetRoom.timer = null;
                            }

                            const players = Array.from(targetRoom.finishTimes.keys());
                            const player1 = players[0];
                            const player2 = players[1];
                            const time1 = targetRoom.finishTimes.get(player1);
                            const time2 = targetRoom.finishTimes.get(player2);

                            // 判断是否平局（5秒内完成视为平局）
                            const isDraw = Math.abs(time1.timestamp - time2.timestamp) < 5000;

                            if (isDraw) {
                                // 平局，双方各得1分
                                updateUserScore(player1, 1, ws.roomId, (err) => {
                                    if (err) console.error('更新积分失败:', err);
                                });
                                updateUserScore(player2, 1, ws.roomId, (err) => {
                                    if (err) console.error('更新积分失败:', err);
                                });

                                // 发送平局消息
                                targetRoom.players.forEach(client => {
                                    if (client.readyState === WebSocket.OPEN) {
                                        client.send(JSON.stringify({
                                            type: 'game_result',
                                            result: 'draw',
                                        }));
                                    }
                                });
                            } else {
                                // 有胜负，赢家得2分
                                const winner = time1.timestamp < time2.timestamp ? player1 : player2;
                                const loser = winner === player1 ? player2 : player1;

                                updateUserScore(winner, 2, ws.roomId, (err) => {
                                    if (err) console.error('更新积分失败:', err);
                                });

                                // 发送胜负消息
                                targetRoom.players.forEach(client => {
                                    if (client.readyState === WebSocket.OPEN) {
                                        const isWinner = client.playerId === winner;
                                        client.send(JSON.stringify({
                                            type: 'game_result',
                                            result: isWinner ? 'win' : 'lose',
                                        }));
                                    }
                                });
                            }

                            // 重置完成时间记录
                            targetRoom.finishTimes.clear();
                        }
                    }
                    break;

                default:
                    console.log('未知WebSocket消息类型:', msg.type);
            }
        } catch (e) {
            console.error('处理WebSocket消息出错:', e);
        }
    });

    ws.on('close', () => {
        console.log('WebSocket客户端断开连接');
        // 清理逻辑，从房间中移除ws
        if (ws.roomId) {
            const room = rooms.get(ws.roomId);
            if (room) {
                room.players.delete(ws);
                // 清除计时器
                if (room.timer) {
                    clearTimeout(room.timer);
                    room.timer = null;
                }
                // 通知其他玩家有人离开
                room.players.forEach(client => {
                    if (client.readyState === WebSocket.OPEN) {
                        client.send(JSON.stringify({
                            type: 'player_left',
                            playerId: ws.playerId,
                            roomId: ws.roomId
                        }));
                        console.log(`通知玩家 ${client.playerId} 有玩家离开`);
                    }
                });
                if (room.players.size === 0) {
                    rooms.delete(ws.roomId);
                }
            }
        }
    });
});

// 启动服务器
const port = process.env.PORT || 3000;
server.listen(port, '0.0.0.0', () => {
    console.log(`HTTP服务器运行在 http://0.0.0.0:${port}`);
    console.log(`WebSocket服务器运行在 ws://0.0.0.0:${port}`);
});

// 优雅关闭 - 关闭数据库连接
process.on('SIGINT', () => {
    console.log('正在关闭服务器...');
    db.close((err) => {
        if (err) {
            console.error('关闭数据库连接失败:', err);
        } else {
            console.log('数据库连接已关闭');
        }
        process.exit(0);
    });
});