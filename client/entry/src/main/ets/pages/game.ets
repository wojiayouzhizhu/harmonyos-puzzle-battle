import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import router from '@ohos.router';
import storage from '@ohos.data.storage';
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
//import resourceManager from '@ohos.resourceManager';
import { common } from '@kit.AbilityKit';

// 添加音效管理器类
@ObservedV2
class SoundEffectManager {
  private avPlayer: media.AVPlayer | null = null;
  private isPrepared: boolean = false;

  async initSound() {
    try {
      const context = getContext() as common.UIAbilityContext;
      const resourceMgr = context.resourceManager;

      // 获取rawfile下音效文件的路径
      const rawfilePath = 'click_sound.mp3';
      const fdInfo = await resourceMgr.getRawFd(rawfilePath);

      this.avPlayer = await media.createAVPlayer();
      this.setAVPlayerCallback(this.avPlayer);

      // 使用fd方式设置音频源
      this.avPlayer.fdSrc = {
        fd: fdInfo.fd,
        offset: fdInfo.offset,
        length: fdInfo.length
      };
    } catch (error) {
      console.error('初始化音频播放器失败:', JSON.stringify(error));
    }
  }

  setAVPlayerCallback(avPlayer: media.AVPlayer) {
    avPlayer.on('stateChange', async (state: string) => {
      switch (state) {
        case 'initialized':
          avPlayer.prepare();
          break;
        case 'prepared':
          this.isPrepared = true;
          console.info('音效准备完成');
          break;
        case 'completed':
          avPlayer.seek(0);
          break;
      }
    });

    avPlayer.on('error', (err: BusinessError) => {
      console.error('音频播放错误:', JSON.stringify(err));
    });
  }

  async play() {
    if (this.avPlayer && this.isPrepared) {
      try {
        this.avPlayer.seek(0);
        this.avPlayer.play();
      } catch (error) {
        console.error('播放音效失败:', JSON.stringify(error));
      }
    }
  }

  async release() {
    if (this.avPlayer) {
      this.avPlayer.release();
      this.avPlayer = null;
      this.isPrepared = false;
    }
  }
}

interface PuzzleData {
  id: number
  size: number
  grid: number[]
  solution: number[][]
}

interface VerifyResponse {
  correct: boolean
  message?: string
  correctAnswer?: number[][]; // 添加这个字段
}

// 用户状态接口
interface UserStateData {
  userState: number[][]
  answerState: number[][]
}

// 保存的游戏进度
interface GameProgress {
  userId: string
  difficulty: string
  levelId: number
  timestamp: number
}

interface GeneratedTypeLiteralInterface_1 {
  row: number;
  col: number;
}

// 定义一个接口或类型来声明每个单元格
interface Cell {
  row: number;
  col: number;
}

// 添加游戏完成状态接口
interface GameCompletion {
  completedLevels: number[];
  allLevelsCompleted: boolean;
}


@Entry
@Component
struct PuzzleGame {
  @State puzzle: PuzzleData | null = null
  @State userState: number[][] = []
  @State answerState: number[][] = []
  @State difficulty: string = 'easy'
  @State isVerifying: boolean = false
  @State verifyResult: VerifyResponse | null = null
  @State showResult: boolean = false
  @State currentLevelId: number = 1
  @State totalLevels: number = 0
  @State showSaveDialog: boolean = false
  @State showContinueDialog: boolean = false
  @State hasSavedProgress: boolean = false
  @State storedLevels: string[] = []
  @State userId: string = 'default_user' // 用户标识，可以从登录系统获取
  @State showUserDialog: boolean = false
  @State tempUserId: string = ''
  @State lastTouchedCell: GeneratedTypeLiteralInterface_1 | null = null

  @State showHint: boolean = false
  @State showAnswer: boolean = false
  @State incorrectCells: Cell[] = [];
  @State isPreviewMode: boolean = false; // 用于标识是否处于预览模式
  // 添加缩放相关状态
  @State scaleValue: number = 1.0
  @State baseScale: number = 1.0
  @State isScaling: boolean = false

  // 在PuzzleGame组件顶部添加以下状态变量
  @State offsetX: number = 0;
  @State offsetY: number = 0;
  @State baseOffsetX: number = 0;
  @State baseOffsetY: number = 0;
  @State isPanning: boolean = false;

  // 添加防误触状态变量
  @State touchPointCount: number = 0;
  @State isMultiTouch: boolean = false;

  // 存储对象
  storage: storage.Storage | null = null

  // 动画参数
  @State scaleAnim: number = 0
  @State opacityAnim: number = 0

  // 添加音效管理器
  private soundManager: SoundEffectManager = new SoundEffectManager();

  // 添加游戏完成状态
  @State completedLevels: number[] = []; // 存储已完成的关卡ID
  @State showWinDialog: boolean = false; // 控制获胜窗口显示

