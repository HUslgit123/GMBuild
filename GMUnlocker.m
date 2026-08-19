// =============================================================================
// GMUnlocker.m —— 终极版（UI 坐标修复 + 全局视图打捞置顶）
// =============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <unistd.h>

#define BTN_TAG_GM     77701
#define BTN_TAG_AD     77702
#define BTN_TAG_NATIVE 77703

// -------------------------------------------------------------
// 1. 悬浮拖拽按钮组件
// -------------------------------------------------------------
@interface GMSuspendButton : UIButton
@property (nonatomic, assign) CGPoint beginPoint;
@end

@implementation GMSuspendButton

- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    self.beginPoint = [touch locationInView:self];
    [super touchesBegan:touches withEvent:event];
}

- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    UITouch *touch = [touches anyObject];
    CGPoint current = [touch locationInView:self.superview];
    self.center = CGPointMake(current.x - self.beginPoint.x + self.bounds.size.width / 2.0,
                              current.y - self.beginPoint.y + self.bounds.size.height / 2.0);
}

@end

// -------------------------------------------------------------
// 2. 核心辅助：动态类查找与全局视图打捞置顶
// -------------------------------------------------------------
static Class GM_findClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (cls) return cls;
    
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes) {
        for (unsigned int i = 0; i < count; i++) {
            NSString *curName = NSStringFromClass(classes[i]);
            if ([curName hasSuffix:name] || [curName containsString:name]) {
                cls = classes[i];
                break;
            }
        }
        free(classes);
    }
    return cls;
}

// 递归查找并把所有 GM 相关的视图打捞到最顶层 Window
static void GM_rescueAllGMViews(UIView *rootView, UIWindow *targetWindow) {
    if (!rootView) return;
    
    for (UIView *subview in [rootView.subviews copy]) {
        NSString *clsName = NSStringFromClass([subview class]);
        
        // 匹配所有 GM 核心组件
        if ([clsName containsString:@"GM"] || [clsName containsString:@"LP"] || [clsName containsString:@"Table"]) {
            if (![subview isKindOfClass:[GMSuspendButton class]] && subview.tag != BTN_TAG_NATIVE) {
                subview.hidden = NO;
                subview.alpha = 1.0;
                subview.userInteractionEnabled = YES;
                
                // 如果尺寸异常，修正为居中显示
                if (subview.bounds.size.width < 50 || subview.bounds.size.height < 50) {
                    subview.frame = CGRectMake(20, 100, [UIScreen mainScreen].bounds.size.width - 40, [UIScreen mainScreen].bounds.size.height - 200);
                }
                
                // 挂载到主 Window 顶层
                if (targetWindow && subview.superview != targetWindow) {
                    [targetWindow addSubview:subview];
                }
                [subview.superview bringSubviewToFront:subview];
                NSLog(@"[GM5] 成功打捞并置顶 GM 视图: %@, Frame: %@", clsName, NSStringFromCGRect(subview.frame));
            }
        }
        GM_rescueAllGMViews(subview, targetWindow);
    }
}

// -------------------------------------------------------------
// 3. 视图生命周期注入
// -------------------------------------------------------------
@implementation UIViewController (GMUnlockerFinal)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Method orig = class_getInstanceMethod(self, @selector(viewDidAppear:));
        Method swiz = class_getInstanceMethod(self, @selector(gm_final_viewDidAppear:));
        method_exchangeImplementations(orig, swiz);
    });
}

- (void)gm_final_viewDidAppear:(BOOL)animated {
    [self gm_final_viewDidAppear:animated];
    
    NSString *clsName = NSStringFromClass([self class]);
    
    // 【背包界面】：添加 GM 悬浮按钮
    if ([clsName containsString:@"BagViewController"] && ![self.view viewWithTag:BTN_TAG_GM]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            GMSuspendButton *btn = [self gm_createButtonWithTitle:@"★ GM ★"
                                                            color:[UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:0.92]
                                                            frame:CGRectMake(self.view.bounds.size.width - 85, 120, 75, 34)
                                                              tag:BTN_TAG_GM
                                                           action:@selector(gm_onTapGMButton:)];
            [self.view addSubview:btn];
            [self.view bringSubviewToFront:btn];
        });
    }
    
    // 【商城 / 设置界面】：添加免广告秒发奖悬浮按钮
    if (([clsName containsString:@"ShopViewController"] || [clsName containsString:@"OptionViewController"])
        && ![self.view viewWithTag:BTN_TAG_AD]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            GMSuspendButton *btn = [self gm_createButtonWithTitle:@"⚡领奖励"
                                                            color:[UIColor colorWithRed:0.1 green:0.6 blue:0.9 alpha:0.92]
                                                            frame:CGRectMake(self.view.bounds.size.width - 85, 170, 75, 34)
                                                              tag:BTN_TAG_AD
                                                           action:@selector(gm_onTapRewardButton:)];
            [self.view addSubview:btn];
            [self.view bringSubviewToFront:btn];
        });
    }
}

