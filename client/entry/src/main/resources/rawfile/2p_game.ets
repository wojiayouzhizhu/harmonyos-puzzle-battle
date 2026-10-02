import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import router from '@ohos.router';
import webSocket from '@ohos.net.webSocket';
import { BusinessError } from '@kit.BasicServicesKit';

interface PuzzleData {
  id: number
  size: number
  grid: number[][]  // 修改为二维数组
  solution: number[][]
}

interface VerifyResponse {
  correct: boolean
  message?: string
}

// 定义WebSocket消息类型的接口
interface WsMessage {
  result: string;
  type: string;
  roomId?: string;
  playerId?: string;
  time?: number;
  players?: string[];
  puzzle?: PuzzleData; // 添加 puzzle 字段
}

// 定义完成消息接口
interface FinishMessage {
  type: string;
  roomId: string;
  playerId: string;
  time: number;
}

interface PlayerInfo {
  id: string
  name?: string
  status: 'waiting' | 'playing' | 'finished'
  time?: number
}

@Entry
@Component
struct TwoPlayerGame {
  // 游戏状态
  @State puzzle: PuzzleData | null = null
  @State userState: number[][] = []    // 显示状态：-1 白色 -2 黑色 -3 灰色
  @State answerState: number[][] = []  // 用户答案：0 或 1
  @State isWsConnected: boolean = false
  @State isVerifying: boolean = false  // 是否正在验证
  @State verifyResult: VerifyResponse | null = null // 验证结果

  // 多人游戏状态
  @State roomId: string = ''
  @State playerId: string = ''
  @State opponent: PlayerInfo | null = null
  @State gameStarted: boolean = false
  @State gameFinished: boolean = false
  @State opponentHasFinished: boolean = false
  @State iWon: boolean = false
  // 在组件中添加状态
  @State gameResult: string = ''

  // 计时器状态
  @State elapsedTime: number = 0
  private timer: number = 0

  // WebSocket连接
  private ws: webSocket.WebSocket | null = null

  // 使用StorageLink获取用户邮箱
  @StorageLink('userEmail') userEmail: string = ''

  // 在组件顶部添加GIF资源引用
  @State showWinGif: boolean = false
  @State showLoseGif: boolean = false
  @State showDrawGif: boolean = false
  private winGif: Resource = $rawfile('win.gif');
  private loseGif: Resource = $rawfile('lose.gif');
  private drawGif: Resource = $rawfile('draw.gif');

  aboutToAppear() {
    console.log('2p_game页面已加载');

    // 生成玩家ID
    this.playerId = this.userEmail || 'unknown@example.com'

    // 获取难度参数
    const params = router.getParams() as Record<string, string>
    const difficulty = params['difficulty'] ?? 'easy'
    console.log('难度参数:', difficulty);

    // 连接到WebSocket服务器
    this.connectWebSocket(difficulty)

    // 不再需要获取游戏数据，谜题将通过WebSocket发送
  }

