// =============================================================================
// GMUnlocker_Final.m —— 终极整合版
// 1. 内存级 Patch：解除广告冷却与日限
// 2. 伪造发奖回调：直接触发激励视频奖励
// 3. 原生 GM 面板唤醒：直接调用底层构建函数 (0x1005e5694) + 视图安全解隐置顶
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
// 1. 内存指令级 Patch (解除广告30分钟与24次限制)
// -------------------------------------------------------------
static void patchAllGates(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
        uintptr_t base  = 0x100000000 + slide;
        
        long pageSize = sysconf(_SC_PAGESIZE);
        
        struct PatchEntry {
            uintptr_t offset;
            uint32_t instruction;
            const char *desc;
        } patches[] = {
            { 0x75144,  0xD503201F, "广告30分钟冷却拦截 (b.ge -> NOP)" },
            { 0x75240,  0xD503201F, "广告每日24次上限拦截 (b.ge -> NOP)" },
            { 0x9428c8, 0xD503201F, "商城每日广告拦截 (b.ge -> NOP)" }
        };
        
        size_t count = sizeof(patches) / sizeof(patches[0]);
        for (size_t i = 0; i < count; i++) {
            uintptr_t targetAddr = base + patches[i].offset;
            uintptr_t pageStart  = targetAddr & ~(pageSize - 1);
            
            if (mprotect((void *)pageStart, pageSize, PROT_READ | PROT_WRITE | PROT_EXEC) == 0) {
                *(uint32_t *)targetAddr = patches[i].instruction;
                mprotect((void *)pageStart, pageSize, PROT_READ | PROT_EXEC);
                NSLog(@"[GM_FINAL] 成功 Patch: %s (0x%lx)", patches[i].desc, targetAddr);
            }
        }
    });
}

// -------------------------------------------------------------
// 2. 悬浮拖拽按钮实现
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
// 3. 视图生命周期注入与控制逻辑
// -------------------------------------------------------------
@implementation UIViewController (GMUnlockerFinal)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        patchAllGates();
        
        Method orig = class_getInstanceMethod(self, @selector(viewDidAppear:));
        Method swiz = class_getInstanceMethod(self, @selector(gm_final_viewDidAppear:));
        method_exchangeImplementations(orig, swiz);
    });
}

- (void)gm_final_viewDidAppear:(BOOL)animated {
    [self gm_final_viewDidAppear:animated];
    
    NSString *clsName = NSStringFromClass([self class]);
    
    // 背包界面：添加 GM 面板按钮
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
    
    // 商城或配置界面：添加免看广告领奖按钮
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
// 【核心功能 1】：唤醒原生 GM 面板（直接执行构建函数 + 安全解隐）
// -------------------------------------------------------------
- (void)gm_onTapGMButton:(GMSuspendButton *)sender {
    uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
    uintptr_t base  = 0x100000000 + slide;
    
    // 1. 设置数据段全局变量 (0x100f504a8)
    uint8_t *pGlobalDebug = (uint8_t *)(base + 0x00f504a8);
    if (pGlobalDebug) {
        *pGlobalDebug = 0;
    }
    
    // 2. 直接调用 GM 面板底层构建函数 (0x1005e5694)
    typedef void (*GMBuildFunc)(id self_vc);
    GMBuildFunc buildGM = (GMBuildFunc)(base + 0x5e5694);
    
    @try {
        buildGM(self);
        NSLog(@"[GM_FINAL] 成功直接调用 GM 构建入口: 0x%lx", (uintptr_t)buildGM);
    } @catch (NSException *e) {
        NSLog(@"[GM_FINAL] 调用构建入口异常: %@", e);
    }
    
    // 3. 延迟 0.1 秒将生成的 GM 视图置顶显示
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class curCls = [self class];
        while (curCls && curCls != [NSObject class]) {
            unsigned int count = 0;
            Ivar *ivars = class_copyIvarList(curCls, &count);
            for (unsigned int i = 0; i < count; i++) {
                const char *type = ivar_getTypeEncoding(ivars[i]);
                if (type && type[0] == '@') {
                    id val = object_getIvar(self, ivars[i]);
                    if ([val isKindOfClass:[UIView class]]) {
                        UIView *v = (UIView *)val;
                        NSString *vCls = NSStringFromClass([v class]);
                        if ([vCls containsString:@"GM"] || [vCls containsString:@"LP"]) {
                            if (!v.superview) [self.view addSubview:v];
                            v.hidden = NO;
                            v.alpha = 1.0;
                            [v.superview bringSubviewToFront:v];
                        }
                    }
                }
            }
            free(ivars);
            curCls = class_getSuperclass(curCls);
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
