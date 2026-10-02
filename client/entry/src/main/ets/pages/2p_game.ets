import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import router from '@ohos.router';
import webSocket from '@ohos.net.webSocket';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
//import { resourceManager } from '@kit.LocalizationKit';
import resourceManager from '@ohos.resourceManager';
import { common } from '@kit.AbilityKit';

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

// 添加音频播放管理器类
@ObservedV2
class SoundEffectManager {
  private avPlayers: Map<string, media.AVPlayer> = new Map();
  private preparedSounds: Set<string> = new Set();

  // 初始化所有音效
  async initAllSounds() {
    try {
      const context = getContext() as common.UIAbilityContext;
      const resourceMgr = context.resourceManager;

      // 初始化所有音效
      await this.initSound('click', 'click_sound.mp3', resourceMgr);
      await this.initSound('win', 'win_sound.mp3', resourceMgr);
      await this.initSound('lose', 'lose_sound.mp3', resourceMgr);
      await this.initSound('draw', 'draw_sound.mp3', resourceMgr);

    } catch (error) {
      console.error('初始化音频播放器失败:', JSON.stringify(error));
    }
  }

  // 初始化单个音效
  private async initSound(soundName: string, fileName: string, resourceMgr: resourceManager.ResourceManager) {
    try {
      const rawfilePath = fileName;
      const fdInfo = await resourceMgr.getRawFd(rawfilePath);

      const avPlayer = await media.createAVPlayer();
      this.setAVPlayerCallback(avPlayer, soundName);

      // 使用fd方式设置音频源
      avPlayer.fdSrc = {
        fd: fdInfo.fd,
        offset: fdInfo.offset,
        length: fdInfo.length
      };

      this.avPlayers.set(soundName, avPlayer);
    } catch (error) {
      console.error(`初始化音效 ${soundName} 失败:`, JSON.stringify(error));
    }
  }

  setAVPlayerCallback(avPlayer: media.AVPlayer, soundName: string) {
    avPlayer.on('stateChange', async (state: string) => {
      switch (state) {
        case 'initialized':
          avPlayer.prepare();
          break;
        case 'prepared':
          this.preparedSounds.add(soundName);
          console.info(`音效 ${soundName} 准备完成`);
          break;
        case 'completed':
          avPlayer.seek(0);
          break;
      }
    });

    avPlayer.on('error', (err: BusinessError) => {
      console.error(`音效 ${soundName} 播放错误:`, JSON.stringify(err));
    });
  }

  // 播放指定音效
  async play(soundName: string) {
    const avPlayer = this.avPlayers.get(soundName);
    if (avPlayer && this.preparedSounds.has(soundName)) {
      try {
        avPlayer.seek(0);
        avPlayer.play();
        console.log(`播放音效: ${soundName}`);
      } catch (error) {
        console.error(`播放音效 ${soundName} 失败:`, JSON.stringify(error));
      }
    } else {
      console.warn(`音效 ${soundName} 未准备好或不存在`);
    }
  }

  async release() {
    // 方法：使用 for-of 循环和数组下标访问
    for (const entry of this.avPlayers) {
      let soundName = entry[0]; // 获取键
      let avPlayer = entry[1];  // 获取值
      avPlayer.release();
      this.preparedSounds.delete(soundName);
    }
    this.avPlayers.clear();
  }
}

interface GeneratedTypeLiteralInterface_1 {
  row: number;
  col: number;
}

@Entry
@Component
struct TwoPlayerGame {
  // 游戏状态
  @State puzzle: PuzzleData | null = null
  @State userState: number[][] = []    // 显示状态：-1 白色 -2 黑色 -3 灰色
  @State answerState: number[][] = []  // 用户答案：0 或 1
  @State myId: string = ''
  @State isWsConnected: boolean = false
  @State isVerifying: boolean = false  // 是否正在验证
  @State verifyResult: VerifyResponse | null = null // 验证结果
  @State lastTouchedCell: GeneratedTypeLiteralInterface_1 | null = null

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

  // 添加缩放相关状态
  @State scaleValue: number = 1.0
  @State baseScale: number = 1.0
  @State isScaling: boolean = false

