import express from "express";
import fs from "fs";

const app = express();
const PORT = 3001;

// 读取 gamedata.json
let gameData = {};
try {
    const rawData = fs.readFileSync("./gamedata.json", "utf-8");
    gameData = JSON.parse(rawData);
} catch (err) {
    console.error("读取 gamedata.json 失败:", err);
}

// API: 根据难度返回关卡
app.get("/api/game", (req, res) => {
    const difficulty = req.query.difficulty || "easy";

    if (!gameData[difficulty]) {
        return res.status(400).json({ error: "无效的难度参数" });
    }

    // 随机选一个关卡
    const puzzles = gameData[difficulty];
    const randomPuzzle = puzzles[Math.floor(Math.random() * puzzles.length)];

    res.json(randomPuzzle);
});

app.listen(PORT, () => {
    console.log(`服务器运行在 http://localhost:${PORT}`);
});
