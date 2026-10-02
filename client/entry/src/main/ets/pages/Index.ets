import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import http from '@ohos.net.http';
import { MusicControl } from 'utils/MusicControl'; // 根据实际路径调整
import { BackgroundMusicManager } from 'utils/BackgroundMusicManager'; // 根据实际路径调整
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
interface LeaderboardItem {
  email: string;
  score: number;
}

interface UserScoreResponse {
  email: string;
  easy_score: number;
  normal_score: number;
  hard_score: number;
}

@Entry
@Component
struct GameLayout {
  @State currentTab: number = 0; // 初始选中首页（索引0）
  @StorageLink('token') token: string = '';      // 响应式获取 token
  @StorageLink('userEmail') userEmail: string = ''; // 响应式获取用户邮箱
  @StorageLink('userScore') userScore: number = 0; // 响应式获取用户积分
  @StorageLink('userEasyScore') userEasyScore: number = 0; // 简单模式积分
  @StorageLink('userNormalScore') userNormalScore: number = 0; // 普通模式积分
  @StorageLink('userHardScore') userHardScore: number = 0; // 困难模式积分

  // 在GameLayout组件中添加状态
  @State leaderboardData: LeaderboardItem[] = [];
  @State isLeaderboardLoading: boolean = false;
  @State selectedDifficulty: string = 'normal'; // 默认显示普通模式排行榜
  @State avatarUrl: string = ''; // 新增：存储用户头像URL
  // 首先在组件中添加一个状态来跟踪头像加载是否失败
  @State avatarLoadFailed: boolean = false;


  aboutToAppear() {
    const context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(context, { name: 'user_data' }).then(async (prefs) => {
      const token = await prefs.get('token', '');
      const userEmail = await prefs.get('userEmail', '');
      const userScore = await prefs.get('userScore', 0);
      const userEasyScore = await prefs.get('userEasyScore', 0);
      const userNormalScore = await prefs.get('userNormalScore', 0);
      const userHardScore = await prefs.get('userHardScore', 0);

      AppStorage.set('token', token);
      AppStorage.set('userEmail', userEmail);
      AppStorage.set('userScore', userScore);
      AppStorage.set('userEasyScore', userEasyScore);
      AppStorage.set('userNormalScore', userNormalScore);
      AppStorage.set('userHardScore', userHardScore);

      if (token && userEmail) {
        this.fetchAvatar(userEmail as string);
        this.fetchUserScores(); // 获取最新的用户积分
      }

      // 确保页面显示时音乐继续播放
      if (!BackgroundMusicManager.getInstance().getIsPlaying()) {
        BackgroundMusicManager.getInstance().play();
      }
    });
  }

  // 监听StorageLink变化
  onUserEmailChange() {
    if (this.token && this.userEmail) {
      this.fetchAvatar(this.userEmail);
    } else {
      this.avatarUrl = ''; // 退出登录时清空头像
    }
  }