  // 连接到WebSocket服务器
  connectWebSocket(difficulty: string) {
    try {
      this.ws = webSocket.createWebSocket();

      // 设置事件回调
      this.ws.on('open', () => {
        console.log('WebSocket连接已建立');
        this.isWsConnected = true;

        // 加入房间（使用难度作为房间ID）
        this.roomId = difficulty;
        const joinMsg: WsMessage = {
          type: 'join',
          roomId: this.roomId,
          playerId: this.playerId,
          result: ''
        };

        // 短暂延迟确保连接完全建立
        setTimeout(() => {
          if (this.ws && this.isWsConnected) {
            this.ws.send(JSON.stringify(joinMsg), (err) => {
              if (err) {
                console.error('发送加入房间消息失败:', JSON.stringify(err));
              } else {
                console.log('加入房间消息发送成功');
              }
            });
          }
        }, 100);
      });

      // 使用 HarmonyOS 特定的 'headerReceive' 事件
      this.ws.on('message', (err: BusinessError, value: string | ArrayBuffer) => {
        if (err) {
          console.error('接收消息错误:', JSON.stringify(err));
          return;
        }

        try {
          // 确保value是字符串类型
          const messageString = typeof value === 'string' ? value : '';
          console.log('收到WebSocket消息:', messageString);

          const msg: WsMessage = JSON.parse(messageString) as WsMessage;
          this.handleWebSocketMessage(msg);
        } catch (e) {
          console.error('解析WebSocket消息失败:', e);
        }
      });

      this.ws.on('close', () => {
        console.log('WebSocket连接已关闭');
        this.isWsConnected = false;
      });

      this.ws.on('error', (err) => {
        console.error('WebSocket错误:', JSON.stringify(err));
      });

      // 连接到服务器（假设服务器运行在10.34.121.200:3000）
      this.ws.connect('ws://10.34.121.200:3000', (err) => {
        if (err) {
          console.error('WebSocket连接失败:', JSON.stringify(err));
          promptAction.showToast({ message: '连接服务器失败', duration: 2000 });
        }
      });
    } catch (error) {
      console.error('创建WebSocket失败:', JSON.stringify(error));
    }
  }

  // 修改 handleWebSocketMessage 方法
  handleWebSocketMessage(msg: WsMessage) {
    console.log('收到WebSocket消息:', JSON.stringify(msg));

    switch (msg.type) {
      case 'room_joined':
        console.log('已加入房间:', msg.roomId);
        if (msg.players && msg.players.length > 0) {
          // 更新对手信息
          this.opponent = {
            id: msg.players[0], // 只有一名对手
            status: 'waiting'
          } as PlayerInfo;
          console.log('更新对手信息:', JSON.stringify(this.opponent));
        }
        break;

      case 'game_start':
        console.log('收到游戏开始消息和谜题');
        this.gameStarted = true;

        // 使用服务器发送的谜题数据
        if (msg.puzzle) {
          this.puzzle = msg.puzzle;

          // 使用可选链和空值合并操作符
          const size = this.puzzle?.size ?? 0;
          if (size > 0) {
            // 初始化 userState 和 answerState
            this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
            this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
          } else {
            console.error('谜题数据无效或缺少size属性');
            promptAction.showToast({ message: '游戏数据加载失败', duration: 2000 });
          }
        } else {
          console.error('游戏开始消息中缺少谜题数据');
          promptAction.showToast({ message: '游戏数据加载失败', duration: 2000 });
        }

        this.startTimer();
        promptAction.showToast({ message: '游戏开始！', duration: 2000 });
        break;

      case 'player_left':
        if (msg.playerId && msg.playerId === this.opponent?.id) {
          promptAction.showToast({ message: '对手已离开游戏', duration: 2000 })
          this.opponent = null
          this.gameStarted = false
          this.stopTimer()
          console.log('对手离开:', msg.playerId)
        }
        break;

      case 'player_finished':
        console.log('收到完成消息，对方ID:', msg.playerId, '本方ID:', this.playerId);
        if (msg.playerId && msg.playerId !== this.playerId) {
          console.log('收到对手完成消息:', JSON.stringify(msg));

          // 不要立即结束游戏，只是记录对手已完成
          this.opponentHasFinished = true;

          promptAction.showToast({
            message: `对手已完成游戏，用时 ${msg.time} 秒`,
            duration: 3000
          });
        } else {
          console.log('收到自己的完成消息，忽略');
        }
        break;

      case 'game_result':
        console.log('收到游戏结果:', JSON.stringify(msg));
        this.gameFinished = true;
        this.stopTimer();

        // 根据结果设置胜负状态
        if (msg.result === 'win') {
          this.iWon = true;
          this.showWinGif = true; // 显示胜利GIF
          setTimeout(() => {
            this.showWinGif = false; // 3秒后隐藏GIF
          }, 1000);
          promptAction.showToast({ message: '恭喜你获胜！', duration: 3000 });
        } else if (msg.result === 'lose') {
          this.iWon = false;
          this.showLoseGif = true; // 显示失败GIF
          setTimeout(() => {
            this.showLoseGif = false; // 3秒后隐藏GIF
          }, 1000);
          promptAction.showToast({ message: '很遗憾，你输了。', duration: 3000 });
        } else if (msg.result === 'draw') {
          this.iWon = true;
          this.showDrawGif = true; // 显示平局GIF
          setTimeout(() => {
            this.showDrawGif = false; // 3秒后隐藏GIF
          }, 1000);
          promptAction.showToast({ message: '平局！', duration: 3000 });
        }
        break;
    }
  }

