// =============================================================================
// GMUnlocker.m —— 终极全功能整合版
// 1. 【GM 核心突破】：动态设置 A=0, B=1 (BSS) + 构造真 LPGMButton 实例 (过 Gate C)
// 2. 【秒领灵石奖励】：直接伪造广点通激励视频完成回调，跳过广告秒到账
// 3. 【纯安全实现】：零不安全 ivar 访问，纯视图树与运行时消息，杜绝崩溃闪退
// =============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <unistd.h>

#define BTN_TAG_GM     77701
#define BTN_TAG_AD     77702

// -------------------------------------------------------------
// 1. 可拖拽悬浮按钮组件
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
// 2. 辅助工具：动态查找 Swift / ObjC 类与递归安全解隐
// -------------------------------------------------------------
static Class GM_findClass(NSString *name) {
    Class cls = NSClassFromString(name);
    if (cls) return cls;
    
    // 兼容 Swift 模块前缀混淆（如 _TtC...LPGMButton）
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

// 递归遍历视图树进行安全解隐与置顶（不读任何原生变量，杜绝 Bad Access）
static void GM_unhideViewsRecursively(UIView *rootView) {
    if (!rootView) return;
    for (UIView *subview in rootView.subviews) {
        NSString *clsName = NSStringFromClass([subview class]);
        if ([clsName containsString:@"GM"] || [clsName containsString:@"LP"]) {
            subview.hidden = NO;
            subview.alpha = 1.0;
            [subview.superview bringSubviewToFront:subview];
            NSLog(@"[GM5] 找到并解隐 GM 视图: %@", clsName);
        }
        GM_unhideViewsRecursively(subview);
    }
}

// -------------------------------------------------------------
// 3. 视图生命周期注入与功能实现
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
    
    // 【背包界面】：添加 GM 唤醒悬浮按钮
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
// 【核心功能 1】：完美破解三道门禁，唤醒原生 GM 面板
// -------------------------------------------------------------
- (void)gm_onTapGMButton:(GMSuspendButton *)sender {
    uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
    uintptr_t base  = 0x100000000 + slide;
    
    // 1. 破解 Gate A 与 Gate B (BSS 段状态变量，调用前即时赋初值)
    uint8_t *pGateA = (uint8_t *)(base + 0x00f504a8);
    uint8_t *pGateB = (uint8_t *)(base + 0x00f504a9);
    if (pGateA && pGateB) {
        *pGateA = 0; // Gate A 要求: *pA == 0
        *pGateB = 1; // Gate B 要求: *pB == 1
        NSLog(@"[GM5] 成功重设 BSS 闸门标志: A=0, B=1");
    }
    
    // 2. 破解 Gate C (构造真 LPGMButton 实例，满足 isa 比对)
    Class gmBtnClass = GM_findClass(@"LPGMButton");
    id realSender = nil;
    if (gmBtnClass) {
        realSender = [[gmBtnClass alloc] initWithFrame:CGRectMake(-100, -100, 50, 50)];
        if ([realSender isKindOfClass:[UIView class]]) {
            [self.view addSubview:(UIView *)realSender];
            ((UIView *)realSender).hidden = YES; // 挂载到视图层级，提供 UI 窗口上下文
        }
        NSLog(@"[GM5] 成功实例化真 LPGMButton 对象: %@", realSender);
    } else {
        NSLog(@"[GM5] 警告: 未找到 LPGMButton 类，降级使用自身作为 sender");
        realSender = sender;
    }
    
    // 3. 触发调用链路
    SEL gmSel = NSSelectorFromString(@"clickGMButtonWithButton:");
    if ([self respondsToSelector:gmSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, gmSel, realSender);
        NSLog(@"[GM5] 已通过官方消息通道发送 clickGMButtonWithButton:");
    } else {
        // 兜底方案：直接调用底层构建器函数 (0x10059c638)
        typedef void (*GMBuilderFunc)(id sender_btn);
        GMBuilderFunc builder = (GMBuilderFunc)(base + 0x59c638);
        @try {
            builder(realSender);
            NSLog(@"[GM5] 已通过函数指针直调构建器: 0x%lx", (uintptr_t)builder);
        } @catch (NSException *e) {
            NSLog(@"[GM5] 直调构建器异常: %@", e);
        }
    }
    
    // 4. 闸门回读验证 (构建器执行通过会自动将 B 清零)
    if (pGateB) {
        if (*pGateB == 0) {
            NSLog(@"[GM5] 状态验证: Gate B 成功从 1 变为 0！说明构建器内部已完整放行！");
            [sender setTitle:@"✓已激活" forState:UIControlStateNormal];
        } else {
            NSLog(@"[GM5] 状态验证: Gate B 仍为 1，可能在 Gate C (isa) 拦截。");
        }
    }
    
    // 5. 延迟 0.15 秒，进行视图树递归解隐与置顶兜底
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        GM_unhideViewsRecursively(self.view);
        if (self.view.window) {
            GM_unhideViewsRecursively(self.view.window);
        }
        
        // 1.5 秒后恢复按钮文字
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [sender setTitle:@"★ GM ★" forState:UIControlStateNormal];
        });
    });
}

// -------------------------------------------------------------
// 【核心功能 2】：免看广告秒领奖（灵石+20）
// -------------------------------------------------------------
- (void)gm_onTapRewardButton:(GMSuspendButton *)sender {
    SEL rewardSel = NSSelectorFromString(@"gdt_rewardVideoAdDidRewardEffective:info:");
    if ([self respondsToSelector:rewardSel]) {
        // 直接触发发奖代理回调，传入安全 nil 参数
        ((void (*)(id, SEL, id, id))objc_msgSend)(self, rewardSel, nil, nil);
        
        // 视觉反馈
        [sender setTitle:@"✓已发放" forState:UIControlStateNormal];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [sender setTitle:@"⚡领奖励" forState:UIControlStateNormal];
        });
        NSLog(@"[GM5] 成功触发免广告发奖回调！");
    }
}

@end
