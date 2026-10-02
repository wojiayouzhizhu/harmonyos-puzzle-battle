import router from '@ohos.router';
import promptAction from '@ohos.promptAction';

@Entry
@Component
struct TutorialPage {
  // 使用VideoController
  private controller: VideoController = new VideoController();
  @State isPlaying: boolean = false;
  @State currentPosition: number = 0;
  @State duration: number = 0;
  @State showControls: boolean = true;
  @State isFullscreen: boolean = false;
  private controlsTimeout: number = 0;

  // 使用Resource类型
  private videoSrc: Resource = $rawfile('tutorial.mp4');
  // 可选：预览图
  private previewUri: Resource = $r('app.media.video_preview');

  aboutToAppear() {
    // 设置视频状态变化监听
  }

  // 播放/暂停视频
  togglePlayPause() {
    if (this.isPlaying) {
      this.controller.pause();
      this.isPlaying = false;
    } else {
      this.controller.start();
      this.isPlaying = true;
    }

    // 显示控制条并设置隐藏定时器
    this.showControls = true;
    this.resetControlsTimer();
  }

  // 停止播放
  stopPlayback() {
    this.controller.stop();
    this.isPlaying = false;
    this.currentPosition = 0;
  }

  // 重置视频
  resetPlayback() {
    this.controller.reset();
    this.isPlaying = false;
    this.currentPosition = 0;
  }

  // 跳转到指定位置
  seekTo(position: number) {
    // 使用setCurrentTime方法跳转到指定位置
    this.controller.setCurrentTime(position);
    this.currentPosition = position;
  }

  // 切换全屏模式
  toggleFullscreen() {
    if (this.isFullscreen) {
      this.controller.exitFullscreen();
    } else {
      this.controller.requestFullscreen(true);
    }
    this.isFullscreen = !this.isFullscreen;
  }

  // 重置控制条隐藏定时器
  resetControlsTimer() {
    if (this.controlsTimeout) {
      clearTimeout(this.controlsTimeout);
    }

    this.controlsTimeout = setTimeout(() => {
      this.showControls = false;
    }, 3000);
  }

  // 格式化时间显示 (秒 -> 分:秒)
  formatTime(seconds: number): string {
    const mins = Math.floor(seconds / 60);
    const secs = Math.floor(seconds % 60);
    return `${mins}:${secs < 10 ? '0' : ''}${secs}`;
  }

  aboutToDisappear() {
    // 清理资源
    if (this.controlsTimeout) {
      clearTimeout(this.controlsTimeout);
    }

    // 停止视频播放
    this.controller.stop();
  }