  // 在TwoPlayerGame组件顶部添加以下状态变量
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State baseOffsetX: number = 0;
  @State baseOffsetY: number = 0;
  @State isPanning: boolean = false;

  // 添加防误触状态变量
  @State touchPointCount: number = 0;
  @State isMultiTouch: boolean = false;

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

  // 添加音效管理器
  private soundManager: SoundEffectManager = new SoundEffectManager();

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

    // 初始化音效管理器 - 加载所有音效
    this.soundManager.initAllSounds();
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
        this.myId = this.playerId;
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

      // 连接到服务器
      this.ws.connect('ws://10.0.2.2:3000', (err) => {
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
          // 找到除自己外的其他玩家作为对手
          const otherPlayers = msg.players.filter(playerId => playerId !== this.myId);
          if (otherPlayers.length > 0) {
            // 更新对手信息
            this.opponent = {
              id: otherPlayers[0], // 只有一名对手
              status: 'waiting'
            } as PlayerInfo;
            console.log('更新对手信息:', JSON.stringify(this.opponent));
          }
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
          // 播放胜利音效
          this.soundManager.play('win');
          setTimeout(() => {
            this.showWinGif = false; // 3秒后隐藏GIF
          }, 3000);
          promptAction.showToast({ message: '恭喜你获胜！', duration: 3000 });
        } else if (msg.result === 'lose') {
          this.iWon = false;
          this.showLoseGif = true; // 显示失败GIF
          // 播放失败音效
          this.soundManager.play('lose');
          setTimeout(() => {
            this.showLoseGif = false; // 3秒后隐藏GIF
          }, 3000);
          promptAction.showToast({ message: '很遗憾，你输了。', duration: 3000 });
        } else if (msg.result === 'draw') {
          this.iWon = true;
          this.showDrawGif = true; // 显示平局GIF
          // 播放平局音效
          this.soundManager.play('draw');
          setTimeout(() => {
            this.showDrawGif = false; // 3秒后隐藏GIF
          }, 3000);
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

  // 计算最大偏移量，确保网格要么超出边框被遮挡，要么与边框重合
  calculateMaxOffset(scale: number): number {
    const baseSize = 350;
    const scaledSize = baseSize * scale;

    // 当缩放比例大于1时，允许网格超出边框
    // 当缩放比例小于等于1时，网格应该与边框重合
    if (scale > 1) {
      // 允许网格超出边框，最大偏移量为缩放后大小与基础大小差值的一半
      return (scaledSize - baseSize) / 2;
    } else {
      // 网格应该与边框重合，不允许偏移
      return 0;
    }
  }

  // 验证答案
  verifyAnswer() {
    if (!this.puzzle) return

    this.isVerifying = true
    let httpRequest = http.createHttp()
    httpRequest.request(
      `http://10.0.2.2:3000/api/verify`,
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

    // 释放音效资源
    this.soundManager.release();
  }

  build() {
    Stack() {
      // 背景图片
      Image($r('app.media.bg2'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover)
        .opacity(0.9)

      // 胜利GIF动画
      if (this.showWinGif) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(25,25,25,0.5)')

          Image(this.winGif)
            .width(300)
            .height(300)
            .objectFit(ImageFit.Contain)
            .focusable(true)
            .focusOnTouch(true)
        }
        .position({ x: 0, y: 0 })
        .width('100%')
        .height('100%')
        .zIndex(999)
      }

      // 失败GIF动画
      if (this.showLoseGif) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(25,25,25,0.5)')

          Image(this.loseGif)
            .width(300)
            .height(300)
            .objectFit(ImageFit.Contain)
            .focusable(true)
            .focusOnTouch(true)
        }
        .position({ x: 0, y: 0 })
        .width('100%')
        .height('100%')
        .zIndex(999)
      }

      // 平局GIF动画
      if (this.showDrawGif) {
        Stack() {
          Column()
            .width('100%')
            .height('100%')
            .backgroundColor('rgba(25,25,25,0.5)')

          Image(this.drawGif)
            .width(300)
            .height(300)
            .objectFit(ImageFit.Contain)
            .focusable(true)
            .focusOnTouch(true)
        }
        .position({ x: 0, y: 0 })
        .width('100%')
        .height('100%')
        .zIndex(999)
      }

      Column() {
        // 标题和游戏信息
        Column() {
          Text('双人对战 - 像素填空')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .margin({ top: 20, bottom: 5 })
            .textAlign(TextAlign.Center)
            .width('100%')
            .fontColor('#673B78')

          // 添加缩放提示
          //Text(' ')
          //  .fontSize(14)
          //  .fontColor('#7f8c8d')
          //  .margin({ bottom: 10 })
          //  .textAlign(TextAlign.Center)
          //  .width('100%')
          //  .opacity(0.8)

          // 显示房间信息和对手状态
          Row() {
            Text(`难度: ${this.roomId}`)
              .fontSize(14)
              .fontColor('#7f8c8d')

            Text(`|`)
              .fontSize(14)
              .fontColor('#7f8c8d')
              .margin({ left: 10, right: 10 })

            if (this.opponent) {
              Text(`对手: ${this.opponent.id}`)
                .fontSize(14)
                .fontColor('#4CAF50')
            } else {
              Text(`对手: 等待中...`)
                .fontSize(14)
                .fontColor('#F44336')
            }
          }
          .margin({ bottom: 10 })

          // 计时器
          if (this.gameStarted) {
            Text(`用时: ${this.elapsedTime} 秒`)
              .fontSize(16)
              .fontColor('#673B78')
              .fontWeight(FontWeight.Medium)
              .margin({ bottom: 20 })
          }

          // 游戏状态显示
          if (this.gameFinished) {
            //
          } else if (!this.gameStarted) {
            Text('等待对手加入...')
              .fontSize(16)
              .fontColor('#673B78')
              .margin({ bottom: 10 })
          }
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        // 游戏网格 - 添加边框和缩放功能
        Column() {
          if (this.puzzle !== null && this.gameStarted && !this.gameFinished) {
            // 添加边框容器
            Stack() {
              // 边框
              Stack()
                .width(350)
                .height(350)
                .border({ width: 2, color: '#3498db', radius: 8 })
                .backgroundColor('#f8f9fa')

              // 游戏网格容器
              Stack() {
                Column() {
                  Grid() {
                    // 添加非空断言 (!) 确保 this.puzzle 不为 null
                    ForEach(this.puzzle!.grid, (row: number[], rowIndex: number) => {
                      ForEach(row, (cellValue: number, colIndex: number) => {
                        GridItem() {
                          Stack() {
                            // 显示数字
                            if (cellValue >= 0) {
                              Text(cellValue.toString())
                                .fontSize(16) // 减小字体大小以适应更小的网格
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.userState[rowIndex][colIndex] === -2 ? Color.White : Color.Black)
                                .align(Alignment.Center)
                            }
                            // 显示 X（灰色状态）
                            if (this.userState[rowIndex][colIndex] === -3) {
                              Text('X')
                                .fontSize(18) // 减小字体大小以适应更小的网格
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
                              ? '#7f4f92'
                              : '#ecf0f1'
                          )
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
                  .width(350) // 修改为350
                  .height(350) // 修改为350
                }
                .width(350) // 修改为350
                .height(350) // 修改为350
                .scale({ x: this.scaleValue, y: this.scaleValue })
                .translate({ x: this.offsetX, y: this.offsetY })
                .clip(true) // 添加裁剪属性，确保超出容器范围的内容被裁剪
                .onTouch((event: TouchEvent) => {
                  // 更新触摸点数量
                  this.touchPointCount = event.touches.length;

                  // 如果是多指触摸，设置标志并忽略单元格点击
                  if (this.touchPointCount > 1) {
                    this.isMultiTouch = true;
                    this.lastTouchedCell = null;
                    return;
                  }

                  // 如果刚刚结束多指操作，忽略接下来的单指操作
                  if (this.isMultiTouch && event.type === TouchType.Down) {
                    this.isMultiTouch = false;
                    return;
                  }

                  // 重置多指操作标志
                  if (event.type === TouchType.Up && this.touchPointCount === 0) {
                    this.isMultiTouch = false;
                  }

                  // 如果是多指操作后的第一次单指触摸，忽略它
                  if (this.isMultiTouch) {
                    return;
                  }

                  if (!this.gameStarted || this.gameFinished || this.puzzle === null || this.isScaling || this.isPanning) {
                    return;
                  }

                  // 多指触摸时不处理单元格点击
                  if (event.touches.length > 1) {
                    return;
                  }

                  if (event.type === TouchType.Down || event.type === TouchType.Move) {
                    // 获取触摸点相对于Grid的位置
                    const gridWidth = 350; // 修改为350
                    const gridHeight = 350; // 修改为350
                    const cellSize = gridWidth / this.puzzle.size;

                    // 计算触摸点所在的行和列
                    const touchX = event.touches[0].x;
                    const touchY = event.touches[0].y;

                    // 确保触摸点在Grid范围内
                    if (touchX >= 0 && touchX <= gridWidth && touchY >= 0 && touchY <= gridHeight) {
                      const col = Math.floor(touchX / cellSize);
                      const row = Math.floor(touchY / cellSize);

                      // 确保行列在有效范围内
                      if (row >= 0 && row < this.puzzle.size && col >= 0 && col < this.puzzle.size) {
                        // 如果是第一次触摸或移动到新单元格，更新状态
                        if (this.lastTouchedCell === null ||
                          this.lastTouchedCell.row !== row ||
                          this.lastTouchedCell.col !== col) {

                          // 播放点击音效
                          this.soundManager.play('click');

                          // 更新当前单元格状态
                          let newState = this.userState[row][col];
                          let updatedState = newState === -1 ? -2 : newState === -2 ? -3 : -1;
                          this.userState[row][col] = updatedState;

                          // 更新 answerState：黑色 = 1，其他 = 0
                          this.answerState[row][col] = updatedState === -2 ? 1 : 0;

                          // 记录最后触摸的单元格
                          this.lastTouchedCell = { row, col };

                          // 触发界面刷新
                          this.userState = [...this.userState];
                          this.answerState = [...this.answerState];
                        }
                      }
                    }
                  } else if (event.type === TouchType.Up) {
                    // 触摸结束，重置最后触摸的单元格
                    this.lastTouchedCell = null;
                  }
                })
                // 添加手势识别 - 使用parallelGesture来处理多个手势
                .parallelGesture(
                  PinchGesture()
                    .onActionStart((event: GestureEvent) => {
                      this.isScaling = true;
                      this.baseScale = this.scaleValue;
                    })
                    .onActionUpdate((event: GestureEvent) => {
                      // 计算新的缩放比例，限制在0.5到3倍之间
                      let newScale = this.baseScale * event.scale;
                      if (newScale < 1.0) newScale = 1.0;
                      if (newScale > 3.0) newScale = 3.0;
                      this.scaleValue = newScale;

                      // 限制偏移量，确保网格要么超出边框被遮挡，要么与边框重合
                      const maxOffset = this.calculateMaxOffset(this.scaleValue);
                      this.offsetX = Math.min(Math.max(this.offsetX, -maxOffset), maxOffset);
                      this.offsetY = Math.min(Math.max(this.offsetY, -maxOffset), maxOffset);
                    })
                    .onActionEnd(() => {
                      this.isScaling = false;
                    })
                    .onActionCancel(() => {
                      this.isScaling = false;
                    })
                )
                .parallelGesture(
                  PanGesture({ fingers: 2 }) // 双指滑动手势
                    .onActionStart((event: GestureEvent) => {
                      this.isPanning = true;
                      this.baseOffsetX = this.offsetX;
                      this.baseOffsetY = this.offsetY;
                    })
                    .onActionUpdate((event: GestureEvent) => {
                      if (this.isPanning) {
                        // 更新偏移量，限制在合理范围内
                        const maxOffset = this.calculateMaxOffset(this.scaleValue);
                        this.offsetX = Math.min(Math.max(this.baseOffsetX + event.offsetX, -maxOffset), maxOffset);
                        this.offsetY = Math.min(Math.max(this.baseOffsetY + event.offsetY, -maxOffset), maxOffset);
                      }
                    })
                    .onActionEnd(() => {
                      this.isPanning = false;
                    })
                    .onActionCancel(() => {
                      this.isPanning = false;
                    })
                )
              }
              .width(350) // 修改为350
              .height(350) // 修改为350
              .clip(true) // 确保内容不会超出边框
            }
            .width(350) // 修改为350
            .height(350) // 修改为350
          } else if (this.gameFinished) {
            // 游戏结束显示
            Column() {
              Text('游戏结束，请返回大厅')
                .fontSize(20)
                .fontColor('#FF7043')
                .fontWeight(FontWeight.Bold)
                .margin({ bottom: 20 })

              // 显示胜负结果
              if (this.opponentHasFinished && this.iWon) {
                Text('你们是平局！')
                  .fontSize(18)
                  .fontColor('#cd61ff')
                  .fontWeight(FontWeight.Bolder)
                  .textShadow({
                    radius: 0,
                    color: '#FFFFFF',
                    offsetX: 0,
                    offsetY: 0
                  })
                  .margin({ bottom: 10 })
              } else if (this.opponentHasFinished && (!this.iWon)) {
                Text('对手已获胜')
                  .fontSize(18)
                  .fontColor('#cd61ff')
                  .fontWeight(FontWeight.Bolder)
                  .textShadow({
                    radius: 0,
                    color: '#FFFFFF',
                    offsetX: 0,
                    offsetY: 0
                  })
                  .margin({ bottom: 10 })
              } else if (this.iWon && (!this.opponentHasFinished)) {
                Text('恭喜您获胜！')
                  .fontSize(18)
                  .fontColor('#cd61ff')
                  .fontWeight(FontWeight.Bolder)
                  .textShadow({
                    radius: 0,
                    color: '#FFFFFF',
                    offsetX: 0,
                    offsetY: 0
                  })
                  .margin({ bottom: 10 })
              }

              Text(`您的用时: ${this.elapsedTime} 秒`)
                .fontSize(16)
                .fontColor('#7f8c8d')
            }
            .height(350) // 修改为350
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .width(350) // 修改为350
            .backgroundColor('#f9f9f9')
            .borderRadius(8)
            .padding(20)
          } else if (this.puzzle !== null && !this.gameStarted) {
            // 等待游戏开始
            Column() {
              LoadingProgress()
                .width(50)
                .height(50)
                .color('#673B78')
                .margin({ bottom: 10 })
              Text('等待游戏开始...')
                .fontSize(16)
                .fontColor('#673B78')
            }
            .height(350) // 修改为350
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .width(350) // 修改为350
          } else {
            Column() {
              LoadingProgress()
                .width(50)
                .height(50)
                .color('#673B78')
                .margin({ bottom: 10 })
              Text('加载中...')
                .fontSize(16)
                .fontColor('#673B78')
            }
            .height(350) // 修改为350
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .width(350) // 修改为350
          }
        }
        .width('100%')
        .height(350) // 修改为350
        .margin({ bottom: 30 })
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)

        // 操作按钮
        Row() {
          Button('提 交 答 案')
            .width(150)
            .height(45)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundImage($r('app.media.multi_player_icon'))
            .backgroundImageSize(ImageSize.Cover)
            .backgroundImagePosition(Alignment.Center)
            .backgroundColor(this.gameStarted && !this.gameFinished ? 'rgba(231, 76, 60, 0.7)' : 'rgba(149, 165, 166, 0.7)')
            .borderRadius(8)
            .onClick(() => {
              if (this.gameStarted && !this.gameFinished && this.puzzle) {
                this.verifyAnswer()
              }
            })

          Button('返 回')
            .width(150)
            .height(45)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(Color.White)
            .backgroundImage($r('app.media.single_player_icon'))
            .backgroundImageSize(ImageSize.Cover)
            .backgroundImagePosition(Alignment.Center)
            .backgroundColor('rgba(52, 152, 219, 0.7)')
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
    }
    .width('100%')
    .height('100%')
  }
}