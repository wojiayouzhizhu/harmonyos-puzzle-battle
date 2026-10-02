// components/MusicControl.ts
import { BackgroundMusicManager } from '../utils/BackgroundMusicManager';

@Component
export struct MusicControl {
  @State isPlaying: boolean = BackgroundMusicManager.getInstance().getIsPlaying();
  @State volume: number = BackgroundMusicManager.getInstance().getVolume();
  @State isExpanded: boolean = false; // 控制是否展开显示控制选项

  build() {
    Stack() {
      // 主控制按钮
      Button(this.isPlaying ? '🎵' : '🔇')
        .onClick(() => {
          this.isExpanded = !this.isExpanded;
        })
        .width(40)
        .height(40)
        .backgroundColor(Color.White)
        .borderRadius(20)
        .opacity(0.8)
        .zIndex(10)

      // 展开后的控制面板
      if (this.isExpanded) {
        Column() {
          // 播放/暂停按钮
          Button(this.isPlaying ? '⏸️' : '▶️')
            .onClick(() => {
              if (this.isPlaying) {
                BackgroundMusicManager.getInstance().pause();
              } else {
                BackgroundMusicManager.getInstance().play();
              }
              this.isPlaying = !this.isPlaying;
            })
            .width(40)
            .height(40)
            .margin({ bottom: 10 })

          // 音量滑块
          Slider({
            value: this.volume,
            min: 0,
            max: 1,
            step: 0.1,
            style: SliderStyle.OutSet
          })
            .onChange((value: number) => {
              BackgroundMusicManager.getInstance().setVolume(value);
              this.volume = value;
            })
            .width(100)
            .margin({ bottom: 10 })

          // 关闭按钮
          Button('✕')
            .onClick(() => {
              this.isExpanded = false;
            })
            .width(30)
            .height(30)
        }
        .padding(10)
        .backgroundColor('rgba(255,255,255,0.9)')
        .borderRadius(8)
        .position({ x: 50, y: 0 }) // 在主按钮右侧显示
        .zIndex(5)
      }
    }
    .position({ x: 0, y: 0 })
    .margin({ top: 10, right: 10 })
    .align(Alignment.TopEnd)
    .zIndex(100)
  }
}