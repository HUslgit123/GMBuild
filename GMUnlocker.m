// =============================================================================
// GMUnlocker.m —— v6 终极全功能集成版
// 1. 【GM/CZ/JJ 三面板解锁】：精准定位 BagVC 实例 + BSS 门禁赋初值 + 动态 Target 类 Sender
// 2. 【可视化 HUD 日志诊断】：屏幕浮窗实时回显状态 + 沙盒落盘 <tmp>/gm6_v6.log
// 3. 【秒领广告奖励】：伪造激励视频回调直刷灵石
// 4. 【零外部符号依赖】：编译兼容 ARC/MRC，杜绝链接错误与野指针闪退
// =============================================================================

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <sys/mman.h>
#import <unistd.h>

#define VA_BASE        0x100000000ULL
#define OFF_GATE_A     0x00f504a8ULL   // 必须 == 0
#define OFF_GATE_B     0x00f504a9ULL   // 必须 == 1
#define OFF_ISA_SLOT   0x00f1f568ULL   // 闸门C 对比类指针槽位

// -------------------------------------------------------------
// 1. 全局诊断日志与落盘系统
// -------------------------------------------------------------
static UITextView *g_hudTextView = nil;
static NSMutableArray *g_logHistory = nil;

static void GM_Log(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *logStr = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    
    NSLog(@"[GM6] %@", logStr);
    
    // 写入临时目录文件
    static NSString *logPath = nil;
    if (!logPath) {
        logPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"gm6_v6.log"];
    }
    FILE *fp = fopen([logPath UTF8String], "a+");
    if (fp) {
        fprintf(fp, "%s\n", [logStr UTF8String]);
        fclose(fp);
    }
    
    // 更新 HUD 屏幕滚动回显
    dispatch_async(dispatch_get_main_queue(), ^{
        if (!g_logHistory) g_logHistory = [NSMutableArray array];
        [g_logHistory addObject:logStr];
        if (g_logHistory.count > 6) [g_logHistory removeObjectAtIndex:0];
        if (g_hudTextView) {
            g_hudTextView.text = [g_logHistory componentsJoinedByString:@"\n"];
        }
    });
}

// -------------------------------------------------------------
// 2. 悬浮控制台 HUD 界面
// -------------------------------------------------------------
@interface GMControlHUD : UIView
@property (nonatomic, assign) CGPoint beginPoint;
@end

@implementation GMControlHUD

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        self.backgroundColor = [UIColor colorWithWhite:0.05 alpha:0.92];
        self.layer.cornerRadius = 12;
        self.layer.borderWidth = 1.5;
        self.layer.borderColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:0.9].CGColor;
        self.layer.masksToBounds = YES;
        self.userInteractionEnabled = YES;
        [self setupSubviews];
    }
    return self;
}

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

- (UIButton *)createBtn:(NSString *)title bg:(UIColor *)color y:(CGFloat)y action:(SEL)action {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.frame = CGRectMake(8, y, self.bounds.size.width - 16, 28);
    btn.backgroundColor = color;
    btn.layer.cornerRadius = 6;
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:11];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:btn];
    return btn;
}

- (void)setupSubviews {
    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(8, 6, self.bounds.size.width - 16, 16)];
    title.text = @"⚡ GM6 逆向控制台";
    title.textColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
    title.font = [UIFont boldSystemFontOfSize:12];
    [self addSubview:title];
    
    // 状态日志视窗
    g_hudTextView = [[UITextView alloc] initWithFrame:CGRectMake(8, 26, self.bounds.size.width - 16, 68)];
    g_hudTextView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.9];
    g_hudTextView.textColor = [UIColor colorWithRed:0.9 green:0.9 blue:0.3 alpha:1.0];
    g_hudTextView.font = [UIFont systemFontOfSize:9];
    g_hudTextView.editable = NO;
    g_hudTextView.layer.cornerRadius = 4;
    [self addSubview:g_hudTextView];
    
    // 功能操作区
    [self createBtn:@"① 开启原生 GM 面板" bg:[UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9] y:98 action:@selector(onTapGM)];
    [self createBtn:@"② 开启 CZ 充值面板" bg:[UIColor colorWithRed:0.8 green:0.5 blue:0.1 alpha:0.9] y:130 action:@selector(onTapCZ)];
    [self createBtn:@"③ 开启 JJ 打赏面板" bg:[UIColor colorWithRed:0.5 green:0.2 blue:0.8 alpha:0.9] y:162 action:@selector(onTapJJ)];
    [self createBtn:@"⚡ 免广告领灵石(+20)" bg:[UIColor colorWithRed:0.1 green:0.5 blue:0.9 alpha:0.9] y:194 action:@selector(onTapReward)];
    [self createBtn:@"🔍 强制解隐置顶" bg:[UIColor colorWithWhite:0.3 alpha:0.9] y:226 action:@selector(onTapUnhide)];
}

