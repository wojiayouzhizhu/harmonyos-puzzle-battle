// utils/BackgroundMusicManager.ts
import { media } from '@kit.MediaKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { common } from '@kit.AbilityKit';

export class BackgroundMusicManager {
  private static instance: BackgroundMusicManager;
  private avPlayer: media.AVPlayer | null = null;
  private isPrepared: boolean = false;
  private isPlaying: boolean = false;
  private volume: number = 0.5; // 默认音量50%

  // 私有构造函数，确保单例
  private constructor() {}

  // 获取单例实例
  public static getInstance(): BackgroundMusicManager {
    if (!BackgroundMusicManager.instance) {
      BackgroundMusicManager.instance = new BackgroundMusicManager();
    }
    return BackgroundMusicManager.instance;
  }

  // 修改初始化方法以接收上下文参数
  async init(context: common.UIAbilityContext) {
    try {
      const resourceMgr = context.resourceManager;

      // 获取背景音乐文件的路径
      const rawfilePath = 'background_music.mp3';
      const fdInfo = await resourceMgr.getRawFd(rawfilePath);

      this.avPlayer = await media.createAVPlayer();
      this.setAVPlayerCallback();

      // 使用fd方式设置音频源
      this.avPlayer.fdSrc = {
        fd: fdInfo.fd,
        offset: fdInfo.offset,
        length: fdInfo.length
      };

      // 设置音量
      this.setVolume(this.volume);
    } catch (error) {
      console.error('初始化背景音乐失败:', JSON.stringify(error));
    }
  }

  // 设置AVPlayer回调
  setAVPlayerCallback() {
    if (this.avPlayer) {
      this.avPlayer.on('stateChange', async (state: string) => {
        switch (state) {
          case 'initialized':
            this.avPlayer?.prepare();
            break;
          case 'prepared':
            this.isPrepared = true;
            console.info('背景音乐准备完成');
            // 自动开始播放
            this.play();
            break;
          case 'completed':
            // 循环播放：播放完成后重新开始
            this.avPlayer?.seek(0);
            this.avPlayer?.play();
            break;
        }
      });

      this.avPlayer.on('error', (err: BusinessError) => {
        console.error('背景音乐播放错误:', JSON.stringify(err));
      });
    }
  }

  // 播放音乐
  play() {
    if (this.avPlayer && this.isPrepared) {
      try {
        this.avPlayer.play();
        this.isPlaying = true;
      } catch (error) {
        console.error('播放背景音乐失败:', JSON.stringify(error));
      }
    }
  }

  // 暂停音乐
  pause() {
    if (this.avPlayer && this.isPrepared && this.isPlaying) {
      try {
        this.avPlayer.pause();
        this.isPlaying = false;
      } catch (error) {
        console.error('暂停背景音乐失败:', JSON.stringify(error));
      }
    }
  }

  // 停止音乐
  stop() {
    if (this.avPlayer && this.isPrepared) {
      try {
        this.avPlayer.stop();
        this.isPlaying = false;
      } catch (error) {
        console.error('停止背景音乐失败:', JSON.stringify(error));
      }
    }
  }

  // 设置音量 (0.0 到 1.0)
  setVolume(level: number) {
    this.volume = Math.max(0, Math.min(1, level)); // 确保在0-1范围内
    if (this.avPlayer && this.isPrepared) {
      try {
        // 使用 setVolume() 方法而不是直接赋值
        this.avPlayer.setVolume(this.volume);
      } catch (error) {
        console.error('设置音量失败:', JSON.stringify(error));
      }
    }
  }

  // 获取当前音量
  getVolume(): number {
    return this.volume;
  }

  // 获取播放状态
  getIsPlaying(): boolean {
    return this.isPlaying;
  }

  // 释放资源
  release() {
    if (this.avPlayer) {
      this.avPlayer.release();
      this.avPlayer = null;
      this.isPrepared = false;
      this.isPlaying = false;
    }
  }
}