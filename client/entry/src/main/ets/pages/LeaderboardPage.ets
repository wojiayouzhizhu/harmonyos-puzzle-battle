import router from '@ohos.router';
import http from '@ohos.net.http';
import promptAction from '@ohos.promptAction';

interface UserScore {
  email: string;
  score: number;
}

@Entry
@Component
struct LeaderboardPage {
  @State leaderboard: UserScore[] = [];
  @State isLoading: boolean = true;
  @State error: string = '';
  @State selectedDifficulty: string = 'easy'; // 默认选择简单难度
  @StorageLink('userEmail') userEmail: string = '';

  aboutToAppear() {
    this.fetchLeaderboard();
  }

  fetchLeaderboard() {
    this.isLoading = true;
    this.error = '';

    let httpRequest = http.createHttp();
    httpRequest.request(
      `http://10.0.2.2:3000/api/leaderboard?difficulty=${this.selectedDifficulty}`,
      {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING
      },
      (err, data) => {
        this.isLoading = false;

        if (!err && data.responseCode === 200) {
          try {
            this.leaderboard = JSON.parse(data.result as string) as UserScore[];
          } catch (e) {
            this.error = '解析数据失败';
            console.error('解析排行榜数据失败', e);
          }
        } else {
          this.error = '获取排行榜失败';
          console.error('获取排行榜失败', JSON.stringify(err));
        }
        httpRequest.destroy();
      }
    );
  }

  // 切换难度
  changeDifficulty(difficulty: string) {
    this.selectedDifficulty = difficulty;
    this.fetchLeaderboard();
  }