  aboutToAppear() {
    // 初始化音效管理器
    this.soundManager.initSound();

    try {
      this.storage = storage.getStorageSync('/data/storage/el2/puzzle_game');

      // 步骤1：读取路由参数中的userId
      const params: Record<string, string> = router.getParams() as Record<string, string>;
      let newUserId = params['userId'] || '';

      // 步骤2：确定最终用户ID并确保存储中存在current_user_id
      if (newUserId) {
        // 路由有userId，直接使用并更新存储
        this.userId = newUserId.trim();
        this.storage.putSync('current_user_id', this.userId);
        this.storage.flushSync();
      } else {
        // 路由无userId，从存储读取
        try {
          const currentUserId: string = this.storage.getSync('current_user_id', 'default_user') as string;
          this.userId = currentUserId;
          // 关键修复：如果是首次使用（存储中无current_user_id），主动写入默认值
          if (currentUserId === 'default_user') {
            this.storage.putSync('current_user_id', 'default_user');
            this.storage.flushSync();
          }
        } catch (e) {
          // 读取失败时，使用默认值并强制写入存储
          this.userId = 'default_user';
          this.storage.putSync('current_user_id', 'default_user');
          this.storage.flushSync();
        }
      }

      // 后续步骤保持不变...
      try {
        const storedLevelsKey = `${this.userId}_stored_levels_list`;
        const storedLevelsStr: string = this.storage.getSync(storedLevelsKey, '[]') as string;
        this.storedLevels = JSON.parse(storedLevelsStr);
      } catch (e) {
        this.storedLevels = [];
      }

      this.difficulty = params['difficulty'] ?? 'easy';
      this.currentLevelId = parseInt(params['levelId'] ?? '1');

      // 加载已完成的关卡
      this.loadCompletedLevels();

      this.checkSavedProgress();

      if (params['fromMainMenu'] === 'true' && this.hasSavedProgress) {
        this.showContinueDialog = true;
      } else {
        this.fetchGridData(this.difficulty, this.currentLevelId);
      }
    } catch (err) {
      console.error('Failed to initialize storage', err);
      const params: Record<string, string> = router.getParams() as Record<string, string>;
      this.difficulty = params['difficulty'] ?? 'easy';
      this.currentLevelId = parseInt(params['levelId'] ?? '1');
      this.fetchGridData(this.difficulty, this.currentLevelId);
    }
  }

  // 加载已完成的关卡
  loadCompletedLevels() {
    if (!this.storage) return;

    try {
      const completedLevelsKey = `${this.userId}_${this.difficulty}_completed_levels`;
      const completedLevelsStr: string = this.storage.getSync(completedLevelsKey, '[]') as string;
      this.completedLevels = JSON.parse(completedLevelsStr);
    } catch (e) {
      console.error('加载已完成关卡失败', e);
      this.completedLevels = [];
    }
  }

  // 保存已完成的关卡
  saveCompletedLevels() {
    if (!this.storage) return;

    try {
      const completedLevelsKey = `${this.userId}_${this.difficulty}_completed_levels`;
      this.storage.putSync(completedLevelsKey, JSON.stringify(this.completedLevels));
      this.storage.flushSync();
    } catch (e) {
      console.error('保存已完成关卡失败', e);
    }
  }

  // 标记关卡为已完成
  markLevelAsCompleted(levelId: number) {
    if (!this.completedLevels.includes(levelId)) {
      this.completedLevels = [...this.completedLevels, levelId];
      this.saveCompletedLevels();

      // 检查是否所有关卡都已完成
      if (this.completedLevels.length === this.totalLevels) {
        this.showWinDialog = true;
      }
    }
  }

  // 检查是否所有关卡都已完成
  checkAllLevelsCompleted() {
    return this.completedLevels.length === this.totalLevels;
  }

  // 切换用户
  switchUser(newUserId: string) {
    // 补充：过滤空ID和与当前ID相同的情况，避免无效操作
    if (!this.storage || !newUserId.trim() || newUserId.trim() === this.userId) return;

    this.userId = newUserId.trim();
    this.storage.putSync('current_user_id', this.userId);
    this.storage.flushSync();

    // 重新加载新用户的存储数据
    try {
      const storedLevelsKey = `${this.userId}_stored_levels_list`;
      const storedLevelsStr: string = this.storage.getSync(storedLevelsKey, '[]') as string;
      this.storedLevels = JSON.parse(storedLevelsStr);
    } catch (e) {
      this.storedLevels = [];
    }

    // 重新加载新用户的已完成关卡
    this.loadCompletedLevels();

    this.checkSavedProgress();
    this.fetchGridData(this.difficulty, this.currentLevelId);

    promptAction.showToast({ message: `已切换到用户: ${this.userId}`, duration: 2000 });
  }

