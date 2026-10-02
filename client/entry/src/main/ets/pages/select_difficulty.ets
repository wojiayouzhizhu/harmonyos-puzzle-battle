import router from '@ohos.router';
import { MusicControl } from 'utils/MusicControl'; // 根据实际路径调整
import { BackgroundMusicManager } from 'utils/BackgroundMusicManager'; // 根据实际路径调整

@Entry
@Component
struct SelectDifficulty {
  @State gameMode: string = 'single'; // 默认是单人模式

  aboutToAppear() {
    // 获取从主页传递过来的游戏模式参数
    const params = router.getParams() as Record<string, string>;
    if (params && params.mode) {
      this.gameMode = params.mode;
    }

    // 确保页面显示时音乐继续播放
    if (!BackgroundMusicManager.getInstance().getIsPlaying()) {
      BackgroundMusicManager.getInstance().play();
    }
  }

  build() {
    Stack() {
      // 添加背景图片
      Image($r('app.media.bg2'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover) // 覆盖整个屏幕
        .opacity(0.9) // 稍微降低透明度，确保内容可读性

      Column() {
        // 顶部标题区域 - 根据模式显示不同标题
        Column() {
          Text(this.gameMode === 'multi' ? '选择双人对战难度' : '选择游戏难度')
            .fontSize(28)
            .fontColor('#673B78')
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 8, top: 40})

          Text(this.gameMode === 'multi' ? '同一局域网下的玩家需选择相同难度' : '选择适合您的挑战级别')
            .fontSize(16)
            .fontColor('#666')
            .margin({ bottom: 40 })
        }
        .width('100%')
        .padding({ top: 30 })
        .alignItems(HorizontalAlign.Center)

        // 难度选择卡片区域
        Column() {
          // 简单难度卡片
          Stack() {
            // 背景图片
            Image($r('app.media.easy'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(16)

            // 半透明遮罩层，提高文字可读性
            Column()
              .width('100%')
              .height('100%')
              //.backgroundColor('rgba(76, 175, 80, 0.6)') // 绿色半透明遮罩
              .borderRadius(16)

            // 文字内容
            Column() {
              Text('简单')
                .fontSize(22)
                .fontColor('#fff')
                .fontWeight(FontWeight.Bold)
                .textShadow({ radius: 3, color: '#000', offsetX: 1, offsetY: 1 })
                .margin({ bottom: 5 })
              Text('适合初学者')
                .fontSize(14)
                .fontColor('#fff')
                .textShadow({ radius: 2, color: '#000', offsetX: 1, offsetY: 1 })
            }
            .padding(20)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width('90%')
          .height(100)
          .borderRadius(16)
          .margin({ bottom: 15 })
          .onClick(() => {
            if (this.gameMode === 'multi') {
              router.push({ url: 'pages/2p_game', params: { difficulty: 'easy' } })
            } else {
              router.push({ url: 'pages/game', params: { difficulty: 'easy' } })
            }
          })

          // 普通难度卡片
          Stack() {
            // 背景图片
            Image($r('app.media.normal'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(16)

            // 半透明遮罩层，提高文字可读性
            Column()
              .width('100%')
              .height('100%')
              //.backgroundColor('rgba(255, 152, 0, 0.6)') // 橙色半透明遮罩
              .borderRadius(16)

            // 文字内容
            Column() {
              Text('普通')
                .fontSize(22)
                .fontColor('#fff')
                .fontWeight(FontWeight.Bold)
                .textShadow({ radius: 3, color: '#000', offsetX: 1, offsetY: 1 })
                .margin({ bottom: 5 })
              Text('有一定挑战')
                .fontSize(14)
                .fontColor('#fff')
                .textShadow({ radius: 2, color: '#000', offsetX: 1, offsetY: 1 })
            }
            .padding(20)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width('90%')
          .height(100)
          .borderRadius(16)
          .margin({ bottom: 15 })
          .onClick(() => {
            if (this.gameMode === 'multi') {
              router.push({ url: 'pages/2p_game', params: { difficulty: 'medium' } })
            } else {
              router.push({ url: 'pages/game', params: { difficulty: 'medium' } })
            }
          })

          // 困难难度卡片
          Stack() {
            // 背景图片
            Image($r('app.media.hard'))
              .width('100%')
              .height('100%')
              .objectFit(ImageFit.Cover)
              .borderRadius(16)

            // 半透明遮罩层，提高文字可读性
            Column()
              .width('100%')
              .height('100%')
              //.backgroundColor('rgba(244, 67, 54, 0.6)') // 红色半透明遮罩
              .borderRadius(16)

            // 文字内容
            Column() {
              Text('困难')
                .fontSize(22)
                .fontColor('#fff')
                .fontWeight(FontWeight.Bold)
                .textShadow({ radius: 3, color: '#000', offsetX: 1, offsetY: 1 })
                .margin({ bottom: 5 })
              Text('高手专属')
                .fontSize(14)
                .fontColor('#fff')
                .textShadow({ radius: 2, color: '#000', offsetX: 1, offsetY: 1 })
            }
            .padding(20)
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width('90%')
          .height(100)
          .borderRadius(16)
          .margin({ bottom: 25 })
          .onClick(() => {
            if (this.gameMode === 'multi') {
              router.push({ url: 'pages/2p_game', params: { difficulty: 'hard' } })
            } else {
              router.push({ url: 'pages/game', params: { difficulty: 'hard' } })
            }
          })
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)

        // 游戏说明区域 - 根据模式显示不同说明
        Column() {
          Text(this.gameMode === 'multi' ? '双人对战规则' : '游戏规则')
            .fontSize(18)
            .fontColor('#673B78')
            .fontWeight(FontWeight.Medium)
            .margin({ bottom: 12 })

          if (this.gameMode === 'multi') {
            Text('双人对战模式下，您需要与同一局域网下的另一位玩家进行对战。双方需要选择相同的难度级别，系统将自动匹配对手。对战过程中，您需要比对手更快更准确地完成谜题，以获得胜利。')
              .fontSize(15)
              .fontColor('#673B78')
              .lineHeight(22)
              .textAlign(TextAlign.Start)
          } else {
            Text('每道谜题都是由一个网格构成，该网格中的一些位置上放置了提示数字。游戏的目的是涂画提示数字周围的方格，使得被涂画方格的数量（包含提示数字所在方格）与其对应的提示数字数值相同，从而绘画出一幅藏在网格背后的像素画。')
              .fontSize(15)
              .fontColor('#673B78')
              .lineHeight(22)
              .textAlign(TextAlign.Start)
          }
        }
        .width('90%')
        .padding(20)
        .backgroundColor('rgba(249, 249, 249, 0.8)') // 添加透明度
        .borderRadius(12)
        .margin({ bottom: 20, top: -30})
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.SpaceBetween)

      // 左上角返回按钮
      Button('←')
        .width(50)
        .height(50)
        .fontSize(24)
        .fontColor('#673B78')
        .backgroundColor('rgba(255, 255, 255, 0.7)')
        .borderRadius(25)
        .position({ x: 15, y: 15 })
        .onClick(() => {
          router.push({ url: 'pages/Index' })
        })

      // 音乐控制组件 - 会定位在右上角
      MusicControl()
    }
    .width('100%')
    .height('100%')
  }
}