import http from '@ohos.net.http';
import router from '@ohos.router';
import promptAction from '@ohos.promptAction';
import preferences from '@ohos.data.preferences';
import common from '@ohos.app.ability.common';
import connection from '@ohos.net.connection';

interface LoginResponse {
  token: string;
}

@Entry
@Component
struct LoginPage {
  @State email: string = '';
  @State score: number = 0;
  @State code: string = '';
  @State countdown: number = 0;
  @State isFocused: boolean = false;

  private timerId: number = 0;

  // 获取上下文
  private context: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;

  sendVerificationCode() {
    if (!this.email || !this.email.includes('@')) {
      promptAction.showToast({ message: '请输入有效的QQ邮箱！', duration: 2000 });
      return;
    }
    let httpRequest = http.createHttp();
    httpRequest.request(
      'http://10.0.2.2:3000/api/send-code',
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ email: this.email })
      },
      (err, data) => {
        if (!err && data.responseCode === 200) {
          promptAction.showToast({ message: '验证码已发送至邮箱！', duration: 5000 });
          this.startCountdown();
        } else {
          promptAction.showToast({ message: '发送失败，请重试！', duration: 5000 });
        }
      }
    );
  }

  // 倒计时
  startCountdown() {
    this.countdown = 60;
    this.timerId = setInterval(() => {
      if (this.countdown > 0) {
        this.countdown--;
      } else {
        clearInterval(this.timerId);
      }
    }, 1000);
  }


  // 提交登录
  async submitLogin() {
    if (!this.code || this.code.length !== 6) {
      promptAction.showToast({ message: '请输入6位验证码！', duration: 2000 });
      return;
    }

    let httpRequest = http.createHttp();
    httpRequest.request(
      'http://10.0.2.2:3000/api/login',
      {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'application/json' },
        extraData: JSON.stringify({ email: this.email, code: this.code })
      },
      async (err, data) => {
        if (!err && data.responseCode === 200) {
          try {
            const response: LoginResponse = JSON.parse(data.result as string) as LoginResponse;

            // ✅ 保存到AppStorage（内存）
            AppStorage.set('token', response.token);
            AppStorage.set('userEmail', this.email);

            // ✅ 同时保存到持久化存储
            try {
              const prefs = await preferences.getPreferences(this.context, {
                name: 'user_data'
              });
              await prefs.put('token', response.token);
              await prefs.put('userEmail', this.email);
              await prefs.flush();
              console.log('登录状态已保存到持久化存储');
            } catch (prefErr) {
              console.error('保存登录状态失败:', prefErr);
            }

            promptAction.showToast({ message: '登录成功！', duration: 2000 });
            router.replaceUrl({ url: 'pages/Index' });

          } catch (e) {
            console.error('登录处理错误:', e);
            promptAction.showToast({ message: '登录失败，请重试！', duration: 2000 });
          }
        } else {
          promptAction.showToast({ message: '验证码错误或已过期！', duration: 2000 });
        }
      }
    );
  }

  build() {
    // 使用Stack布局实现背景图片和内容叠加
    Stack() {
      // 背景图片
      Column()
        .width('100%')
        .height('100%')
        .backgroundImage($r('app.media.bg2')) // 添加背景图片:cite[1]:cite[6]
        .backgroundImageSize(ImageSize.Cover) // 图片覆盖整个区域:cite[1]
        .backgroundImagePosition(Alignment.Center) // 图片居中显示:cite[1]

      // 内容区域
      Column() {
        // 添加间距 - 方法一：使用 Blank 组件
        Blank()
          .height(10) // 调整这个值来控制间距大小

        // 顶部装饰区域
        Column() {
          Text('欢迎登录')
            .fontSize(28)
            .fontColor('#673B78') // 改为白色文字，在背景图上更清晰
            .fontWeight(FontWeight.Bold)
            .margin({ bottom: 8 })
            .textShadow({ radius: 2, color: '#ECCFF7', offsetX: 1, offsetY: 1 }) // 添加文字阴影增强可读性
            .height(30) // 设置固定高度
            //.textAlign(TextAlign.Center) // 垂直居中显示

          Text('验证码将发送到您的QQ邮箱')
            .fontSize(16)
            .fontColor('#673B78')
            .textShadow({ radius: 1, color: '#ECCFF7', offsetX: 1, offsetY: 1 })
            .height(20) // 设置固定高度
            //.textAlign(TextAlign.Center) // 垂直居中显示
        }
        .width('100%')
        .alignItems(HorizontalAlign.Center)
        .margin({ bottom: 5 }) // 添加下边距

        // 表单区域 - 添加半透明背景提高可读性
        Column({ space: 20 }) {
          // 邮箱输入框
          Column() {
            Text('QQ邮箱')
              .fontSize(14)
              .fontColor('#333333')
              .margin({ bottom: 5, left: -27})
              .width('100%')

            TextInput({ placeholder: '请输入QQ邮箱（如：12345@qq.com）' })
              .width('110.5%')
              .height(50)
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .padding(10)
              .type(InputType.Email)
              .onChange((value: string) => { this.email = value.trim(); })
              .onFocus(() => { this.isFocused = true; })
              .onBlur(() => { this.isFocused = false; })
          }
          .width('90%')

          // 验证码区域
          Column() {
            Row() {
              Text('验证码')
                .fontSize(14)
                .fontColor('#333333')
                .margin({ bottom: 5, left: 3})

              Text('(6位数字)')
                .fontSize(12)
                .fontColor('#666666')
                .margin({ bottom: 5, left: 5})
            }
            .width('100%')
            .justifyContent(FlexAlign.Start)

            Row({ space: 10 }) {
              TextInput({ placeholder: '请输入验证码' })
                .width('65%')
                .height(50)
                .backgroundColor('#FFFFFF')
                .borderRadius(8)
                .padding(10)
                .type(InputType.Number)
                .maxLength(6)
                .onChange((value: string) => { this.code = value.trim(); })

              Button(this.countdown > 0 ? `${this.countdown}s后重试` : '获取验证码')
                .width('31.1%')
                .height(50)
                .fontSize(14)
                .fontColor(this.countdown > 0 ? '#80333333' : '#FFFFFF')
                .fontWeight(FontWeight.Medium) // 增加字体权重提高可读性
                .backgroundImage(this.countdown > 0 ? $r('app.media.wait') : $r('app.media.single_player_icon')) // 根据状态使用不同背景图片
                .backgroundImageSize(ImageSize.Cover) // 背景图片覆盖整个按钮
                .backgroundImagePosition(Alignment.Center) // 图片居中显示
                .backgroundColor(this.countdown > 0 ? '#CCC' : '#80FFFFFF') // 保留背景色，图片加载失败时显示
                .borderRadius(8)
                .enabled(this.countdown === 0)
                .onClick(() => this.sendVerificationCode())
            }
            .width('100%')
          }

          // 登录按钮
          Button('登录'/*, { type: ButtonType.Capsule }*/)
            .width('100%')
            .height(50)
            .fontSize(18)
            .fontColor('#FFF')
            .fontWeight(FontWeight.Bold) // 增加字体权重提高可读性
            .backgroundImage($r('app.media.hard')) // 使用hard.png作为背景图片
            .backgroundImageSize(ImageSize.Cover) // 背景图片覆盖整个按钮
            .backgroundImagePosition(Alignment.Center) // 图片居中显示
            .backgroundColor('#1890FF') // 保留背景色，图片加载失败时显示
            .borderRadius(8)
            .margin({ top: 15 })
            .onClick(() => this.submitLogin())
        }
        .width('100%')
        .margin({ top: -100 })
        .padding(20)
        .backgroundColor('rgba(255, 255, 255, 0.5)') // 半透明白色背景
        .borderRadius(12)

        // 底部说明
        Text('登录即代表您同意《用户协议》和《隐私政策》')
          .fontSize(12)
          .fontColor('#673B78')
          .margin({ top: 30, bottom: 20 })
          .textAlign(TextAlign.Center)
          .width('90%')
          .textShadow({ radius: 1, color: '#ECCFF7', offsetX: 1, offsetY: 1 })
      }
      .width('100%')
      .height('100%')
      .justifyContent(FlexAlign.SpaceBetween)
    }
    .width('100%')
    .height('100%')
  }
}