  build() {
    Column() {
      // 顶部导航栏
      Row() {
        Button('←')
          .fontSize(24)
          .fontColor('#673B78')
          .backgroundColor(Color.Transparent)
          .onClick(() => {
            router.back();
          })

        Text('新手教程')
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#673B78')
          .margin({ left: 10 })
          .layoutWeight(1)

        // 全屏按钮
        //Button(this.isFullscreen ? '⛌' : '⛶')
        //  .fontSize(20)
        //  .fontColor('#007AFF')
        //  .backgroundColor(Color.Transparent)
        //  .onClick(() => this.toggleFullscreen())
      }
      .width('100%')
      .padding(15)
      .backgroundColor('#F5F5F5')

      // 视频播放区域
      Stack() {
        Column(){
          Blank()
            .height(10) // 调整这个值来控制间距大小

        // 视频播放器 - 使用Video组件
        Video({
          src: this.videoSrc,
          previewUri: this.previewUri,
          controller: this.controller
        })
          .width('100%')
          .height(300)
          .objectFit(ImageFit.Contain)
          .autoPlay(false)
          .onStart(() => {
            this.isPlaying = true;
            console.log('Video started');
          })
          .onPause(() => {
            this.isPlaying = false;
            console.log('Video paused');
          })
          .onFinish(() => {
            this.isPlaying = false;
            console.log('Video finished');
          })
          .onPrepared((event) => {
            this.duration = event.duration;
            console.log('Video prepared, duration: ' + this.duration);
          })
          .onSeeking((event) => {
            this.currentPosition = event.time;
            console.log('Video seeking to: ' + event.time);
          })
          .onUpdate((event) => {
            this.currentPosition = event.time;
            console.log('Video time update: ' + event.time);
          })
          .onError(() => {
            console.error('Video playback error');
            promptAction.showToast({ message: '视频播放失败', duration: 2000 });
          })
          .onClick(() => {
            this.showControls = !this.showControls;
            if (this.showControls) {
              this.resetControlsTimer();
            }
          })

        // 视频控制层
        if (this.showControls) {
          Column() {
            Blank()
              .height(10) // 调整这个值来控制间距大小

            // 顶部控制栏
            Row() {
              // 空白的顶部控制栏，用于平衡布局
            }
            .width('100%')
            .height(40)
            .backgroundColor('rgba(0,0,0,0.3)')

            // 中间播放/暂停按钮
            Row() {
              if (this.isPlaying) {
                Image($r('app.media.pause_icon1')) // 暂停图标
                  .width(40)
                  .height(40)
                  //.backgroundColor('rgba(0,0,0,0.5)')
                  .borderRadius(20)
                  .onClick(() => this.togglePlayPause())
              } else {
                Image($r('app.media.play_icon1')) // 播放图标
                  .width(40)
                  .height(40)
                  //.backgroundColor('rgba(0,0,0,0.5)')
                  .borderRadius(20)
                  .onClick(() => this.togglePlayPause())
              }
            }
            .width('100%')
            .height(180)
            .justifyContent(FlexAlign.Center)

            // 底部控制栏
            Column() {
              // 进度条
              Row() {
                Text(this.formatTime(this.currentPosition))
                  .fontSize(12)
                  .fontColor(Color.White)
                  .width(40)

                Slider({
                  value: this.currentPosition,
                  min: 0,
                  max: this.duration > 0 ? this.duration : 100,
                  step: 1,
                  style: SliderStyle.OutSet
                })
                  .blockColor('#de85ff')
                  .trackColor('#E5E5E5')
                  .selectedColor('#de85ff')
                  .showSteps(false)
                  .showTips(true)
                  .onChange((value: number) => {
                    this.seekTo(value);
                  })
                  .layoutWeight(1)

                Text(this.formatTime(this.duration))
                  .fontSize(12)
                  .fontColor(Color.White)
                  .width(40)
                  .textAlign(TextAlign.End)
              }
              .width('100%')
              .padding({ left: 10, right: 10 })

              // 添加控制按钮
              Row() {
                Image($r('app.media.rewind_icon1')) // 后退图标
                  .width(30)
                  .height(30)
                  //.backgroundColor('rgba(0,0,0,0.5)')
                  .onClick(() => {
                    // 后退10秒
                    let newTime = Math.max(0, this.currentPosition - 10);
                    this.seekTo(newTime);
                  })

                Image($r('app.media.forward_icon1')) // 前进图标
                  .width(30)
                  .height(30)
                  //.backgroundColor('rgba(0,0,0,0.5)')
                  .margin({ left: 10, right: 10 })
                  .onClick(() => {
                    // 前进10秒
                    let newTime = Math.min(this.duration, this.currentPosition + 10);
                    this.seekTo(newTime);
                  })

                Image($r('app.media.stop_icon1')) // 停止图标
                  .width(30)
                  .height(30)
                  //.backgroundColor('rgba(0,0,0,0.5)')
                  .onClick(() => this.stopPlayback())

                Image($r('app.media.reset_icon1')) // 重置图标
                  .width(30)
                  .height(30)
                  //.backgroundColor('rgba(0,0,0,0.5)')
                  .margin({ left: 10 })
                  .onClick(() => this.resetPlayback())
              }
              .width('100%')
              .justifyContent(FlexAlign.Center)
              .margin({ top: -10 })
            }
            .width('100%')
            .padding(10)
            .backgroundColor('rgba(0,0,0,0.3)')
          }
          .width('100%')
          .height('100%')
          .position({ x: 0, y: 0 })
        }
      }
      }
      .width('100%')
      .height(300)
      .margin({ bottom: 20 })

      // 教程说明区域
      Scroll() {
        Column() {
          Text('游戏教程指南')
            .fontSize(24)
            .fontWeight(FontWeight.Bold)
            .fontColor('#673B78')
            .margin({ bottom: 15 })
            .width('100%')
            .textAlign(TextAlign.Center)

          Text('欢迎来到像素填空游戏！本教程将帮助您快速掌握游戏玩法。')
            .fontSize(16)
            .fontColor('#673B78')
            .margin({ bottom: 20 })
            .width('100%')

          Divider()
            .margin({ bottom: 20 })

          Text('🎯 游戏目标')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#673B78')
            .margin({ bottom: 10 })
            .width('100%')

          Text('根据每行和每列的数字提示，正确填充像素格子，完成一幅像素画。')
            .fontSize(16)
            .fontColor('#673B78')
            .margin({ bottom: 20 })
            .width('100%')

          Text('🕹️ 基本操作')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#673B78')
            .margin({ bottom: 10 })
            .width('100%')

          Text('• 点击格子可在三种状态间切换：空白(白色)、填充(黑色)、标记(灰色带X)\n' +
            '• 数字表示连续填充的格子数量\n' +
            '• 多个数字表示有多组连续填充的格子，组间至少有一个空格')
            .fontSize(16)
            .fontColor('#673B78')
            .margin({ bottom: 20 })
            .width('100%')

          Text('💡 游戏技巧')
            .fontSize(20)
            .fontWeight(FontWeight.Bold)
            .fontColor('#673B78')
            .margin({ bottom: 10 })
            .width('100%')

          Text('• 从最大的数字开始推理\n' +
            '• 注意行和列的数字关联\n' +
            '• 使用标记功能排除不可能的位置\n' +
            '• 完成一行或一列后，可以简化其他行和列的推理')
            .fontSize(16)
            .fontColor('#673B78')
            .margin({ bottom: 20 })
            .width('100%')
        }
        .padding(20)
        .backgroundColor('rgba(255, 255, 255, 0.85)') // 添加半透明白色背景，提高文字可读性
        .borderRadius(12) // 添加圆角
        .margin(10) // 添加外边距
      }
      .layoutWeight(1)
      .width('100%')
    }
    .width('100%')
    .height('100%')
    .backgroundImage($r('app.media.bg2')) // 添加背景图片:cite[1]:cite[6]
    .backgroundImageSize(ImageSize.Cover) // 背景图片覆盖整个区域:cite[1]:cite[2]
    .backgroundImagePosition(Alignment.Center) // 图片居中显示:cite[1]:cite[4]
    .onClick(() => {
      // 点击空白区域隐藏控制条
      this.showControls = false;
    })
  }
}