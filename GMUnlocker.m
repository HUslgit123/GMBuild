// =============================================================================
// GMUnlocker.m —— 终极修复版（正规 Swift 对象初始化 + 寄存器上下文对齐 + 免广告发奖）
// =============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <unistd.h>

#define BTN_TAG_GM     77701
#define BTN_TAG_AD     77702

// -------------------------------------------------------------
// 1. 悬浮拖拽按钮组件 (标准 UIKit)
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
// 2. 辅助工具：安全获取 Class 与视图安全解隐
// -------------------------------------------------------------
static Class GM_findLPGMButtonClass(uintptr_t base) {
    Class cls = NSClassFromString(@"LPGMButton");
    if (cls) return cls;
    
    // 遍历 Runtime 类列表（适配 Swift 名称混淆）
    unsigned int count = 0;
    Class *classes = objc_copyClassList(&count);
    if (classes) {
        for (unsigned int i = 0; i < count; i++) {
            const char *name = class_getName(classes[i]);
            if (name && strstr(name, "LPGMButton")) {
                cls = classes[i];
                break;
            }
        }
        free(classes);
    }
    if (cls) return cls;
    
    // 兜底从 classref (0x100f1f568) 安全提取指针
    @try {
        uintptr_t classRefAddr = base + 0xf1f568;
        void *ptr = *(void **)classRefAddr;
        if (ptr) {
            cls = (__bridge Class)ptr;
        }
    } @catch (NSException *e) {}
    
    return cls;
}

// 递归遍历子视图安全解隐与置顶
static void GM_safeUnhideViews(UIView *rootView) {
    if (!rootView) return;
    for (UIView *subview in [rootView.subviews copy]) {
        NSString *clsName = NSStringFromClass([subview class]);
        if ([clsName containsString:@"GM"] || [clsName containsString:@"LP"] || [clsName containsString:@"Table"]) {
            if (![subview isKindOfClass:[GMSuspendButton class]]) {
                subview.hidden = NO;
                subview.alpha = 1.0;
                subview.userInteractionEnabled = YES;
                [subview.superview bringSubviewToFront:subview];
                NSLog(@"[GM5] 成功解隐并置顶 GM 视图: %@", clsName);
            }
        }
        GM_safeUnhideViews(subview);
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
    
    // 【背包界面】：添加红色 GM 悬浮控制器
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
// 【核心功能 1】：安全唤醒原生 GM 面板（彻底根治闪退）
// -------------------------------------------------------------
- (void)gm_onTapGMButton:(GMSuspendButton *)sender {
    uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
    uintptr_t base  = 0x100000000 + slide;
    
    // 1. 安全重写 Gate A (*pA = 0) 与 Gate B (*pB = 1)
    uint8_t *pGateA = (uint8_t *)(base + 0x00f504a8);
    uint8_t *pGateB = (uint8_t *)(base + 0x00f504a9);
    if (pGateA && pGateB) {
        long pageSize = sysconf(_SC_PAGESIZE);
        uintptr_t pageStart = ((uintptr_t)pGateA) & ~(pageSize - 1);
        mprotect((void *)pageStart, pageSize, PROT_READ | PROT_WRITE);
        *pGateA = 0;
        *pGateB = 1;
        NSLog(@"[GM5] 内存闸门已成功赋予初值: A=0, B=1");
    }
    
    // 2. 正规初始化 LPGMButton 实例（建立完整的 Swift 元数据与引用计数）
    Class gmClass = GM_findLPGMButtonClass(base);
    id realSender = nil;
    if (gmClass) {
        @try {
            // 通过标准的 alloc/initWithFrame 正规初始化，杜绝 raw memory 引用计数崩溃
            realSender = [[gmClass alloc] initWithFrame:CGRectZero];
        } @catch (NSException *e) {
            NSLog(@"[GM5] 标准初始化异常: %@", e);
        }
    }
    if (!realSender) {
        realSender = sender;
    }
    
    // 3. 必须通过 0x1005e5620 入口调用（保证 x20 = self 控制器上下文正确）
    SEL gmSel = NSSelectorFromString(@"clickGMButtonWithButton:");
    if ([self respondsToSelector:gmSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, gmSel, realSender);
    } else {
        typedef void (*GMEntryFunc)(id self_vc, SEL _cmd, id sender_btn);
        GMEntryFunc entry = (GMEntryFunc)(base + 0x5e5620);
        @try {
            entry(self, gmSel, realSender);
        } @catch (NSException *e) {
            NSLog(@"[GM5] 直调 0x1005e5620 异常: %@", e);
        }
    }
    
    // 4. 实时回读验证（物理铁证）
    if (pGateB && *pGateB == 0) {
        [sender setTitle:@"✓放行成功" forState:UIControlStateNormal];
        NSLog(@"[GM5] 物理验证: Gate B 已被游戏底层自动清零，全部三道闸门已完整放行！");
    } else {
        [sender setTitle:@"✗GateC拦截" forState:UIControlStateNormal];
    }
    
    // 5. 延迟 0.15 秒打捞并置顶所有动态创建的 GM 面板
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        GM_safeUnhideViews(self.view);
        if (self.view.window) {
            GM_safeUnhideViews(self.view.window);
        }
        
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
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
        ((void (*)(id, SEL, id, id))objc_msgSend)(self, rewardSel, nil, nil);
        
        [sender setTitle:@"✓已发放" forState:UIControlStateNormal];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [sender setTitle:@"⚡领奖励" forState:UIControlStateNormal];
        });
    }
}

@end