// -------------------------------------------------------------
// 3. 底层调用与门禁击穿引擎
// -------------------------------------------------------------
- (UIViewController *)findBagVC:(UIViewController *)root {
    if (!root) return nil;
    if ([NSStringFromClass([root class]) containsString:@"BagViewController"]) return root;
    for (UIViewController *child in root.childViewControllers) {
        UIViewController *res = [self findBagVC:child];
        if (res) return res;
    }
    if (root.presentedViewController) {
        return [self findBagVC:root.presentedViewController];
    }
    return nil;
}

- (UIViewController *)getCurrentBagViewController {
    UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
    if (!keyWin && [UIApplication sharedApplication].windows.count > 0) {
        keyWin = [UIApplication sharedApplication].windows.firstObject;
    }
    return [self findBagVC:keyWin.rootViewController];
}

- (UIView *)findSubViewByClass:(NSString *)className inView:(UIView *)rootView {
    if (!rootView) return nil;
    if ([NSStringFromClass([rootView class]) containsString:className]) return rootView;
    for (UIView *sub in rootView.subviews) {
        UIView *res = [self findSubViewByClass:className inView:sub];
        if (res) return res;
    }
    return nil;
}

- (void)triggerPanelWithSelector:(NSString *)selName desc:(NSString *)desc {
    UIViewController *bagVC = [self getCurrentBagViewController];
    if (!bagVC) {
        GM_Log(@"❌ 失败: 未在当前视图树找到 BagViewController，请先打开背包界面！");
        return;
    }
    
    uintptr_t slide = _dyld_get_image_vmaddr_slide(0);
    uintptr_t base  = VA_BASE + slide;
    
    // 1. BSS 闸门写保护解除与即时置位 (A=0, B=1)
    uint8_t *pGateA = (uint8_t *)(base + OFF_GATE_A);
    uint8_t *pGateB = (uint8_t *)(base + OFF_GATE_B);
    if (pGateA && pGateB) {
        long pageSize = sysconf(_SC_PAGESIZE);
        uintptr_t pageStart = ((uintptr_t)pGateA) & ~(pageSize - 1);
        mprotect((void *)pageStart, pageSize, PROT_READ | PROT_WRITE);
        *pGateA = 0;
        *pGateB = 1;
        GM_Log(@"[1] 闸门写入: A=0, B=1 (页保护解除)");
    }
    
    // 2. 闸门 C：读取真实 isa 槽位或复用已有的 LPGMButton
    id sender = [self findSubViewByClass:@"LPGMButton" inView:bagVC.view];
    if (sender) {
        GM_Log(@"[2] 成功复用背包内已有真实 LPGMButton 实例");
    } else {
        Class targetClass = nil;
        uintptr_t isaSlotAddr = base + OFF_ISA_SLOT;
        void *clsPtr = *(void **)isaSlotAddr;
        if (clsPtr) {
            targetClass = (__bridge Class)clsPtr;
            GM_Log(@"[2] 读取到闸门C槽位目标类: %s", class_getName(targetClass));
        }
        if (!targetClass) {
            targetClass = NSClassFromString(@"LPGMButton");
        }
        if (targetClass) {
            @try {
                sender = [[targetClass alloc] initWithFrame:CGRectMake(0, 0, 10, 10)];
            } @catch (NSException *e) {}
        }
        if (!sender) sender = bagVC;
    }
    
    // 3. 发送实例消息
    SEL targetSel = NSSelectorFromString(selName);
    if ([bagVC respondsToSelector:targetSel]) {
        GM_Log(@"[3] 正在向 BagVC 发送官方消息 -[%@]", selName);
        ((void (*)(id, SEL, id))objc_msgSend)(bagVC, targetSel, sender);
    } else {
        GM_Log(@"❌ 警告: BagVC 未响应 %@", selName);
    }
    
    // 4. 物理回读验证
    if (pGateB) {
        if (*pGateB == 0) {
            GM_Log(@"✅ [4] 闸门B已自动清零！构建器已完整执行！");
        } else {
            GM_Log(@"⚠️ [4] 闸门B仍为1，可能被 Gate C (isa) 拦截");
        }
    }
    
    // 5. 延迟进行视图安全解隐置顶
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self onTapUnhide];
    });
}

