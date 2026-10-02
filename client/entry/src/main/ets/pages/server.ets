import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import bluetooth from '@ohos.bluetooth';

// ---------------- 类型定义 ----------------
interface Puzzle {
  id: number;
  size: number;
  grid: number[][];
}

interface ProgressUpdateData {
  progress: number;
}

interface GameFinishedData {
  time: number;
  correct: boolean;
}

interface StartGameMessage {
  type: 'start_game';
  data?: Puzzle;
}

interface ProgressUpdateMessage {
  type: 'progress_update';
  data: ProgressUpdateData;
}

interface GameFinishedMessage {
  type: 'game_finished';
  data: GameFinishedData;
}

type BattleMessage = StartGameMessage | ProgressUpdateMessage | GameFinishedMessage;

interface BluetoothDevice {
  deviceId: string;
  name?: string;
  rssi?: number;
}

// ---------------- 声明 TextEncoder/Decoder ----------------


// ---------------- 页面组件 ----------------
@Entry
@Component
struct BluetoothBattlePage {
  // 蓝牙状态
  @State discoveredDevices: Array<BluetoothDevice> = [];
  @State isDiscovering: boolean = false;
  @State connectedDevice: BluetoothDevice | null = null;
  @State connectionState: 'disconnected' | 'connecting' | 'connected' = 'disconnected';

  // 游戏状态
  @State battleState: 'setup' | 'playing' | 'finished' = 'setup';
  @State gameResult: 'win' | 'lose' | '' = '';
  @State showResultDialog: boolean = false;

  // 题目数据
  @State puzzle: Puzzle | null = null;
  @State userState: number[][] = [];
  @State answerState: number[][] = [];

  // 对手进度
  @State opponentProgress: number = 0;

  // 计时器
  @State elapsedTime: number = 0;
  private timer: number | undefined = undefined;

  // ---------------- 蓝牙方法 ----------------
  // ---------------- 蓝牙方法 ----------------
  // ---------------- 蓝牙方法 ----------------
  async enableBluetooth() {
    try {
      // 检查蓝牙状态
      const state = bluetooth.getState();
      if (state === bluetooth.BluetoothState.STATE_OFF) {
        // 如果蓝牙关闭，提示用户开启
        promptAction.showToast({ message: '请在系统中开启蓝牙', duration: 2000 });
        return;
      }

      // 蓝牙已开启
      promptAction.showToast({ message: '蓝牙已就绪', duration: 2000 });

      // 开始发现设备
      this.startDiscovery();

    } catch (error) {
      console.error('蓝牙初始化失败:', error);
      promptAction.showToast({ message: '蓝牙初始化失败', duration: 2000 });
    }
  }

  startDiscovery() {
    this.isDiscovering = true;
    this.discoveredDevices = [];

    // 模拟设备扫描
    setTimeout(() => {
      this.discoveredDevices = [
        { deviceId: '001', name: '设备A' },
        { deviceId: '002', name: '设备B' }
      ];
      this.isDiscovering = false;
    }, 3000);
  }

  stopDiscovery() {
    this.isDiscovering = false;
  }

  async connectToDevice(device: BluetoothDevice) {
    this.connectionState = 'connecting';
    // 模拟连接延迟
    setTimeout(() => {
      this.connectedDevice = device;
      this.connectionState = 'connected';
      promptAction.showToast({ message: `已连接到 ${device.name}`, duration: 2000 });

      // 开始游戏
      this.startBattle();
    }, 1000);
  }

  sendMessageToOpponent(msg: BattleMessage) {
    console.log('发送消息给对手:', msg);
  }

  // ---------------- 游戏逻辑 ----------------
  startBattle() {
    this.battleState = 'playing';
    this.loadPuzzle();
    this.startTimer();

    if (this.puzzle) {
      this.sendMessageToOpponent({ type: 'start_game', data: this.puzzle });
    }
  }

  loadPuzzle() {
    this.puzzle = {
      id: 1,
      size: 5,
      grid: [
        [1,0,1,0,1],
        [0,1,0,1,0],
        [1,0,1,0,1],
        [0,1,0,1,0],
        [1,0,1,0,1]
      ]
    };
    const size = this.puzzle.size;
    this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
    this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
  }

  startTimer() {
    this.elapsedTime = 0;
    this.timer = setInterval(() => this.elapsedTime += 1, 1000);
  }

  stopTimer() {
    if (this.timer !== undefined) {
      clearInterval(this.timer);
      this.timer = undefined;
    }
  }