  // 检查是否有保存的进度
  checkSavedProgress() {
    if (!this.storage) return;

    try {
      const progressKey = `${this.userId}_saved_progress`;
      const progress: string = this.storage.getSync(progressKey, '') as string;
      this.hasSavedProgress = !!progress;
    } catch (e) {
      console.error('检查保存进度失败', e);
      this.hasSavedProgress = false;
    }
  }

  loadSavedProgress() {
    if (!this.storage) return;

    try {
      const progressKey = `${this.userId}_saved_progress`;
      const progressStr: string = this.storage.getSync(progressKey, '') as string;
      if (progressStr) {
        const progress: GameProgress = JSON.parse(progressStr);
        this.difficulty = progress.difficulty;
        this.currentLevelId = progress.levelId;
        // 关键补充：加载新关卡前，重置旧用户的状态（避免界面残留）
        this.userState = [];
        this.answerState = [];
        this.fetchGridData(this.difficulty, this.currentLevelId);
      }
    } catch (e) {
      console.error('加载保存进度失败', e);
      // 异常时同样重置状态
      this.userState = [];
      this.answerState = [];
      this.fetchGridData(this.difficulty, this.currentLevelId);
    }
  }
  // 清除保存的进度
  clearSavedProgress() {
    if (!this.storage) return;

    try {
      const progressKey = `${this.userId}_saved_progress`;
      this.storage.deleteSync(progressKey);
      this.storage.flushSync();
      this.hasSavedProgress = false;
    } catch (e) {
      console.error('清除保存进度失败', e);
    }
  }

  // 清除当前关卡数据
  clearCurrentLevelData() {
    if (!this.storage) return;

    try {
      const key = `${this.userId}_${this.difficulty}_${this.currentLevelId}`;
      this.storage.deleteSync(key);
      this.storage.flushSync();
      console.log('已清除当前关卡数据');
    } catch (e) {
      console.error('清除当前关卡数据失败', e);
    }
  }

  // 保存游戏进度
  saveGameProgress() {
    if (!this.storage) return;

    const progress: GameProgress = {
      userId: this.userId,
      difficulty: this.difficulty,
      levelId: this.currentLevelId,
      timestamp: new Date().getTime()
    };

    try {
      const progressKey = `${this.userId}_saved_progress`;
      this.storage.putSync(progressKey, JSON.stringify(progress));
      this.storage.flushSync();
      this.hasSavedProgress = true;
      promptAction.showToast({ message: '游戏进度已保存', duration: 2000 });
    } catch (e) {
      console.error('保存游戏进度失败', e);
      promptAction.showToast({ message: '保存失败', duration: 2000 });
    }
  }