  // 开始计时器
  startTimer() {
    this.elapsedTime = 0
    this.timer = setInterval(() => {
      this.elapsedTime += 1
    }, 1000)
  }

  // 停止计时器
  stopTimer() {
    if (this.timer) {
      clearInterval(this.timer)
      this.timer = 0
    }
  }

  // 验证答案
  verifyAnswer() {
    if (!this.puzzle) return

    this.isVerifying = true
    let httpRequest = http.createHttp()
    httpRequest.request(
      `http://10.34.121.200:3000/api/verify`,
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        extraData: JSON.stringify({
          id: this.puzzle.id,
          difficulty: this.roomId,
          answer: this.answerState
        })
      },
      (err, res) => {
        this.isVerifying = false
        if (!err && res.responseCode === 200) {
          try {
            const result: VerifyResponse = JSON.parse(res.result as string) as VerifyResponse
            this.verifyResult = result
            if (result.correct) {
              // 答案正确，停止计时并通知对手
              this.stopTimer()
              this.gameFinished = true
             /* this.showWinGif = true; // 显示胜利GIF
              setTimeout(() => {
                this.showWinGif = false; // 3秒后隐藏GIF
              }, 3000); */

              // 发送完成消息
              if (this.ws) {
                const finishMsg: FinishMessage = {
                  type: 'player_finished',
                  roomId: this.roomId,
                  playerId: this.playerId,
                  time: this.elapsedTime
                }
                this.ws.send(JSON.stringify(finishMsg), (err) => {
                  if (err) {
                    console.error('发送完成消息失败:', JSON.stringify(err))
                  }
                })
              }

              promptAction.showToast({
                message: `恭喜您获胜！用时 ${this.elapsedTime} 秒`,
                duration: 3000
              })
            } else {
              promptAction.showToast({ message: '答案不正确，请继续尝试', duration: 2000 })
            }
          } catch (e) {
            promptAction.showToast({ message: '解析响应失败', duration: 2000 })
          }
        } else {
          promptAction.showToast({ message: '提交失败', duration: 2000 })
        }
        httpRequest.destroy()
      }
    )
  }

  aboutToDisappear() {
    // 清理资源
    this.stopTimer()
    if (this.ws) {
      this.ws.close()
      this.ws = null
    }
  }

  build() {
    Column() {
      // 胜利GIF动画 - 覆盖在界面上层
      if (this.showWinGif) {
        Stack() {
          // 半透明黑色背景
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.5)')

          // 胜利GIF
          Image(this.winGif)
            .width(300)
            .height(300)
            .objectFit(ImageFit.Contain)
            .focusable(true) // 使Image可获焦
            .focusOnTouch(true) // 点击获焦
        }
        .position({ x: 0, y: 0 })
        .width('100%')
        .height('100%')
        .zIndex(999) // 确保在最上层
      }

      // 失败GIF动画 - 覆盖在界面上层
      if (this.showLoseGif) {
        Stack() {
          // 半透明黑色背景
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.5)')

          // 失败GIF
          Image(this.loseGif)
            .width(300)
            .height(300)
            .objectFit(ImageFit.Contain)
            .focusable(true) // 使Image可获焦
            .focusOnTouch(true) // 点击获焦
        }
        .position({ x: 0, y: 0 })
        .width('100%')
        .height('100%')
        .zIndex(999) // 确保在最上层
      }

      // 平局GIF动画 - 覆盖在界面上层
      if (this.showDrawGif) {
        Stack() {
          // 半透明黑色背景
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(0,0,0,0.5)')

          // 平局GIF
          Image(this.drawGif)
            .width(300)
            .height(300)
            .objectFit(ImageFit.Contain)
            .focusable(true) // 使Image可获焦
            .focusOnTouch(true) // 点击获焦
        }
        .position({ x: 0, y: 0 })
        .width('100%')
        .height('100%')
        .zIndex(999) // 确保在最上层
      }

      // 标题和游戏信息
      Column() {
        Text('双人对战 - 像素填空')
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20, bottom: 5 })
          .textAlign(TextAlign.Center)
          .width('100%')
          .fontColor('#2c3e50')

        // 显示房间信息和对手状态
        Row() {
          Text(`房间: ${this.roomId}`)
            .fontSize(14)
            .fontColor('#7f8c8d')

          Text(`|`)
            .fontSize(14)
            .fontColor('#7f8c8d')
            .margin({ left: 10, right: 10 })

          if (this.opponent) {
            Text(`对手: ${this.opponent.id}`)
              .fontSize(14)
              .fontColor('#27ae60')
          } else {
            Text(`对手: 等待中...`)
              .fontSize(14)
              .fontColor('#e74c3c')
          }
        }
        .margin({ bottom: 10 })

        // 计时器
        if (this.gameStarted) {
          Text(`用时: ${this.elapsedTime} 秒`)
            .fontSize(16)
            .fontColor('#3498db')
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 10 })
        }

        // 游戏状态显示
        if (this.gameFinished) {
          if (this.iWon && (!this.opponentHasFinished)) {
            Text('恭喜您获胜！')
              .fontSize(18)
              .fontColor('#27ae60')
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 10 })
          } else if (this.opponentHasFinished && (!this.iWon)){
            Column() {
              Text('对手已获胜')
                .fontSize(18)
                .fontColor('#e74c3c')
                .fontWeight(FontWeight.Bold)
            }
            .margin({ bottom: 10 })
          }
        } else if (this.opponentHasFinished && this.iWon) {
          Text('你们是平局！')
            .fontSize(18)
            .fontColor('#3498db')
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 10 })
        } else if (!this.gameStarted) {
          Text('等待对手加入...')
            .fontSize(16)
            .fontColor('#f39c12')
            .margin({ bottom: 10 })
        }
      }
      .width('100%')
      .alignItems(HorizontalAlign.Center)

      // 游戏网格
      Column() {
        if (this.puzzle !== null && this.gameStarted && !this.gameFinished) {
          Grid() {
            // 添加非空断言 (!) 确保 this.puzzle 不为 null
            ForEach(this.puzzle!.grid, (row: number[], rowIndex: number) => {
              ForEach(row, (cellValue: number, colIndex: number) => {
                GridItem() {
                  Stack() {
                    // 显示数字
                    if (cellValue >= 0) {
                      Text(cellValue.toString())
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor(this.userState[rowIndex][colIndex] === -2 ? Color.White : Color.Black)
                        .align(Alignment.Center)
                    }
                    // 显示 X（灰色状态）
                    if (this.userState[rowIndex][colIndex] === -3) {
                      Text('X')
                        .fontSize(22)
                        .fontColor('rgba(0,0,0,0.6)')
                        .align(Alignment.Center)
                    }
                  }
                  .width('100%')
                  .height('100%')
                  .backgroundColor(
                    this.userState[rowIndex][colIndex] === -1
                      ? Color.White
                      : this.userState[rowIndex][colIndex] === -2
                      ? '#34495e'
                      : '#ecf0f1'
                  )
                  .onClick(() => {
                    if (this.gameFinished || this.puzzle === null) {
                      promptAction.showToast({ message: '游戏已结束', duration: 1000 });
                      return;
                    }

                    // 点击格子循环状态
                    let newState = this.userState[rowIndex][colIndex]
                    let updatedState = newState === -1 ? -2 : newState === -2 ? -3 : -1
                    this.userState[rowIndex][colIndex] = updatedState

                    // 更新 answerState：黑色 = 1，其他 = 0
                    this.answerState[rowIndex][colIndex] = updatedState === -2 ? 1 : 0

                    // 触发界面刷新
                    this.userState = [...this.userState]
                    this.answerState = [...this.answerState]
                  })
                }
                .border({ width: 1, color: '#bdc3c7' })
              })
            })
          }
          // 添加非空断言 (!) 确保 this.puzzle 不为 null
          .columnsTemplate(`repeat(${this.puzzle!.size}, 1fr)`)
          // 添加非空断言 (!) 确保 this.puzzle 不为 null
          .rowsTemplate(`repeat(${this.puzzle!.size}, 1fr)`)
          .columnsGap(0)
          .rowsGap(0)
          .width('90%')
          .height(400)
          .border({ width: 2, color: '#34495e' })
          .margin({ bottom: 30 })
        } else if (this.gameFinished) {
          // 游戏结束显示
          Column() {
            Text('游戏结束，请返回大厅')
              .fontSize(20)
              .fontColor('#e74c3c')
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 20 })

            // 显示胜负结果
            if (this.opponentHasFinished && this.iWon) {
              Text('你们是平局！')
                .fontSize(18)
                .fontColor('#f39c12')
                .margin({ bottom: 10 })
            } else if (this.opponentHasFinished && (!this.iWon)) {
              Text('对手已获胜！')
                .fontSize(18)
                .fontColor('#7f8c8d')
                .margin({ bottom: 10 })
            } else if (this.iWon && (!this.opponentHasFinished)) {
              Text('恭喜您获胜！')
                .fontSize(18)
                .fontColor('#27ae60')
                .margin({ bottom: 10 })
            }

            Text(`您的用时: ${this.elapsedTime} 秒`)
              .fontSize(16)
              .fontColor('#7f8c8d')
          }
          .height(400)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width('100%')
          .backgroundColor('#f9f9f9')
          .borderRadius(8)
          .padding(20)
        } else if (this.puzzle !== null && !this.gameStarted) {
          // 等待游戏开始
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color('#3498db')
              .margin({ bottom: 10 })
            Text('等待游戏开始...')
              .fontSize(16)
              .fontColor('#7f8c8d')
          }
          .height(400)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width('100%')
        } else {
          Column() {
            LoadingProgress()
              .width(50)
              .height(50)
              .color('#3498db')
              .margin({ bottom: 10 })
            Text('加载中...')
              .fontSize(16)
              .fontColor('#7f8c8d')
          }
          .height(400)
          .justifyContent(FlexAlign.Center)
          .alignItems(HorizontalAlign.Center)
          .width('100%')
        }
      }

      // 操作按钮
      Row() {
        Button('提交答案')
          .width(150)
          .height(45)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(this.gameStarted && !this.gameFinished ? '#3498db' : '#95a5a6')
          .borderRadius(8)
          .onClick(() => {
            if (this.gameStarted && !this.gameFinished && this.puzzle) {
              this.verifyAnswer()
            }
          })

        Button('返回')
          .width(120)
          .height(45)
          .fontSize(16)
          .backgroundColor('#e74c3c')
          .fontColor(Color.White)
          .borderRadius(8)
          .onClick(() => {
            router.back()
          })
      }
      .justifyContent(FlexAlign.SpaceEvenly)
      .width('100%')
      .margin({ bottom: 20 })
    }
    .width('100%')
    .height('100%')
    .alignItems(HorizontalAlign.Center)
    .padding(20)
    .backgroundColor('#ecf0f1')
  }
}