  handleCellClick(row: number, col: number) {
    if (this.battleState !== 'playing') return;

    let newState = this.userState[row][col];
    let updatedState = newState === -1 ? -2 : newState === -2 ? -3 : -1;
    this.userState[row][col] = updatedState;
    this.answerState[row][col] = updatedState === -2 ? 1 : 0;
    this.userState = [...this.userState];
    this.answerState = [...this.answerState];

    // 更新进度
    const progress = this.calculateProgress();
    this.sendMessageToOpponent({ type: 'progress_update', data: { progress } });
  }

  calculateProgress(): number {
    if (!this.puzzle) return 0;
    let filled = 0;
    let total = this.puzzle.size * this.puzzle.size;
    for (let i = 0; i < this.puzzle.size; i++) {
      for (let j = 0; j < this.puzzle.size; j++) {
        if (this.userState[i][j] === -2) filled++;
      }
    }
    return Math.round((filled / total) * 100);
  }

  submitAnswer() {
    if (this.battleState !== 'playing') return;
    const isCorrect = this.validateAnswer();
    if (!isCorrect) {
      promptAction.showToast({ message: '答案不正确', duration: 2000 });
      return;
    }

    this.battleState = 'finished';
    this.gameResult = 'win';
    this.showResultDialog = true;
    this.stopTimer();

    this.sendMessageToOpponent({ type: 'game_finished', data: { time: this.elapsedTime, correct: true } });
  }

  validateAnswer(): boolean {
    return true; // 简化
  }

  handleOpponentMessage(msg: BattleMessage) {
    if (msg.type === 'start_game') {
      this.puzzle = msg.data || this.puzzle;
      this.loadPuzzle();
    } else if (msg.type === 'progress_update') {
      this.opponentProgress = msg.data.progress;
    } else if (msg.type === 'game_finished') {
      this.battleState = 'finished';
      this.gameResult = 'lose';
      this.showResultDialog = true;
      this.stopTimer();
    }
  }

  backToHome() {
    router.back();
  }

  // ---------------- UI ----------------
  build() {
    Column() {
      // 顶部状态
      Row() {
        Text(`时间: ${this.elapsedTime}s`).fontSize(16);
        Text(`进度: ${this.calculateProgress()}%`).fontSize(16).margin({ left: 20 });
        Text(`对手: ${this.opponentProgress}%`).fontSize(16).margin({ left: 20 });
      }
      .padding(10)
      .width('100%');

      // 游戏网格
      if (this.puzzle && this.battleState === 'playing') {
        Grid() {
          ForEach(this.puzzle.grid, (row: number[], rowIndex: number) => {
            ForEach(row, (cell: number, colIndex: number) => {
              GridItem() {
                Stack() {
                  if (cell >= 0) {
                    Text(cell.toString()).fontSize(20);
                  }
                }
                .width('100%').height('100%')
                .backgroundColor(
                  this.userState[rowIndex][colIndex] === -1 ? Color.White :
                    this.userState[rowIndex][colIndex] === -2 ? '#34495e' : '#ecf0f1'
                )
                .onClick(() => this.handleCellClick(rowIndex, colIndex));
              }
              .border({ width: 1, color: '#bdc3c7' });
            });
          });
        }
        .columnsTemplate(`repeat(${this.puzzle.size}, 1fr)`)
        .rowsTemplate(`repeat(${this.puzzle.size}, 1fr)`)
        .width(300).height(300).margin(20);
      }

      // 提交按钮
      if (this.battleState === 'playing') {
        Button('提交答案').width(200).height(50).fontSize(18)
          .onClick(() => this.submitAnswer()).margin(10);
      }

      // 结果对话框
      if (this.showResultDialog) {
        Stack() {
          Column() {
            Text(this.gameResult === 'win' ? '胜利！' : '失败！').fontSize(24).fontColor('#27ae60');
            Text(this.gameResult === 'win' ? `用时: ${this.elapsedTime}s` : '对手先完成了题目').fontSize(16).margin({ top: 5 });

            Button('返回主页').width(150).height(40).margin({ top: 20 }).onClick(() => this.backToHome());
          }
          .padding(20).backgroundColor(Color.White).borderRadius(12);
        }
        .width('100%').height('100%')
        .position({ x: 0, y: 0 }).backgroundColor('rgba(0,0,0,0.5)')

      }
    }
    .width('100%').height('100%')
    .onAppear(() => this.enableBluetooth())
    .onDisAppear(() => this.stopTimer());
  }
}
