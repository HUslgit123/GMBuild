// =============================================================================
// GMUnlocker.m —— 终极版（修复 ARC 编译报错 + Class 指针直读 + 视图打捞）
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
// 2. 核心辅助：安全获取 Class 与视图打捞
// -------------------------------------------------------------
static Class GM_getRealLPGMButtonClass(uintptr_t base) {
    // 1. 优先从 classref 地址 (0x100f1f568) 安全读取类指针 (ARC 兼容)
    uintptr_t classRefAddr = base + 0xf1f568;
    void *ptr = *(void **)classRefAddr;
    Class cls = (__bridge Class)ptr;
    if (cls && class_getName(cls)) {
        return cls;
    }
    
    // 2. 备选方案：全量遍历类列表匹配
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes) {
        for (unsigned int i = 0; i < count; i++) {
            NSString *curName = NSStringFromClass(classes[i]);
            if ([curName containsString:@"LPGMButton"]) {
                cls = classes[i];
                break;
            }
        }
        free(classes);
    }
    return cls;
}

// 递归查找并将所有 GM 视图强制置顶与显形
static void GM_rescueAllGMViews(UIView *rootView, UIWindow *targetWindow) {
    if (!rootView) return;
    
    for (UIView *subview in [rootView.subviews copy]) {
        NSString *clsName = NSStringFromClass([subview class]);
        if ([clsName containsString:@"GM"] || [clsName containsString:@"LP"] || [clsName containsString:@"Table"]) {
            if (![subview isKindOfClass:[GMSuspendButton class]] && subview.tag != BTN_TAG_NATIVE) {
                subview.hidden = NO;
                subview.alpha = 1.0;
                subview.userInteractionEnabled = YES;
                
                if (subview.bounds.size.width < 50 || subview.bounds.size.height < 50) {
                    subview.frame = CGRectMake(20, 80, [UIScreen mainScreen].bounds.size.width - 40, [UIScreen mainScreen].bounds.size.height - 160);
                }
                
                if (targetWindow && subview.superview != targetWindow) {
                    [targetWindow addSubview:subview];
                }
                [subview.superview bringSubviewToFront:subview];
                NSLog(@"[GM5] 打捞并置顶 GM 视图: %@", clsName);
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
    
    // 【背包界面】：添加 GM 悬浮按钮与原生实体按钮
    if ([clsName containsString:@"BagViewController"]) {
        dispatch_async(dispatch_get_main_queue(), ^{
            uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
            uintptr_t base  = 0x100000000 + slide;
            Class gmClass   = GM_getRealLPGMButtonClass(base);
            
            // 1. 创建悬浮控制器按钮
            if (![self.view viewWithTag:BTN_TAG_GM]) {
                GMSuspendButton *btn = [self gm_createButtonWithTitle:@"★ GM ★"
                                                                color:[UIColor colorWithRed:0.85 green:0.2 blue:0.2 alpha:0.92]
                                                                frame:CGRectMake(self.view.bounds.size.width - 85, 120, 75, 34)
                                                                  tag:BTN_TAG_GM
                                                               action:@selector(gm_onTapGMButton:)];
                [self.view addSubview:btn];
                [self.view bringSubviewToFront:btn];
            }
            
            // 2. 创建实体 GM 原生按钮（放置在屏幕顶部可见区域）
            if (![self.view viewWithTag:BTN_TAG_NATIVE]) {
                UIButton *nativeBtn = [UIButton buttonWithType:UIButtonTypeCustom];
                nativeBtn.tag = BTN_TAG_NATIVE;
                nativeBtn.frame = CGRectMake(20, 70, 110, 36);
                [nativeBtn setTitle:@"⚡原生GM" forState:UIControlStateNormal];
                nativeBtn.backgroundColor = [UIColor colorWithRed:0.55 green:0.15 blue:0.85 alpha:0.95];
                nativeBtn.layer.cornerRadius = 8;
                nativeBtn.layer.borderWidth = 1.0;
                nativeBtn.layer.borderColor = [UIColor whiteColor].CGColor;
                nativeBtn.titleLabel.font = [UIFont boldSystemFontOfSize:13];
                [nativeBtn addTarget:self action:@selector(gm_onTapGMButton:) forControlEvents:UIControlEventTouchUpInside];
                
                // 强制将 isa 修改为 LPGMButton
                if (gmClass) {
                    object_setClass(nativeBtn, gmClass);
                }
                
                [self.view addSubview:nativeBtn];
                [self.view bringSubviewToFront:nativeBtn];
            }
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
// 【核心功能 1】：唤醒原生 GM 面板
// -------------------------------------------------------------
- (void)gm_onTapGMButton:(id)sender {
    uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
    uintptr_t base  = 0x100000000 + slide;
    
    // 1. 即时写入 Gate A (*pA = 0) 与 Gate B (*pB = 1)
    uint8_t *pGateA = (uint8_t *)(base + 0x00f504a8);
    uint8_t *pGateB = (uint8_t *)(base + 0x00f504a9);
    if (pGateA && pGateB) {
        *pGateA = 0;
        *pGateB = 1;
    }
    
    // 2. 准备合法 sender (必须带 LPGMButton 的 isa)
    Class gmClass = GM_getRealLPGMButtonClass(base);
    UIView *targetSender = [self.view viewWithTag:BTN_TAG_NATIVE];
    if (!targetSender) targetSender = sender;
    if (gmClass && targetSender) {
        object_setClass(targetSender, gmClass);
    }
    
    // 3. 触发官方入口或直调构建器
    SEL gmSel = NSSelectorFromString(@"clickGMButtonWithButton:");
    if ([self respondsToSelector:gmSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, gmSel, targetSender);
    } else {
        typedef void (*GMBuilderFunc)(id sender_btn);
        GMBuilderFunc builder = (GMBuilderFunc)(base + 0x59c638);
        @try {
            builder(targetSender);
        } @catch (NSException *e) {}
    }
    
    // 4. 真实回读状态：判断是否放行
    GMSuspendButton *gmBtn = (GMSuspendButton *)[self.view viewWithTag:BTN_TAG_GM];
    if (pGateB && *pGateB == 0) {
        [gmBtn setTitle:@"✓放行成功" forState:UIControlStateNormal];
    } else {
        [gmBtn setTitle:@"✗卡GateC" forState:UIControlStateNormal];
    }
    
    // 5. 延迟 0.15 秒打捞并置顶所有 GM 视图
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *targetWindow = nil;
        NSArray<UIWindow *> *windows = [UIApplication sharedApplication].windows;
        for (UIWindow *win in windows) {
            if (win.isKeyWindow) {
                targetWindow = win;
                break;
            }
        }
        if (!targetWindow && windows.count > 0) {
            targetWindow = windows.firstObject;
        }
        
        GM_rescueAllGMViews(self.view, targetWindow);
        if (targetWindow) {
            GM_rescueAllGMViews(targetWindow, targetWindow);
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [gmBtn setTitle:@"★ GM ★" forState:UIControlStateNormal];
        });
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