  fetchGridData(difficulty: string, levelId: number) {
    let httpRequest = http.createHttp();
    httpRequest.request(
      `http://10.0.2.2:3000/api/game?difficulty=${difficulty}&levelId=${levelId}`,
      {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING
      },
      (err: Error, data: http.HttpResponse) => {
        if (!err && data.responseCode == 200) {
          try {
            let level: PuzzleData = JSON.parse(data.result as string);
            this.puzzle = level;
            this.loadUserState(difficulty, levelId, level.size);

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
      this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
      this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
      return;
    }

    const key = `${this.userId}_${difficulty}_${levelId}`;
    try {
      const storedData: string = this.storage.getSync(key, '') as string;

      if (storedData) {
        try {
          const userStateData: UserStateData = JSON.parse(storedData);
          this.userState = userStateData.userState;
          this.answerState = userStateData.answerState;

          // 添加到已存储关卡列表（如果还没有）
          if (!this.storedLevels.includes(key)) {
            this.storedLevels = [...this.storedLevels, key];
            this.saveStoredLevelsList();
          }
        } catch (e) {
          console.error('解析存储数据失败', e);
          this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
          this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
        }
      } else {
        this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
        this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
      }
    } catch (e) {
      console.error('获取存储数据失败', e);
      this.userState = Array(size).fill(0).map(() => Array(size).fill(-1));
      this.answerState = Array(size).fill(0).map(() => Array(size).fill(0));
    }

    this.verifyResult = null;
    this.showResult = false;
  }

  // 保存用户状态到存储
  saveUserState() {
    if (!this.storage || !this.puzzle) return;

    const key = `${this.userId}_${this.difficulty}_${this.currentLevelId}`;
    const userStateData: UserStateData = {
      userState: this.userState,
      answerState: this.answerState
    };

    try {
      this.storage.putSync(key, JSON.stringify(userStateData));
      this.storage.flushSync();

      // 记录已存储的关卡（如果还没有记录）
      if (!this.storedLevels.includes(key)) {
        this.storedLevels = [...this.storedLevels, key];
        this.saveStoredLevelsList();
      }
    } catch (e) {
      console.error('保存用户状态失败', e);
    }
  }


  // 保存 storedLevels 列表到持久化存储
  saveStoredLevelsList() {
    if (!this.storage) return;

    try {
      const storedLevelsKey = `${this.userId}_stored_levels_list`;
      this.storage.putSync(storedLevelsKey, JSON.stringify(this.storedLevels));
      this.storage.flushSync();
    } catch (e) {
      console.error('保存storedLevels列表失败', e);
    }
  }

  // 验证答案
  verifyAnswer() {
    if (!this.puzzle) return;

    this.isVerifying = true;
    let httpRequest = http.createHttp();
    httpRequest.request(
      `http://10.0.2.2:3000/api/verify`,
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

            // 如果答案正确，标记当前关卡为已完成
            if (result.correct) {
              this.markLevelAsCompleted(this.currentLevelId);
            }

            this.scaleAnim = 0;
            this.opacityAnim = 0;
            setTimeout(() => {
              this.scaleAnim = 1;
              this.opacityAnim = 1;
            }, 10);

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

  // 清除当前难度的所有关卡数据
  clearCurrentDifficultyData() {
    if (!this.storage) return;

    try {
      // 只清除当前难度且记录在storedLevels中的关卡
      const keysToDelete = this.storedLevels.filter(key =>
      key.startsWith(`${this.userId}_${this.difficulty}_`)
      );

      keysToDelete.forEach(key => {
        try {
          this.storage!.deleteSync(key);
          console.log(`已删除关卡数据: ${key}`);
        } catch (e) {
          console.error(`删除键 ${key} 失败`, e);
        }
      });

      // 从记录中移除已删除的关卡
      this.storedLevels = this.storedLevels.filter(key =>
      !key.startsWith(`${this.userId}_${this.difficulty}_`)
      );

      // 更新持久化的 storedLevels
      this.saveStoredLevelsList();

      this.storage.flushSync();
      console.log(`已清除用户 ${this.userId} 的 ${this.difficulty} 难度所有关卡数据`);
    } catch (e) {
      console.error('清除当前难度关卡数据失败', e);
    }
  }

  // 下一关
  nextLevel() {
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
    this.saveUserState();

    if (this.currentLevelId > 1) {
      this.currentLevelId--;
      this.fetchGridData(this.difficulty, this.currentLevelId);
    } else {
      promptAction.showToast({ message: '已经是第一关了', duration: 2000 });
    }
  }

  // 返回主菜单
  backToMenu(saveProgress: boolean) {
    if (saveProgress) {
      this.saveGameProgress();
      // 正常保存当前关卡状态
      this.saveUserState();
    } else {
      this.clearSavedProgress();
      // 清除当前难度的所有关卡数据
      this.clearCurrentDifficultyData();
    }

    router.push({
      url: 'pages/select_difficulty',
      params: { userId: this.userId }
    });
  }

  aboutToDisappear() {
    // 释放音效资源
    this.soundManager.release();
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
  // 恢复原始状态（用于取消预览）
  restoreOriginalState() {
    this.isPreviewMode = false; // 重置预览模式
    // 这里需要重新从存储加载用户原始状态
    this.loadUserState(this.difficulty, this.currentLevelId, this.puzzle!.size);
    promptAction.showToast({ message: '已恢复您的答案', duration: 2000 });
  }


  // 高亮错误单元格并发送请求获取正确答案
  highlightIncorrectCells() {
    if (!this.puzzle) return;

    // 发送请求获取正确答案
    let httpRequest = http.createHttp();
    httpRequest.request(
      `http://10.0.2.2:3000/api/getCorrectAnswer`,
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        extraData: JSON.stringify({
          id: this.puzzle.id,
          difficulty: this.difficulty,
          userAnswerState: this.answerState
        })
      },
      (err: Error, res: http.HttpResponse) => {
        if (err) {
          console.error("请求正确答案失败", JSON.stringify(err));
          promptAction.showToast({ message: '获取正确答案失败', duration: 2000 });
          return;
        }

        if (res.responseCode === 200 && res.result) {
          try {
            const result: VerifyResponse = JSON.parse(res.result as string);

            // 检查是否正确返回了答案数据
            if (!result.correctAnswer) {
              promptAction.showToast({ message: '未获取到正确答案数据', duration: 2000 });
              return;
            }

            const correctAnswer: number[][] = result.correctAnswer;

            // 对比正确答案与用户答案，标记错误单元格
            this.incorrectCells = [];

            for (let row = 0; row < this.puzzle!.size; row++) {
              for (let col = 0; col < this.puzzle!.size; col++) {
                // 用户涂黑了（answerState为1）但正确答案不应该涂黑（correctAnswer为0）
                if (this.answerState[row][col] === 1 && correctAnswer[row][col] === 0) {
                  this.incorrectCells.push({ row, col });
                }
              }
            }

            // 高亮错误单元格
            promptAction.showToast({
              message: `发现${this.incorrectCells.length}处错误`,
              duration: 2000
            });

            // 更新状态以触发 UI 渲染
            this.showHint = true;

          } catch (e) {
            console.error("解析正确答案失败", JSON.stringify(e));
            promptAction.showToast({ message: '解析正确答案失败', duration: 2000 });
          }
        } else {
          promptAction.showToast({ message: '服务器响应失败', duration: 2000 });
        }

        httpRequest.destroy();
      }
    );
  }
  // 预览答案功能
  previewAnswer() {
    if (!this.puzzle) return;
    // 1. 进入预览时，立即开启预览模式（关键！之前漏了这步）
    this.isPreviewMode = true;
    // 发送请求获取正确答案
    let httpRequest = http.createHttp();
    httpRequest.request(
      `http://10.0.2.2:3000/api/getCorrectAnswer`,
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        expectDataType: http.HttpDataType.STRING,
        extraData: JSON.stringify({
          id: this.puzzle.id,
          difficulty: this.difficulty,
          // 补充userAnswerState参数，使用当前答案状态
          // 后端需要这个参数存在，即使我们只是预览答案
          userAnswerState: this.answerState
        })
      },
      (err: Error, res: http.HttpResponse) => {
        if (err) {
          console.error("请求正确答案失败", JSON.stringify(err));
          promptAction.showToast({ message: '获取正确答案失败', duration: 2000 });
          return;
        }

        if (res.responseCode === 200 && res.result) {
          try {
            const result: VerifyResponse = JSON.parse(res.result as string);

            if (!result.correctAnswer) {
              promptAction.showToast({ message: '未获取到正确答案数据', duration: 2000 });
              return;
            }

            const correctAnswer: number[][] = result.correctAnswer;

            // 保存当前状态以便恢复
            const originalUserState: number[][] = [];
            const originalAnswerState: number[][] = [];

            // 深拷贝当前状态
            for (let i = 0; i < this.userState.length; i++) {
              originalUserState.push([...this.userState[i]]);
              originalAnswerState.push([...this.answerState[i]]);
            }

            // 临时显示正确答案
            // 在previewAnswer方法中找到这部分代码并修改
            for (let row = 0; row < this.puzzle!.size; row++) {
              for (let col = 0; col < this.puzzle!.size; col++) {
                // 使用3和4作为预览模式的状态值，区别于原有的-1和-2
                this.userState[row][col] = correctAnswer[row][col] === 1 ? 3 : 4;
                this.answerState[row][col] = correctAnswer[row][col];
              }
            }

            // 触发界面刷新
            this.userState = [...this.userState];
            this.answerState = [...this.answerState];

            promptAction.showToast({
              message: '显示正确答案，5秒后恢复',
              duration: 2000
            });

            // 5秒后恢复原状态
            setTimeout(() => {
              if (this.showAnswer) {
                // 恢复原始状态
                for (let row = 0; row < this.puzzle!.size; row++) {
                  for (let col = 0; col < this.puzzle!.size; col++) {
                    this.userState[row][col] = originalUserState[row][col];
                    this.answerState[row][col] = originalAnswerState[row][col];
                  }
                }

                this.userState = [...this.userState];
                this.answerState = [...this.answerState];
                this.showAnswer = false;
                this.isPreviewMode = false; // 重置预览模式
                promptAction.showToast({
                  message: '已恢复您的答案',
                  duration: 2000
                });
              }
            }, 5000);

          } catch (e) {
            console.error("解析正确答案失败", JSON.stringify(e));
            promptAction.showToast({ message: '解析正确答案失败', duration: 2000 });
          }
        } else {
          promptAction.showToast({ message: '服务器响应失败', duration: 2000 });
        }

        httpRequest.destroy();
      }
    );
  }
  // 重来功能（完全适配 PuzzleData 接口）
  restartLevel(): void {
    // 防错：确保 puzzle 和 size 存在（size 是网格尺寸，如 5 即 5x5）
    if (!this.puzzle || !this.puzzle.size) return;

    const gridSize = this.puzzle.size; // 获取网格尺寸（关键：用于计算行列）
    const newUserState: number[][] = []; // 临时存储新的二维 userState
    const newAnswerState: number[][] = []; // 临时存储新的二维 answerState

    // 1. 遍历每一行（从 0 到 gridSize-1，如 3x3 网格行号 0、1、2）
    for (let row = 0; row < gridSize; row++) {
      const currentUserRow: number[] = []; // 当前行的 userState
      const currentAnswerRow: number[] = []; // 当前行的 answerState

      // 2. 遍历当前行的每一列（从 0 到 gridSize-1）
      for (let col = 0; col < gridSize; col++) {
        // 计算当前格子在一维 grid 中的索引（行优先：行号×尺寸 + 列号）
        // （无需使用 grid 的值，仅用其结构匹配行列）
        const gridIndex = row * gridSize + col;

        // 3. 重置当前格子状态（-1=未涂色，0=未作答，与你原有逻辑一致）
        currentUserRow.push(-1); // 所有格子恢复"未涂色"
        currentAnswerRow.push(0); // 所有格子恢复"未作答"
      }

      // 4. 将当前行添加到二维数组中
      newUserState.push(currentUserRow);
      newAnswerState.push(currentAnswerRow);
    }

    // 5. 赋值给状态变量（触发界面刷新）
    this.userState = newUserState;
    this.answerState = newAnswerState;

    // 6. 重置辅助状态（关闭预览、提示，清空错误记录）
    this.showAnswer = false;
    this.showHint = false;
    this.incorrectCells = [];

    // 7. 用户反馈
    promptAction.showToast({
      message: '已重置关卡，可重新开始',
      duration: 1500
    });
  }


  build() {
    Stack() {
      // 添加背景图片 - 放在最底层
      Image($r('app.media.bg2')) // 使用背景图片
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover) // 覆盖整个屏幕
        .opacity(0.9) // 稍微降低透明度确保内容可读性

      // 主要内容
      Column() {
        // 游戏标题和关卡信息
        Row() {
          Text('像素填空游戏')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .margin({ left: 20 })
            .fontColor('#673B78')
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .margin({ top: 20, bottom: 5 })

        if (this.puzzle) {
          Text(`关卡: ${this.currentLevelId}/${this.totalLevels || '?'}`)
            .fontSize(16)
            .fontColor('#673B78') // 改为深色以适应背景
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 10 })
        }
        // 功能按钮区域
        Row() {
          // 提示按钮
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.hint_icon'))
              .width(30)
              .height(30)
              .objectFit(ImageFit.Contain)
              .backgroundColor('transparent')
          }
          .onClick(() => {
            this.soundManager.play();
            this.showHint = !this.showHint;
            if (this.showHint) {
              this.highlightIncorrectCells();
            } else {
              this.incorrectCells = [];
            }
          })
          .width(50)
          .height(50)
          .backgroundColor(this.showHint ? '#ffcccc' : 'rgba(248, 249, 250, 0.8)') // 添加半透明背景
          .border({ width: 1, color: this.showHint ? '#e74c3c' : '#bdc3c7' })

          // 预览答案按钮
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.preview_icon'))
              .width(30)
              .height(30)
              .objectFit(ImageFit.Contain)
              .backgroundColor('transparent')
          }
          .onClick(() => {
            this.soundManager.play();
            this.showAnswer = !this.showAnswer;
            if (this.showAnswer && this.puzzle) {
              this.previewAnswer();
            } else {
              this.restoreOriginalState();
            }
          })
          .width(50)
          .height(50)
          .backgroundColor(this.showAnswer ? '#d4edda' : 'rgba(248, 249, 250, 0.8)') // 添加半透明背景
          .border({ width: 1, color: this.showAnswer ? '#28a745' : '#bdc3c7' })
          .margin({ left: 10, right: 10 })

          // 重来按钮
          Button({ type: ButtonType.Circle, stateEffect: true }) {
            Image($r('app.media.restart_icon'))
              .width(30)
              .height(30)
              .objectFit(ImageFit.Contain)
              .backgroundColor('transparent')
          }
          .onClick(() => {
            this.soundManager.play();
            this.restartLevel();
          })
          .width(50)
          .height(50)
          .backgroundColor('rgba(248, 249, 250, 0.8)') // 添加半透明背景
          .border({ width: 1, color: '#bdc3c7' })
        }
        .margin({ bottom: 15 })
        .justifyContent(FlexAlign.Center)
        .width('100%')

        // 游戏网格容器
        Column() {
          if (this.puzzle != null) {
            Stack() {
              // 网格边框
              Stack()
                .width(350)
                .height(350)
                .border({ width: 2, color: '#3498db', radius: 8 })
                .backgroundColor('rgba(248, 249, 250, 0.8)') // 添加半透明背景

              // 游戏网格容器
              Stack() {
                Column() {
                  Grid() {
                    ForEach(this.puzzle.grid, (row: number[], rowIndex: number) => {
                      ForEach(row, (originalValue: number, colIndex: number) => {
                        GridItem() {
                          Stack() {
                            if (originalValue >= 0) {
                              Text(originalValue.toString())
                                .fontSize(16) // 减小字体大小以适应更小的网格
                                .fontWeight(FontWeight.Bold)
                                .fontColor(this.userState[rowIndex][colIndex] === -2 ? Color.White : Color.Black)
                                .align(Alignment.Center)
                            }
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
                            // 1. 优先处理提示错误的高亮逻辑
                            this.showHint && this.incorrectCells.some(cell =>
                            cell.row === rowIndex && cell.col === colIndex
                            ) ? '#ffe70f0f' :

                              // 2. 新增：处理预览模式的颜色
                              this.isPreviewMode ?
                                (this.userState[rowIndex][colIndex] === 3
                                  ? '#ff0fe395'  // 预览模式下的正确填充色（浅绿）
                                  : '#ffffffff'  // 预览模式下的空白色（淡绿）
                                ) :

                                // 3. 原有正常状态的颜色逻辑
                                this.userState[rowIndex][colIndex] === -1
                                  ? Color.White
                                  : this.userState[rowIndex][colIndex] === -2
                                  ? '#7f4f92'  // 用户正常涂黑的颜色
                                  : '#ecf0f1'  // 灰色格子
                          )
                        }

                        .border({ width: 1, color: '#bdc3c7' })
                      })
                    })
                  }
                  .columnsTemplate(`repeat(${this.puzzle.size}, 1fr)`)
                  .rowsTemplate(`repeat(${this.puzzle.size}, 1fr)`)
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

                  if (!this.puzzle || this.touchPointCount > 1) {
                    return; // 多指触摸时不处理单元格点击
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
                          this.soundManager.play();

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
                          this.saveUserState();
                        }
                      }
                    }
                  } else if (event.type === TouchType.Up) {
                    // 触摸结束，重置最后触摸的单元格
                    this.lastTouchedCell = null;
                  }
                })
                // 添加手势识别 - 使用parallelGesture而不是GestureGroup
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
          } else {
            Column() {
              LoadingProgress()
                .width(50)
                .height(50)
                .color('#673B78')
                .margin({ bottom: 10 })
              Text('加载中...')
                .fontSize(16)
                .fontColor('#673B78') // 改为深色以适应背景
            }
            .height(350)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
            .width(350)
          }
        }
        .alignItems(HorizontalAlign.Center)
        .justifyContent(FlexAlign.Center)

        // 关卡导航按钮
        Row() {
          Button('上一关')
            .width(110)
            .height(32)
            .fontSize(14)
            .backgroundColor(this.currentLevelId > 1 ? 'rgba(171, 72, 210, 0.8)' : 'rgba(149, 165, 166, 0.8)')
            .backgroundImage(this.currentLevelId > 1 ? $r('app.media.hard') : $r('app.media.ban')) // 添加背景图片
            .fontColor(Color.White)
            .onClick(() => {
              this.prevLevel();
            })
            .backgroundImageSize(ImageSize.Cover) // 覆盖整个按钮
            .backgroundImagePosition(Alignment.Center)
            .borderRadius(6)

          Text(`关卡 ${this.currentLevelId}`)
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor('#673B78')
            .margin({ left: 12, right: 12 })
            .width(80)
            .textAlign(TextAlign.Center)

          Button('下一关')
            .width(110)
            .height(32)
            .fontSize(14)
            .backgroundColor(this.currentLevelId < (this.totalLevels || Infinity) ? 'rgba(171, 72, 210, 0.8)' : 'rgba(149, 165, 166, 0.8)')
            .backgroundImage(this.currentLevelId < (this.totalLevels || Infinity) ? $r('app.media.hard') : $r('app.media.ban')) // 添加背景图片
            .fontColor(Color.White)
            .onClick(() => {
              this.nextLevel();
            })
            .backgroundImageSize(ImageSize.Cover) // 覆盖整个按钮
            .backgroundImagePosition(Alignment.Center)
            .borderRadius(6)
        }
        .margin({ top: 30, bottom: 30 })

        // 提交与返回按钮
        Row() {
          Button(this.isVerifying ? '验 证 中...' : '提 交 答 案')
            .width(150)
            .height(45)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .backgroundColor(this.isVerifying ? 'rgba(149, 165, 166, 0.8)' : 'rgba(231, 76, 60, 0.8)')
            .fontColor(Color.White)
            .borderRadius(8)
            .opacity(this.isVerifying ? 0.7 : 1)
            .onClick(() => {
              if (!this.isVerifying && this.puzzle) {
                this.verifyAnswer();
              }
            })
            .backgroundImage($r('app.media.multi_player_icon')) // 添加背景图片
            .backgroundImageSize(ImageSize.Cover) // 覆盖整个按钮
            .backgroundImagePosition(Alignment.Center)
            .margin({ right: 10 })

          Button('返 回')
            .width(150)
            .height(45)
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .backgroundColor('rgba(52, 152, 219, 0.8)')
            .fontColor(Color.White)
            .borderRadius(8)
            .onClick(() => {
              this.showSaveDialog = true;
            })
            .backgroundImage($r('app.media.single_player_icon')) // 添加背景图片
            .backgroundImageSize(ImageSize.Cover) // 覆盖整个按钮
            .backgroundImagePosition(Alignment.Center)
        }
        .justifyContent(FlexAlign.SpaceEvenly)
        .width('100%')
        .margin({ bottom: 20 })
      }
      .width('100%')
      .height('100%')
      .alignItems(HorizontalAlign.Center)
      .padding(20)

