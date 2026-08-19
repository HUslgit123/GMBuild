// =============================================================================
// GMUnlocker_Final.m —— 终极完整版
// 1. 内存级 Patch：3处广告拦截门禁 (NOP) + 1处 GM 全局布尔门禁 (Force Branch)
// 2. 伪造发奖回调：秒领激励视频奖励（灵石+20）
// 3. 原生 GM 面板唤醒：放行构建门禁 + 视图安全兜底解隐置顶
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
// 1. 内存指令级 Patch (彻底解除广告限制与 GM 调试门禁)
// -------------------------------------------------------------
static void patchAllGates(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
        uintptr_t base  = 0x100000000 + slide;
        
        long pageSize = sysconf(_SC_PAGESIZE);
        
        // 需要 Patch 的关键地址与对应替换机器码
        struct PatchEntry {
            uintptr_t offset;
            uint32_t instruction;
            const char *desc;
        } patches[] = {
            { 0x75144,  0xD503201F, "广告30分钟冷却拦截 (b.ge -> NOP)" },
            { 0x75240,  0xD503201F, "广告每日24次上限拦截 (b.ge -> NOP)" },
            { 0x9428c8, 0xD503201F, "商城每日广告拦截 (b.ge -> NOP)" },
            { 0x59cc70, 0x14000002, "GM构建布尔门禁 (tbnz -> b +8 强制构建)" }
        };
        
        size_t count = sizeof(patches) / sizeof(patches[0]);
        for (size_t i = 0; i < count; i++) {
            uintptr_t targetAddr = base + patches[i].offset;
            uintptr_t pageStart  = targetAddr & ~(pageSize - 1);
            
            if (mprotect((void *)pageStart, pageSize, PROT_READ | PROT_WRITE | PROT_EXEC) == 0) {
                *(uint32_t *)targetAddr = patches[i].instruction;
                mprotect((void *)pageStart, pageSize, PROT_READ | PROT_EXEC);
                NSLog(@"[GM_FINAL] 成功 Patch: %s (0x%lx)", patches[i].desc, targetAddr);
            } else {
                NSLog(@"[GM_FINAL] Patch 权限修改失败: %s", patches[i].desc);
            }
        }
    });
}

// -------------------------------------------------------------
// 2. 悬浮拖拽按钮组件
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
// 3. 视图生命周期注入与主控制逻辑
// -------------------------------------------------------------
@implementation UIViewController (GMUnlockerFinal)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // 启动时立即修补全部内存门禁
        patchAllGates();
        
        Method orig = class_getInstanceMethod(self, @selector(viewDidAppear:));
        Method swiz = class_getInstanceMethod(self, @selector(gm_final_viewDidAppear:));
        method_exchangeImplementations(orig, swiz);
    });
}

- (void)gm_final_viewDidAppear:(BOOL)animated {
    [self gm_final_viewDidAppear:animated];
    
    NSString *clsName = NSStringFromClass([self class]);
    
    // 【背包界面】：添加 GM 唤醒按钮
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
    
    // 【商城 / 设置界面】：添加免广告秒发奖按钮
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
- (void)gm_onTapGMButton:(GMSuspendButton *)sender {
    // 步骤 1：触发原生调用（由于内存已 Patch，内部直接跳入面板构建代码）
    SEL gmSel = NSSelectorFromString(@"clickGMButtonWithButton:");
    if ([self respondsToSelector:gmSel]) {
        ((void (*)(id, SEL, id))objc_msgSend)(self, gmSel, sender);
    }
    
    // 步骤 2：延迟 0.15s 进行安全置顶与解隐兜底（确保动态创建的视图彻底展示）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        Class curCls = [self class];
        while (curCls && curCls != [NSObject class]) {
            unsigned int count = 0;
            Ivar *ivars = class_copyIvarList(curCls, &count);
            for (unsigned int i = 0; i < count; i++) {
                const char *type = ivar_getTypeEncoding(ivars[i]);
                // 严格类型保护：仅解引用标准 OC 对象指针，杜绝野指针崩溃
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
// 【核心功能 2】：免看广告直接发奖
// -------------------------------------------------------------
- (void)gm_onTapRewardButton:(GMSuspendButton *)sender {
    SEL rewardSel = NSSelectorFromString(@"gdt_rewardVideoAdDidRewardEffective:info:");
    if ([self respondsToSelector:rewardSel]) {
        // 直接触发底层的发奖代理回调，传入安全空参数
        ((void (*)(id, SEL, id, id))objc_msgSend)(self, rewardSel, nil, nil);
        
        // 视觉反馈
        [sender setTitle:@"✓已发放" forState:UIControlStateNormal];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [sender setTitle:@"⚡领奖励" forState:UIControlStateNormal];
        });
    }
}

@end