  build() {
    // 使用Stack布局实现背景图片和内容分层
    Stack() {
      // 背景图片 - 放在最底层
      Image($r('app.media.bg2'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Cover) // 覆盖整个区域
        .backgroundColor('#FFFDE7') // 备用背景色

      // 左上角返回按钮
      Button('←')
        .width(40)
        .height(40)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor('#673B78')
        .backgroundColor(Color.White)
        .borderRadius(20)
        .shadow({ radius: 2, color: '#000', offsetX: 0, offsetY: 1 })
        .position({ x: 15, y: 15 })
        .zIndex(10) // 确保按钮在最上层
        .onClick(() => {
          router.back();
        })

      // 主内容区域 - 使用Scroll实现滚动
      Scroll() {
        Column() {
          // 标题 - 增加上边距为返回按钮留出空间
          Text('排行榜')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor('#E640FF')
            .textShadow({ radius: 6, color: '#ffffff', offsetX: 1, offsetY: 1 }) // 添加文字阴影增强可读性
            .margin({ top: 60, bottom: 20 }) // 增加上边距
            .width('100%')
            .textAlign(TextAlign.Center)

          // 难度选择器 - 添加背景图片
          Row() {
            // 简单难度按钮
            Button('简 单')
              .width('35%')
              .height(30)
              .fontSize(16)
              .fontColor(this.selectedDifficulty === 'easy' ? Color.White : '#333')
              .fontWeight(FontWeight.Medium)
              .backgroundImage(this.selectedDifficulty === 'easy' ? $r('app.media.easy') : $r('app.media.easy1')) // 简单难度背景图片
              .backgroundImageSize(ImageSize.Cover)
              .backgroundImagePosition(Alignment.Center)
              .backgroundColor(this.selectedDifficulty === 'easy' ? 'rgba(0, 0, 0, 0.7)' : 'rgba(232, 245, 232, 0.7)') // 半透明背景色叠加
              .borderRadius(8)
              .onClick(() => this.changeDifficulty('easy'))
              .margin({ left: -20 })

            // 普通难度按钮
            Button('普 通')
              .width('35%')
              .height(30)
              .fontSize(16)
              .fontColor(this.selectedDifficulty === 'normal' ? Color.White : '#333')
              .fontWeight(FontWeight.Medium)
              .backgroundImage(this.selectedDifficulty === 'normal' ? $r('app.media.normal') : $r('app.media.normal1')) // 普通难度背景图片
              .backgroundImageSize(ImageSize.Cover)
              .backgroundImagePosition(Alignment.Center)
              .backgroundColor(this.selectedDifficulty === 'normal' ? 'rgba(0, 0, 0, 0.7)' : 'rgba(227, 242, 253, 0.7)') // 半透明背景色叠加
              .borderRadius(8)
              .onClick(() => this.changeDifficulty('normal'))
              .margin({ left: 10 })

            // 困难难度按钮
            Button('困 难')
              .width('35%')
              .height(30)
              .fontSize(16)
              .fontColor(this.selectedDifficulty === 'hard' ? Color.White : '#333')
              .fontWeight(FontWeight.Medium)
              .backgroundImage(this.selectedDifficulty === 'hard' ? $r('app.media.hard') : $r('app.media.hard1')) // 困难难度背景图片
              .backgroundImageSize(ImageSize.Cover)
              .backgroundImagePosition(Alignment.Center)
              .backgroundColor(this.selectedDifficulty === 'hard' ? 'rgba(0, 0, 0, 0.7)' : 'rgba(255, 235, 238, 0.7)') // 半透明背景色叠加
              .borderRadius(8)
              .onClick(() => this.changeDifficulty('hard'))
              .margin({ left: 10 })
          }
          .width('90%')
          .margin({ bottom: 20 })

          // 当前难度标题
          //Text(this.getDifficultyTitle())
          //  .fontSize(20)
          //  .fontWeight(FontWeight.Bold)
          //  .fontColor(this.getDifficultyColor())
          //  .margin({ bottom: 15 })

          // 加载中状态
          if (this.isLoading) {
            Column() {
              Text('⏳')
                .fontSize(50)
                .margin({ bottom: 10 })
              Text('加载中...')
                .fontSize(16)
                .fontColor('#7f8c8d')
                .margin({ top: 10 })
            }
            .width('100%')
            .height(300) // 设置固定高度
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          // 错误状态
          else if (this.error) {
            Column() {
              Text('❌')
                .fontSize(50)
                .margin({ bottom: 20 })
              Text(this.error)
                .fontSize(18)
                .fontColor('#e74c3c')
                .margin({ bottom: 20 })
              Button('重试')
                .width(120)
                .height(40)
                .fontSize(16)
                .backgroundColor('#3498db')
                .fontColor(Color.White)
                .borderRadius(8)
                .onClick(() => this.fetchLeaderboard())
            }
            .width('100%')
            .height(300) // 设置固定高度
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          // 空状态
          else if (this.leaderboard.length === 0) {
            Column() {
              Text('📊')
                .fontSize(50)
                .margin({ bottom: 20 })
              Text('暂无排名数据')
                .fontSize(18)
                .fontColor('#7f8c8d')
            }
            .width('100%')
            .height(300) // 设置固定高度
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          // 正常显示排行榜
          else {
            // 显示前10名
            Column() {
              ForEach(this.leaderboard, (item: UserScore, index: number) => {
                Row() {
                  // 排名
                  Column() {
                    if (index === 0) {
                      Text('🥇') // 金牌
                        .fontSize(30)
                    } else if (index === 1) {
                      Text('🥈') // 银牌
                        .fontSize(30)
                    } else if (index === 2) {
                      Text('🥉') // 铜牌
                        .fontSize(30)
                    } else {
                      Text((index + 1).toString())
                        .fontSize(20)
                        .fontWeight(FontWeight.Bold)
                        .fontColor('#7f8c8d')
                    }
                  }
                  .width(50)
                  .justifyContent(FlexAlign.Center)
                  .alignItems(HorizontalAlign.Center)

                  // 用户信息
                  Column() {
                    Text(item.email)
                      .fontSize(16)
                      .fontColor(item.email === this.userEmail ? '#E640FF' : '#2c3e50')
                      .fontWeight(item.email === this.userEmail ? FontWeight.Bold : FontWeight.Normal)
                    Text(`${item.score} 积分`)
                      .fontSize(14)
                      .fontColor('#7f8c8d')
                  }
                  .layoutWeight(1)
                  .margin({ left: 10 })

                  // 当前用户标识
                  if (item.email === this.userEmail) {
                    Text('我')
                      .fontSize(14)
                      .fontColor(Color.White)
                      .backgroundColor('#E640FF')
                      .borderRadius(10)
                      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
                  }
                }
                .padding(15)
                .backgroundColor('#FFFFFF')
                .borderRadius(8)
                .shadow({ radius: 2, color: '#ecf0f1', offsetX: 0, offsetY: 2 })
                .margin({ bottom: 10 })
              })
            }
            .width('100%')
            .margin({ bottom: 20 })
          }
        }
        .width('100%')
        .padding(20)
      }
      .width('100%')
      .height('100%')
      .scrollable(ScrollDirection.Vertical) // 启用垂直滚动
      .scrollBar(BarState.On) // 显示滚动条
      .scrollBarColor('#E640FF') // 滚动条颜色
      .edgeEffect(EdgeEffect.Spring) // 滚动边缘效果
    }
    .width('100%')
    .height('100%')
  }

  // 获取难度标题
  private getDifficultyTitle(): string {
    switch (this.selectedDifficulty) {
      case 'easy':
        return '简单模式排行榜';
      case 'normal':
        return '普通模式排行榜';
      case 'hard':
        return '困难模式排行榜';
      default:
        return '排行榜';
    }
  }

  // 获取难度颜色
  private getDifficultyColor(): string {
    switch (this.selectedDifficulty) {
      case 'easy':
        return '#4CAF50';
      case 'normal':
        return '#2196F3';
      case 'hard':
        return '#F44336';
      default:
        return '#2c3e50';
    }
  }
}