      // 保存进度对话框
      if (this.showSaveDialog) {
        Column() {
          Column() {
            Text('保存游戏进度？')
              .fontSize(20)
              .fontColor('#673B78')
              .fontWeight(FontWeight.Bold)
              .margin({ top: 20, bottom: 10 })

            Text('下次进入游戏时可以继续当前进度')
              .fontSize(14)
              .fontColor('#7f8c8d')
              .margin({ bottom: 20 })

            Row() {
              Button('不 保 存')
                .width(120)
                .height(35)
                .fontSize(16)
                .backgroundColor('#e74c3c')
                .fontColor(Color.White)
                .onClick(() => {
                  this.showSaveDialog = false;
                  this.backToMenu(false);
                })
                .backgroundImage($r('app.media.multi_player_icon')) // 添加背景图片
                .backgroundImageSize(ImageSize.Cover) // 覆盖整个按钮
                .backgroundImagePosition(Alignment.Center)
                .borderRadius(12)

              Button('保 存')
                .width(120)
                .height(35)
                .fontSize(16)
                .backgroundColor('#3498db')
                .fontColor(Color.White)
                .margin({ left: 10 })
                .onClick(() => {
                  this.showSaveDialog = false;
                  this.backToMenu(true);
                })
                .backgroundImage($r('app.media.single_player_icon')) // 添加背景图片
                .backgroundImageSize(ImageSize.Cover) // 覆盖整个按钮
                .backgroundImagePosition(Alignment.Center)
                .borderRadius(12)
            }
            .margin({ bottom: 20 })
          }
          .width('80%')
          .padding(20)
          .backgroundColor(Color.White)
          .borderRadius(12)
          .shadow({ radius: 10, color: '#cccccc', offsetX: 0, offsetY: 2 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.5)')
        .zIndex(20)
      }

      // 验证结果提示
      if (this.showResult && this.verifyResult) {
        Column() {
          Column() {
            if (this.verifyResult.correct) {
              Image($r('app.media.success'))
                .width(60)
                .height(60)
                .margin({ bottom: 10 })
              Text('恭喜！答案正确！')
                .fontSize(20)
                .fontColor('#27ae60')
                .fontWeight(FontWeight.Bold)

              if (this.currentLevelId < (this.totalLevels || Infinity)) {
                Button('下 一 关')
                  .width(120)
                  .height(35)
                  .fontSize(16)
                  .backgroundColor('#3498db')
                  .fontColor(Color.White)
                  .margin({ top: 15 })
                  .onClick(() => {
                    this.saveUserState();
                    this.nextLevel();
                    this.showResult = false;
                  })
                  .backgroundImage($r('app.media.hard')) // 添加背景图片
                  .backgroundImageSize(ImageSize.Cover) // 覆盖整个按钮
                  .borderRadius(12)
              }
            } else {
              Image($r('app.media.error'))
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
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.5)')
        .zIndex(10)
        .scale({ x: this.scaleAnim, y: this.scaleAnim })
        .opacity(this.opacityAnim)
        .onClick(() => {
          this.showResult = false;
        })
      }

      // 获胜窗口
      if (this.showWinDialog) {
        Column() {
          Column() {
            Image($r('app.media.trophy')) // 使用奖杯图标
              .width(80)
              .height(80)
              .margin({ bottom: 20 })

            Text('恭喜你完成了全部关卡！')
              .fontSize(24)
              .fontColor('#673B78')
              .fontWeight(FontWeight.Bold)
              .margin({ bottom: 10 })

            Text(`你已经成功完成了 ${this.totalLevels} 个关卡`)
              .fontSize(16)
              .fontColor('#7f8c8d')
              .margin({ bottom: 30 })

            Button('返回主菜单')
              .width(200)
              .height(45)
              .fontSize(18)
              .fontWeight(FontWeight.Bold)
              .backgroundColor('#dc5cff')
              .fontColor(Color.White)
              .borderRadius(8)
              .onClick(() => {
                this.showWinDialog = false;
                this.backToMenu(false);
              })
              .backgroundImage($r('app.media.hard')) // 添加背景图片
              .backgroundImageSize(ImageSize.Cover) // 覆盖整个按钮
              .backgroundImagePosition(Alignment.Center)
          }
          .padding(30)
          .backgroundColor(Color.White)
          .borderRadius(16)
          .shadow({ radius: 20, color: '#cccccc', offsetX: 0, offsetY: 4 })
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
        .backgroundColor('rgba(0,0,0,0.7)')
        .zIndex(30) // 确保在最上层
      }
    }
    .width('100%')
    .height('100%')
  }
}