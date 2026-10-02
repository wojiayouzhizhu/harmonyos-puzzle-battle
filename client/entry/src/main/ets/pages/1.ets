import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import router from '@ohos.router';
import storage from '@ohos.data.storage'; // 添加存储模块

interface PuzzleData {
  id: number
  size: number
  grid: number[]
  solution: number[][]
}

interface VerifyResponse {
  correct: boolean
  message?: string
}

// 用户状态接口
interface UserStateData {
  userState: number[][]
  answerState: number[][]
}

@Entry
@Component
struct PuzzleGame {
  @State puzzle: PuzzleData | null = null
  @State userState: number[][] = []    // 显示状态：-1 白色 -2 黑色 -3 灰色
  @State answerState: number[][] = []  // 用户答案：0 或 1
  @State difficulty: string = 'easy'   // 当前难度
  @State isVerifying: boolean = false  // 是否正在验证
  @State verifyResult: VerifyResponse | null = null // 验证结果
  @State showResult: boolean = false   // 是否显示结果
  @State currentLevelId: number = 1    // 当前关卡ID
  @State totalLevels: number = 0       // 总关卡数

  // 存储对象
  storage: storage.Storage | null = null

  // 动画参数
  @State scaleAnim: number = 0
  @State opacityAnim: number = 0

  aboutToAppear() {
    // 初始化存储 - 使用正确的API
    try {
      this.storage = storage.getStorageSync('/data/storage/el2/puzzle_game');
      const params: Record<string, string> = router.getParams() as Record<string, string>;
      this.difficulty = params['difficulty'] ?? 'easy';
      this.currentLevelId = parseInt(params['levelId'] ?? '1');
      this.fetchGridData(this.difficulty, this.currentLevelId);
    } catch (err) {
      console.error('Failed to initialize storage', err);
      const params: Record<string, string> = router.getParams() as Record<string, string>;
      this.difficulty = params['difficulty'] ?? 'easy';
      this.currentLevelId = parseInt(params['levelId'] ?? '1');
      this.fetchGridData(this.difficulty, this.currentLevelId);
    }
  }

  fetchGridData(difficulty: string, levelId: number) {
    let httpRequest = http.createHttp();
    httpRequest.request(
      `http://10.34.58.201:3000/api/game?difficulty=${difficulty}&levelId=${levelId}`,
      {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING
      },
      (err: Error, data: http.HttpResponse) => {
        if (!err && data.responseCode == 200) {
          try {
            let level: PuzzleData = JSON.parse(data.result as string);
            this.puzzle = level;

            // 尝试从存储中加载用户状态
            this.loadUserState(difficulty, levelId, level.size);

            // 获取总关卡数（假设API返回了总关卡数信息）
            if (data.result && JSON.parse(data.result as string).totalLevels) {
              this.totalLevels = JSON.parse(data.result as string).totalLevels;
            }
          } catch (e) {
            console.error('解析关卡数据失败', e);
          }
        } else {
          console.error('获取关卡失败', JSON.stringify(err));
          promptAction.showToast({ message: '获取关卡失败', duration: 2000 });
        }
        httpRequest.destroy();
      }
    );
  }

  // 从存储加载用户状态
  loadUserState(difficulty: string, levelId: number, size: number) {
    if (!this.storage) {
      // 如果没有存储对象，初始化默认状态
      this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
      this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
      return;
    }

    const key = `${difficulty}_${levelId}`;
    try {
      const storedData: string = this.storage.getSync(key, '') as string;

      if (storedData) {
        try {
          const userStateData: UserStateData = JSON.parse(storedData);
          this.userState = userStateData.userState;
          this.answerState = userStateData.answerState;
        } catch (e) {
          console.error('解析存储数据失败', e);
          // 如果解析失败，初始化默认状态
          this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
          this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
        }
      } else {
        // 如果没有存储的数据，初始化默认状态
        this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
        this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
      }
    } catch (e) {
      console.error('获取存储数据失败', e);
      this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
      this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
    }

    // 重置验证状态
    this.verifyResult = null;
    this.showResult = false;
  }