// -------------------------------------------------------------
// 4. 按钮事件分发
// -------------------------------------------------------------
- (void)onTapGM {
    [self triggerPanelWithSelector:@"clickGMButtonWithButton:" desc:@"GM 面板"];
}

- (void)onTapCZ {
    [self triggerPanelWithSelector:@"clickCZButtonWithButton:" desc:@"CZ 充值面板"];
}

- (void)onTapJJ {
    [self triggerPanelWithSelector:@"clickJJButtonWithButton:" desc:@"JJ 打赏面板"];
}

- (void)onTapReward {
    UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
    UIViewController *root = keyWin.rootViewController;
    UIViewController *topVC = root;
    while (topVC.presentedViewController) topVC = topVC.presentedViewController;
    
    SEL rewardSel = NSSelectorFromString(@"gdt_rewardVideoAdDidRewardEffective:info:");
    if ([topVC respondsToSelector:rewardSel]) {
        ((void (*)(id, SEL, id, id))objc_msgSend)(topVC, rewardSel, nil, nil);
        GM_Log(@"⚡ 成功发送激励视频回调 -> 灵石+20！");
    } else {
        // 全局广播通知尝试
        [[NSNotificationCenter defaultCenter] postNotificationName:@"GDTRewardVideoAdDidRewardEffectiveNotification" object:nil];
        GM_Log(@"⚡ 已在当前页面尝试触发发奖！");
    }
}

- (void)unhideRecursively:(UIView *)v {
    if (!v) return;
    for (UIView *sub in v.subviews) {
        NSString *cls = NSStringFromClass([sub class]);
        if ([cls containsString:@"GM"] || [cls containsString:@"LP"] || [cls containsString:@"Table"]) {
            sub.hidden = NO;
            sub.alpha = 1.0;
            sub.userInteractionEnabled = YES;
            [sub.superview bringSubviewToFront:sub];
            GM_Log(@"🔍 已置顶视图: %@", cls);
        }
        [self unhideRecursively:sub];
    }
}

- (void)onTapUnhide {
    UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
    [self unhideRecursively:keyWin];
}

@end

// -------------------------------------------------------------
// 5. 注入挂载入口
// -------------------------------------------------------------
__attribute__((constructor)) static void GM_Init(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        UIWindow *keyWin = [UIApplication sharedApplication].keyWindow;
        if (!keyWin && [UIApplication sharedApplication].windows.count > 0) {
            keyWin = [UIApplication sharedApplication].windows.firstObject;
        }
        if (keyWin) {
            GMControlHUD *hud = [[GMControlHUD alloc] initWithFrame:CGRectMake([UIScreen mainScreen].bounds.size.width - 190, 80, 180, 262)];
            [keyWin addSubview:hud];
            [keyWin bringSubviewToFront:hud];
            GM_Log(@"🚀 GM6 控制台加载成功，就绪！");
        }
    });
}