  // 获取头像的方法
  async fetchAvatar(email: string): Promise<void> {
    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(
        `http://10.0.2.2:3000/api/avatar?email=${encodeURIComponent(email)}`,
        {
          method: http.RequestMethod.GET,
        }
      );

      if (response.responseCode === 200) {
        // 使用类型安全的JSON解析
        interface AvatarResponse {
          avatarUrl: string;
        }

        const data: AvatarResponse = JSON.parse(response.result as string) as AvatarResponse;
        this.avatarUrl = data.avatarUrl;
      }
    } catch (error) {
      // 使用类型安全的错误处理
      if (error instanceof Error) {
        console.error('获取头像失败', error.message);
      } else {
        console.error('获取头像失败', '未知错误');
      }
      this.avatarUrl = ''; // 失败时使用默认头像
    }
  }

  // 在GameLayout组件中添加方法
  async fetchUserScores() {
    if (!this.token) return;

    try {
      const httpRequest = http.createHttp();
      const response = await httpRequest.request(
        'http://10.0.2.2:3000/api/user-score',
        {
          method: http.RequestMethod.GET,
          header: {
            'Authorization': `Bearer ${this.token}`
          }
        }
      );

      if (response.responseCode === 200) {
        // 使用类型断言
        const data: UserScoreResponse = JSON.parse(response.result as string) as UserScoreResponse;

        // 更新AppStorage中的积分值
        AppStorage.set('userEasyScore', data.easy_score || 0);
        AppStorage.set('userNormalScore', data.normal_score || 0);
        AppStorage.set('userHardScore', data.hard_score || 0);

        // 更新本地preferences
        const context = getContext(this) as common.UIAbilityContext;
        const prefs = await preferences.getPreferences(context, { name: 'user_data' });
        await prefs.put('userEasyScore', data.easy_score || 0);
        await prefs.put('userNormalScore', data.normal_score || 0);
        await prefs.put('userHardScore', data.hard_score || 0);
        await prefs.flush();
      }
    } catch (error) {
      console.error('获取用户积分失败:', JSON.stringify(error));
    }
  }

  // 添加获取排行榜数据的方法
  fetchLeaderboardPreview() {
    this.isLeaderboardLoading = true;
    let httpRequest = http.createHttp();
    httpRequest.request(
      `http://10.0.2.2:3000/api/leaderboard?difficulty=${this.selectedDifficulty}`,
      {
        method: http.RequestMethod.GET,
        expectDataType: http.HttpDataType.STRING
      },
      (err, data) => {
        this.isLeaderboardLoading = false;
        if (!err && data.responseCode === 200) {
          try {
            this.leaderboardData = JSON.parse(data.result as string);
          } catch (e) {
            console.error('解析排行榜数据失败', e);
          }
        } else {
          console.error('获取排行榜失败', JSON.stringify(err));
        }
        httpRequest.destroy();
      }
    );
  }

  // 修改switchTab方法，在切换到排行榜标签时获取数据
  switchTab(index: number) {
    this.currentTab = index;
    // 如果切换到排行榜标签，则获取排行榜数据
    if (index === 1 && this.leaderboardData.length === 0) {
      this.fetchLeaderboardPreview();
    }
  }

  // 退出登录
  logout() {
    AppStorage.set('token', '');
    AppStorage.set('userEmail', '');
    AppStorage.set('userScore', 0);
    AppStorage.set('userEasyScore', 0);
    AppStorage.set('userNormalScore', 0);
    AppStorage.set('userHardScore', 0);
    this.avatarUrl = ''; // 清空头像

    // 清除本地preferences中的积分数据
    const context = getContext(this) as common.UIAbilityContext;
    preferences.getPreferences(context, { name: 'user_data' }).then(async (prefs) => {
      await prefs.put('userEasyScore', 0);
      await prefs.put('userNormalScore', 0);
      await prefs.put('userHardScore', 0);
      await prefs.flush();
    });

    promptAction.showToast({ message: '已退出登录', duration: 2000 });
  }

  // 顶部用户信息 - 修改头像显示部分
  @Builder userInfoPanel() {
    Row() {
      // 头像部分 - 修改为动态显示
      // 然后在头像显示部分使用条件渲染
      if (this.token) {
        if (this.avatarUrl && !this.avatarLoadFailed) {
          Image(this.avatarUrl)
            .width(60).height(60)
            .borderRadius(30)
            .objectFit(ImageFit.Cover)
            .margin({ right: 15 })
            .border({ width: 2, color: '#CEA8D0' })
            .shadow({ radius: 8, color: '#FFE3D8' })
            .onError(() => {
              // 图片加载失败时设置状态
              this.avatarLoadFailed = true;
            })
        } else {
          // 加载失败或没有头像时显示默认头像
          Image($r('app.media.guest_avatar'))
            .width(60).height(60)
            .borderRadius(30)
            .objectFit(ImageFit.Cover)
            .margin({ right: 15 })
            .border({ width: 2, color: '#E640FF' })
            .shadow({ radius: 8, color: '#FFE3D8' })
        }
      } else {
        Image($r('app.media.default_avatar'))
          .width(60).height(60)
          .borderRadius(30)
          .objectFit(ImageFit.Cover)
          .margin({ right: 15 })
          .shadow({ radius: 6, color: '#ccc' })
      }

      if (this.token) {
        Column() {
          Text(this.userEmail || '用户邮箱')
            .fontSize(22)
            .fontColor('#B67ACD')
            .fontWeight(FontWeight.Bold)
          // Text(`总积分: ${this.userScore}`)
          //   .fontSize(16)
          //   .fontColor('#4CAF50')
          //Text('退出登录')
          //  .fontSize(18)
          //  .fontColor('#B43757')
           // .onClick(() => this.logout())
        }
      } else {
        Text('请先登录')
          .fontSize(18)
          .fontColor('#B67ACD')
          .fontWeight(FontWeight.Medium)
          .onClick(() => router.pushUrl({ url: 'pages/LoginPage' }))
      }
    }
    .padding(20)
    .width('100%')
    .backgroundColor('#90B2D3F3')
    .borderRadius(12)
    .margin({ bottom: 15 })
    .onClick(() => {
      // 点击用户信息区域时，如果已登录但头像加载失败，可以重新获取
      if (this.token && this.userEmail && !this.avatarUrl) {
        this.fetchAvatar(this.userEmail);
      }
    })
  }

  // 游戏主区域
  @Builder gameContainer() {
      Column() {
        Image($r('app.media.index_img'))
          .width('95%')
          .aspectRatio(1)
          .borderRadius(20)
          //边框
          //.shadow({ radius: 10, color: '#FFCC80', })
          .margin({top: -40, bottom: -10})

        // 添加间距 - 方法一：使用 Blank 组件
        //Blank()
        //  .height(10) // 调整这个值来控制间距大小

        // 修改教程视频按钮 - 使用背景图片并自适应
        Button('教 程 视 频')
          .width('60%')
          .height(65)
          .fontSize(20)
          .fontColor('#fff')
          .fontWeight(FontWeight.Bolder)
          .backgroundImage($r('app.media.tutorial_icon'))
          .backgroundImageSize(ImageSize.Cover)
          .backgroundImagePosition(Alignment.Center)
          .borderRadius(16)
          .shadow({ radius: 6, color: '#828282' })
          .margin({ top: 10 })
          .onClick(() => {
            router.pushUrl({ url: 'pages/TutorialPage' });
          })

        // 修改单人模式按钮 - 使用背景图片并自适应
        Button('单 人 模 式')
          .width('60%')
          .height(65)
          .fontSize(20)
          .fontColor('#fff')
          .fontWeight(FontWeight.Bolder)
          .backgroundImage($r('app.media.single_player_icon'))
          .backgroundImageSize(ImageSize.Cover)
          .backgroundImagePosition(Alignment.Center)
          .borderRadius(16)
          .shadow({ radius: 6, color: '#828282' })
          .margin({ top: 20 })
          .onClick(() => {
            if (!this.token) {
              promptAction.showToast({ message: '请先登录', duration: 2000 });
              router.pushUrl({ url: 'pages/LoginPage' });
              return;
            }
            router.push({ url: 'pages/select_difficulty', params: { mode: 'single' } })
          })

        // 修改双人模式按钮 - 使用背景图片并自适应
        Button('双 人 模 式')
          .width('60%')
          .height(65)
          .fontSize(20)
          .fontColor('#fff')
          .fontWeight(FontWeight.Bolder)
          .backgroundImage($r('app.media.multi_player_icon'))
          .backgroundImageSize(ImageSize.Cover)
          .backgroundImagePosition(Alignment.Center)
          .borderRadius(16)
          .shadow({ radius: 6, color: '#828282' })
          .margin({ top: 15 })
          .onClick(() => {
            if (!this.token) {
              promptAction.showToast({ message: '请先登录', duration: 2000 });
              router.pushUrl({ url: 'pages/LoginPage' });
              return;
            }
            router.push({ url: 'pages/select_difficulty', params: { mode: 'multi' } })
          })
      }
      .width('100%')
      .height('70%')
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
  }

  // 排行榜组件
  @Builder leaderboardContainer() {
    Column() {
      // 使用Stack布局将文字叠加在背景图片上
      Stack() {
        // 背景图片
        //Image($r('app.media.bg_rank'))
        //  .width('80%')
        //  .height(80) // 根据图片和文字大小调整高度
        //  .objectFit(ImageFit.Cover) // 覆盖整个区域
        //  .borderRadius(8) // 添加圆角

        // 文字内容 - 居中显示在图片上
        Text('排行榜预览 ')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFA045') // 使用白色文字确保在背景上可见
          .textShadow({ radius: 6, color: '#ffffff', offsetX: 1, offsetY: 1 }) // 添加文字阴影增强可读性
          .width('100%')
          .textAlign(TextAlign.Center)
          .position({ y: -16, x: 0}) // 垂直居中
      }
      .width('100%')
      .height(8) // 与背景图片高度一致
      .margin({ top: 20, bottom: 15 })

      // 难度选择器 - 使用背景图片
      Row() {
        // 简单难度按钮
        Button('简 单')
          .width('30%')
          .height(35)
          .fontSize(14)
          .fontColor(this.selectedDifficulty === 'easy' ? '#fff' : '#333')
          .fontWeight(FontWeight.Medium)
          .backgroundImage(this.selectedDifficulty === 'easy' ? $r('app.media.easy') : $r('app.media.easy1')) // 简单难度背景图片
          .backgroundImageSize(ImageSize.Cover)
          .backgroundImagePosition(Alignment.Center)
          .backgroundColor(this.selectedDifficulty === 'easy' ? 'rgba(10, 10, 10, 0.7)' : 'rgba(0, 0, 0, 0)') // 半透明背景色叠加
          .borderRadius(8)
          .onClick(() => {
            this.selectedDifficulty = 'easy';
            this.fetchLeaderboardPreview();
          })

        // 普通难度按钮
        Button('普 通')
          .width('30%')
          .height(35)
          .fontSize(14)
          .fontColor(this.selectedDifficulty === 'normal' ? '#fff' : '#333')
          .fontWeight(FontWeight.Medium)
          .backgroundImage(this.selectedDifficulty === 'normal' ? $r('app.media.normal') : $r('app.media.normal1')) // 普通难度背景图片
          .backgroundImageSize(ImageSize.Cover)
          .backgroundImagePosition(Alignment.Center)
          .backgroundColor(this.selectedDifficulty === 'normal' ? 'rgba(10, 10, 10, 0.7)' : 'rgba(0, 0, 0, 0)') // 半透明背景色叠加
          .borderRadius(8)
          .margin({ left: 10, right: 10 })
          .onClick(() => {
            this.selectedDifficulty = 'normal';
            this.fetchLeaderboardPreview();
          })

        // 困难难度按钮
        Button('困 难')
          .width('30%')
          .height(35)
          .fontSize(14)
          .fontColor(this.selectedDifficulty === 'hard' ? '#fff' : '#333')
          .fontWeight(FontWeight.Medium)
          .backgroundImage(this.selectedDifficulty === 'hard' ? $r('app.media.hard') : $r('app.media.hard1')) // 困难难度背景图片
          .backgroundImageSize(ImageSize.Cover)
          .backgroundImagePosition(Alignment.Center)
          .backgroundColor(this.selectedDifficulty === 'hard' ? 'rgba(10, 10, 10, 0.7)' : 'rgba(0, 0, 0, 0)') // 半透明背景色叠加
          .borderRadius(8)
          .onClick(() => {
            this.selectedDifficulty = 'hard';
            this.fetchLeaderboardPreview();
          })
      }
      .margin({ bottom: 15 })

        // 显示前10名排行榜预览
        if (this.isLeaderboardLoading) {
          Stack() {
            // 半透明背景
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('rgba(255, 255, 255, 0.6)')
              .borderRadius(12)

            Column() {
              LoadingProgress()
                .width(30)
                .height(30)
                .color('#3498db')
                .margin({ bottom: 10 })
              Text('加载中...')
                .fontSize(14)
                .fontColor('#7f8c8d')
            }
            .width('100%')
            .height('60%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .height('60%')
        } else if (this.leaderboardData.length === 0) {
          Stack() {
            // 半透明背景
            Column()
              .width('100%')
              .height('100%')
              .backgroundColor('rgba(255, 255, 255, 0.6)')
              .borderRadius(12)

            Column() {
              Text('📊')
                .fontSize(40)
                .margin({ bottom: 10 })
              Text('暂无排名数据')
                .fontSize(16)
                .fontColor('#7f8c8d')
            }
            .width('100%')
            .height('60%')
            .justifyContent(FlexAlign.Center)
            .alignItems(HorizontalAlign.Center)
          }
          .width('100%')
          .height('60%')
        } else {
          // 使用Column而不是Stack来确保按钮可见
          Column() {
            Stack() {
              // 半透明背景
              Column()
                .width('100%')
                .height('100%')
                .backgroundColor('rgba(255, 255, 255, 0.6)')
                .borderRadius(12)

              Column() {
                // 显示前10名
                List() {
                  ForEach(this.leaderboardData.slice(0, 10), (item: LeaderboardItem, index: number) => {
                    ListItem() {
                      Row() {
                        // 排名
                        Column() {
                          if (index === 0) {
                            Text('🥇')
                              .fontSize(20)
                          } else if (index === 1) {
                            Text('🥈')
                              .fontSize(20)
                          } else if (index === 2) {
                            Text('🥉')
                              .fontSize(20)
                          } else {
                            Text((index + 1).toString())
                              .fontSize(16)
                              .fontColor('#7f8c8d')
                          }
                        }
                        .width(30)
                        .justifyContent(FlexAlign.Center)
                        .alignItems(HorizontalAlign.Center)

                        // 用户邮箱
                        Text(item.email)
                          .fontSize(14)
                          .fontColor(item.email === this.userEmail ? '#FF7043' : '#2C3E50')
                          .fontWeight(item.email === this.userEmail ? FontWeight.Bold : FontWeight.Normal)
                          .layoutWeight(1)
                          .margin({ left: 10 })
                          .maxLines(1)
                          .textOverflow({ overflow: TextOverflow.Ellipsis })

                        // 积分
                        // Text(`${item.score}`)
                        //   .fontSize(14)
                        //   .fontColor('#4CAF50')
                      }
                      .padding(10)
                      .width('100%')
                      .backgroundColor(index % 2 === 0 ? 'rgba(255, 233, 79, 0.3)' : 'rgba(209, 130, 248, 0.3)')
                      .borderRadius(6)
                    }
                  })
                }
                .height(425) // 减少高度，为按钮留出空间
                .width('100%')
              }
              .width('100%')
              .padding(15)
            }
            .width('100%')
            .height(425) // 固定Stack的高度

            // 查看完整排行榜的按钮 - 放在Stack外部，确保可见
            Button('查看完整排行榜')
              .width('70%')
              .height(40)
              .fontSize(16)
              .fontColor(Color.White)
              .fontWeight(FontWeight.Medium)
              .backgroundImage($r('app.media.hard')) // 添加背景图片
              .backgroundImageSize(ImageSize.Cover) // 背景图片覆盖整个按钮
              .backgroundImagePosition(Alignment.Center) // 图片居中
              //.backgroundColor('rgba(244, 67, 54, 0.7)') // 半透明背景色叠加，与困难模式按钮保持一致
              .borderRadius(8) // 添加圆角
              .margin({ top: 15 })
              .onClick(() => {
                router.pushUrl({ url: 'pages/LeaderboardPage' });
              })
          }
          .width('100%')
        }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Start)
    .alignItems(HorizontalAlign.Center)
  }

  // 个人中心组件 - 修改头像显示并获取所有难度积分
  @Builder profileContainer() {
    Column() {
      if (this.token) {
        Column() {
          // 修改为动态头像
          if (this.avatarUrl && !this.avatarLoadFailed) {
            Image(this.avatarUrl)
              .width(100)
              .height(100)
              .borderRadius(50)
              .margin({ bottom: 15 })
              .border({ width: 3, color: '#E640FF' })
              .onError(() => {
                // 图片加载失败时设置状态
                this.avatarLoadFailed = true;
              })
          } else {
            // 加载失败或没有头像时使用默认头像
            Image($r('app.media.guest_avatar'))
              .width(100)
              .height(100)
              .borderRadius(50)
              .margin({ bottom: 15 })
              .border({ width: 3, color: '#E640FF' })
          }

          Text(this.userEmail)
            .fontSize(22)
            .fontColor('#E640FF')
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 20 })

          // 积分卡片容器
          Column() {
            // 简单模式积分
            Row() {
              Text('简单模式')
                .fontSize(16)
                .fontColor('#3498db')
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)
              Text(`${this.userEasyScore} 积分`)
                .fontSize(16)
                .fontColor('#3498db')
            }
            .padding(10)
            .width('100%')
            .backgroundColor('rgba(108, 182, 255, 0.3)')
            .borderRadius(8)
            .margin({ bottom: 10 })

            // 普通模式积分
            Row() {
              Text('普通模式')
                .fontSize(16)
                .fontColor('#ee964f')
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)
              Text(`${this.userNormalScore} 积分`)
                .fontSize(16)
                .fontColor('#ee964f')
            }
            .padding(10)
            .width('100%')
            .backgroundColor('rgba(255, 233, 79, 0.3)')
            .borderRadius(8)
            .margin({ bottom: 10 })

            // 困难模式积分
            Row() {
              Text('困难模式')
                .fontSize(16)
                .fontColor('#c34fee')
                .fontWeight(FontWeight.Bold)
                .layoutWeight(1)
              Text(`${this.userHardScore} 积分`)
                .fontSize(16)
                .fontColor('#c34fee')
            }
            .padding(10)
            .width('100%')
            .backgroundColor('rgba(209, 130, 248, 0.3)')
            .borderRadius(8)
            .margin({ bottom: 20 })
          }
          .width('90%')
          .padding(15)
          //.backgroundColor(Color.White)
          .borderRadius(12)
          //.shadow({ radius: 5, color: '#ecf0f1', offsetX: 0, offsetY: 2 })

          Button('退 出 登 录')
            .width(200)
            .height(45)
            .fontSize(18)
            .fontColor(Color.White)
            .backgroundImage($r('app.media.hard')) // 添加背景图片
            .backgroundImageSize(ImageSize.Cover) // 背景图片覆盖整个按钮
            .backgroundImagePosition(Alignment.Center) // 图片居中
            //.backgroundColor('#FF5722')
            .borderRadius(8)
            .onClick(() => this.logout())
        }
      } else {
        Column() {
          Text('未登录')
            .fontSize(22)
            .fontColor('#7f8c8d')
            .margin({ bottom: 20 })

          Button('去 登 录')
            .width(200)
            .height(45)
            .fontSize(18)
            .fontColor(Color.White)
            .fontWeight(FontWeight.Medium) // 建议添加字体权重增强可读性
            .backgroundImage($r('app.media.hard')) // 添加背景图片
            .backgroundImageSize(ImageSize.Cover) // 背景图片覆盖整个按钮
            .backgroundImagePosition(Alignment.Center) // 图片居中显示
            //.backgroundColor('#FF9800') // 保留背景色，图片加载失败时显示
            .borderRadius(8)
            .onClick(() => {
              router.pushUrl({ url: 'pages/LoginPage' });
            })
        }
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }

  // 底部导航栏
  @Builder navigationBar() {
    Row() {
      Column() {
        Text() {
          SymbolSpan($r('sys.symbol.house')).fontSize(30)
        }
        .fontColor(this.currentTab === 0 ? '#C64AE5' : '#828282')
        Text('首页')
          .fontSize(16).margin({ top: 5 })
          .fontColor(this.currentTab === 0 ? '#C64AE5' : '#828282')
      }
      .onClick(() => this.switchTab(0))

      Blank().layoutWeight(1)

      Column() {
        Text() {
          SymbolSpan($r('sys.symbol.lightbulb')).fontSize(30)
        }
        .fontColor(this.currentTab === 1 ? '#C64AE5' : '#828282')
        Text('排行榜')
          .fontSize(16).margin({ top: 5 })
          .fontColor(this.currentTab === 1 ? '#C64AE5' : '#828282')
      }
      .onClick(() => this.switchTab(1))

      Blank().layoutWeight(1)

      Column() {
        Text() {
          SymbolSpan($r('sys.symbol.person')).fontSize(30)
        }
        .fontColor(this.currentTab === 2 ? '#C64AE5' : '#828282')
        Text('我的')
          .fontSize(16).margin({ top: 5 })
          .fontColor(this.currentTab === 2 ? '#C64AE5' : '#828282')
      }
      .onClick(() => this.switchTab(2))
    }
    .padding({ top: 15, bottom: 15, left: 30, right: 30 })
    .width('100%')
    .height(70)
    .backgroundColor('#F9E9F4')
    .shadow({ radius: 6, color: '#FFD180', })
  }

  build() {
    Stack() {
      // 1. 首先添加背景图片
      Image($r('app.media.background_1'))
        .width('100%')
        .height('100%')
        .objectFit(ImageFit.Fill) // 覆盖整个区域
        .opacity(0.8) // 可选：设置透明度，避免背景太强烈影响内容

      Column() {
        this.userInfoPanel()

        // 中间内容区域，占据剩余空间
        Column() {
          if (this.currentTab === 0) {
            this.gameContainer()
          } else if (this.currentTab === 1) {
            this.leaderboardContainer()
          } else if (this.currentTab === 2) {
            this.profileContainer()
          }
        }
        .layoutWeight(1) // 🔑 填充剩余空间
        .width('100%')

        // 底部导航栏，始终固定在底部
        this.navigationBar()
      }
      .width('100%')
      .height('100%')
     // .backgroundColor('#FFFDE7')

      // 音乐控制组件 - 会定位在右上角
      MusicControl()
    }
    .width('100%')
    .height('100%')
  }
}