  // 保存用户状态到存储
  saveUserState() {
    if (!this.storage || !this.puzzle) return;

    const key = `${this.difficulty}_${this.currentLevelId}`;
    const userStateData: UserStateData = {
      userState: this.userState,
      answerState: this.answerState
    };

    try {
      this.storage.putSync(key, JSON.stringify(userStateData));
      this.storage.flushSync();
    } catch (e) {
      console.error('保存用户状态失败', e);
    }
  }

  // 验证答案
  verifyAnswer() {
    if (!this.puzzle) return;

    this.isVerifying = true;
    let httpRequest = http.createHttp();
    httpRequest.request(
      `http://10.34.58.201:3000/api/verify`,
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        extraData: JSON.stringify({
          id: this.puzzle.id,
          difficulty: this.difficulty,
          answer: this.answerState
        })
      },
      (err: Error, res: http.HttpResponse) => {
        this.isVerifying = false;
        if (!err && res.responseCode === 200) {
          try {
            const result: VerifyResponse = JSON.parse(res.result as string);
            this.verifyResult = result;
            this.showResult = true;

            // 启动动画
            this.scaleAnim = 0;
            this.opacityAnim = 0;
            setTimeout(() => {
              this.scaleAnim = 1;
              this.opacityAnim = 1;
            }, 10);

            // 5秒后自动隐藏结果
            setTimeout(() => {
              this.showResult = false;
            }, 5000);

          } catch (e) {
            promptAction.showToast({ message: '解析响应失败', duration: 2000 });
          }
        } else {
          promptAction.showToast({ message: '提交失败', duration: 2000 });
        }
        httpRequest.destroy();
      }
    );
  }

  // 下一关
  nextLevel() {
    // 保存当前关卡状态
    this.saveUserState();

    if (this.currentLevelId < this.totalLevels) {
      this.currentLevelId++;
      this.fetchGridData(this.difficulty, this.currentLevelId);
    } else {
      promptAction.showToast({ message: '已经是最后一关了', duration: 2000 });
    }
  }

  // 上一关
  prevLevel() {
    // 保存当前关卡状态
    this.saveUserState();

    if (this.currentLevelId > 1) {
      this.currentLevelId--;
      this.fetchGridData(this.difficulty, this.currentLevelId);
    } else {
      promptAction.showToast({ message: '已经是第一关了', duration: 2000 });
    }
  }

  build() {
    Column() {
      // 标题和关卡信息
      Column() {
        Text('像素填空游戏')
          .fontSize(30)
          .fontWeight(FontWeight.Bold)
          .margin({ top: 20, bottom: 5 })
          .textAlign(TextAlign.Center)
          .width('100%')
          .fontColor('#2c3e50')

        // 显示当前关卡信息
        if (this.puzzle) {
          Text(`关卡: ${this.currentLevelId}/${this.totalLevels || '?'}`)
            .fontSize(16)
            .fontColor('#7f8c8d')
            .margin({ bottom: 10 })
        }
      }

      // 游戏说明
      Text('点击格子切换状态：空白→黑色→灰色→空白')
        .fontSize(14)
        .fontColor('#7f8c8d')
        .margin({ bottom: 20 })
        .textAlign(TextAlign.Center)
        .width('100%')

      // 验证结果提示
      if (this.showResult && this.verifyResult) {
        Stack() {
          Column() {
            if (this.verifyResult.correct) {
              Image($r('app.media.success')) // 正确图标
                .width(60)
                .height(60)
                .margin({ bottom: 10 })
              Text('恭喜！答案正确！')
                .fontSize(20)
                .fontColor('#27ae60')
                .fontWeight(FontWeight.Bold)

              // 添加下一关按钮（仅在答案正确时显示）
              if (this.currentLevelId < (this.totalLevels || Infinity)) {
                Button('下一关')
                  .width(120)
                  .height(40)
                  .fontSize(16)
                  .backgroundColor('#3498db')
                  .fontColor(Color.White)
                  .margin({ top: 15 })
                  .onClick(() => {
                    // 保存当前状态
                    this.saveUserState();
                    this.nextLevel();
                    this.showResult = false;
                  })
              }
            } else {
              Image($r('app.media.error')) // 错误图标
                .width(60)
                .height(60)
                .margin({ bottom: 10 })
              Text('答案不正确，请再试一次')
                .fontSize(20)
                .fontColor('#e74c3c')
                .fontWeight(FontWeight.Bold)
            }
          }
          .padding(20)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .shadow({ radius: 10, color: '#cccccc', offsetX: 0, offsetY: 2 })
        }
        .width('100%')
        .height('100%')
        .position({ x: 0, y: 0 })
        .zIndex(10)
        .scale({ x: this.scaleAnim, y: this.scaleAnim })
        .opacity(this.opacityAnim)
        .onClick(() => {
          // 点击任意位置关闭提示
          this.showResult = false;
        })
      }

      // 游戏网格
      Column() {
        if (this.puzzle != null) {
          Grid() {
            ForEach(this.puzzle.grid, (row: number[], rowIndex: number) => {
              ForEach(row, (originalValue: number, colIndex: number) => {
                GridItem() {
                  Stack() {
                    // 显示数字
                    if (originalValue >= 0) {
                      Text(originalValue.toString())
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
                    // 点击格子循环状态
                    let newState = this.userState[rowIndex][colIndex];
                    let updatedState = newState === -1 ? -2 : newState === -2 ? -3 : -1;
                    this.userState[rowIndex][colIndex] = updatedState;

                    // 更新 answerState：黑色 = 1，其他 = 0
                    this.answerState[rowIndex][colIndex] = updatedState === -2 ? 1 : 0;

                    // 触发界面刷新
                    this.userState = [...this.userState];
                    this.answerState = [...this.answerState];

                    // 保存状态
                    this.saveUserState();
                  })
                }
                .border({ width: 1, color: '#bdc3c7' })
              })
            })
          }
          .columnsTemplate(`repeat(${this.puzzle.size}, 1fr)`)
          .rowsTemplate(`repeat(${this.puzzle.size}, 1fr)`)
          .columnsGap(0)
          .rowsGap(0)
          .width('90%')
          .height(400)
          .border({ width: 2, color: '#34495e' })
          .margin({ bottom: 20 })
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

      // 关卡导航按钮
      Row() {
        Button('上一关')
          .width(100)
          .height(40)
          .fontSize(14)
          .backgroundColor(this.currentLevelId > 1 ? '#3498db' : '#95a5a6')
          .onClick(() => {
            this.prevLevel();
          })

        Text(`关卡 ${this.currentLevelId}`)
          .fontSize(16)
          .fontWeight(FontWeight.Bold)
          .margin({ left: 20, right: 20 })
          .width(80)
          .textAlign(TextAlign.Center)

        Button('下一关')
          .width(100)
          .height(40)
          .fontSize(14)
          .backgroundColor(this.currentLevelId < (this.totalLevels || Infinity) ? '#3498db' : '#95a5a6')
          .onClick(() => {
            this.nextLevel();
          })
      }
      .margin({ bottom: 20 })

      // 提交与返回按钮
      Row() {
        Button(this.isVerifying ? '验证中...' : '提交答案')
          .width(150)
          .height(45)
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .backgroundColor(this.isVerifying ? '#95a5a6' : '#3498db')
          .borderRadius(8)
          .opacity(this.isVerifying ? 0.7 : 1)
          .onClick(() => {
            if (!this.isVerifying && this.puzzle) {
              this.verifyAnswer();
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
            // 保存当前状态
            this.saveUserState();
            router.push({ url: 'pages/select_difficulty' });
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