- (GMSuspendButton *)gm_createButtonWithTitle:(NSString *)title
                                        color:(UIColor *)color
                                        frame:(CGRect)frame
                                          tag:(NSInteger)tag
                                       action:(SEL)action {
    GMSuspendButton *btn = [GMSuspendButton buttonWithType:UIButtonTypeCustom];
    btn.tag = tag;
    btn.frame = frame;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 17;
    btn.layer.borderWidth = 1.2;
    btn.layer.borderColor = [UIColor whiteColor].CGColor;
    btn.layer.masksToBounds = YES;
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    return btn;
}

// -------------------------------------------------------------
// 【核心功能 1】：唤醒原生 GM 面板（带屏幕正坐标与视图打捞）
// -------------------------------------------------------------
- (void)gm_onTapGMButton:(GMSuspendButton *)sender {
    uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
    uintptr_t base  = 0x100000000 + slide;
    
    // 1. 即时重写 BSS 闸门（A=0, B=1）
    uint8_t *pGateA = (uint8_t *)(base + 0x00f504a8);
    uint8_t *pGateB = (uint8_t *)(base + 0x00f504a9);
    if (pGateA && pGateB) {
        *pGateA = 0;
        *pGateB = 1;
    }
    
    // 2. 构造真 LPGMButton 实例，并放置在屏幕正中可见区域作为有效锚点
    Class gmBtnClass = GM_findClass(@"LPGMButton");
    id realSender = [self.view viewWithTag:BTN_TAG_NATIVE];
    
    if (!realSender && gmBtnClass) {
        UIButton *nativeBtn = [[gmBtnClass alloc] initWithFrame:CGRectMake(20, 80, 110, 36)];
        nativeBtn.tag = BTN_TAG_NATIVE;
        [nativeBtn setTitle:@"[原生GM入口]" forState:UIControlStateNormal];
        nativeBtn.backgroundColor = [UIColor colorWithRed:0.5 green:0.1 blue:0.8 alpha:0.9];
        nativeBtn.layer.cornerRadius = 8;
        nativeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        [self.view addSubview:nativeBtn];
        [self.view bringSubviewToFront:nativeBtn];
        realSender = nativeBtn;
        NSLog(@"[GM5] 已在背包界面创建原生 GM 入口按钮: %@", nativeBtn);
    }
    if (!realSender) realSender = sender;
    
    // 3. 发送官方消息
    SEL gmSel = NSSelectorFromString(@"clickGMButtonWithButton:");
    if ([self respondsToSelector:gmSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, gmSel, realSender);
    } else {
        typedef void (*GMBuilderFunc)(id sender_btn);
        GMBuilderFunc builder = (GMBuilderFunc)(base + 0x59c638);
        @try {
            builder(realSender);
        } @catch (NSException *e) {}
    }
    
    [sender setTitle:@"✓已激活" forState:UIControlStateNormal];
    
    // 4. 延迟 0.15 秒打捞所有生成的 GM 视图并强制置顶
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
        if (!keyWindow && [UIApplication sharedApplication].windows.count > 0) {
            keyWindow = [UIApplication sharedApplication].windows.firstObject;
        }
        
        GM_rescueAllGMViews(self.view, keyWindow);
        if (keyWindow) {
            GM_rescueAllGMViews(keyWindow, keyWindow);
        }
    });
}

// -------------------------------------------------------------
// 【核心功能 2】：免看广告秒领奖
// -------------------------------------------------------------
- (void)gm_onTapRewardButton:(GMSuspendButton *)sender {
    SEL rewardSel = NSSelectorFromString(@"gdt_rewardVideoAdDidRewardEffective:info:");
    if ([self respondsToSelector:rewardSel]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(self, rewardSel, nil, nil);
        
        [sender setTitle:@"✓已发放" forState:UIControlStateNormal];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [sender setTitle:@"⚡领奖励" forState:UIControlStateNormal];
        });
    }
}

@end
