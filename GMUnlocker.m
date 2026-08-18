// GM Unlocker v2 —— 自诊断 + 三级解锁 GM 面板
//
// 编译（Mac 上执行）:
//   SDK=$(xcrun --sdk iphoneos --show-sdk-path)
//   clang -target arm64-apple-ios12.0 -isysroot "$SDK" -fobjc-arc \
//     -framework UIKit -framework Foundation -framework QuartzCore \
//     -dynamiclib -install_name @rpath/libGM.dylib \
//     -o libGM.dylib gm_unlocker_v2.m
//
// TrollFools 注入前: 先把 v1 的 dylib 注入记录删掉（两个同名分类同时
// swizzle viewDidAppear: 会导致互相覆盖，行为未定义）。
//
// 用法:
//   进背包界面 → 点红色 ★GM★ 按钮
//   成功: 按钮变 "✓GM"，GM 面板应已展开
//   失败: 弹诊断报告（截图整个 Alert 发出来）
//   成功后再点按钮: 弹本次执行的完整诊断（截图发出来可精确定位守卫逻辑）

#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define GM_BTN_TAG 88888

#pragma mark - 可拖拽悬浮按钮
@interface GMSuspendButton : UIButton
@property (nonatomic, assign) CGPoint beginPt;
@property (nonatomic, assign) CGPoint origC;
@property (nonatomic, assign) BOOL busy;
@property (nonatomic, assign) BOOL isUnlocked;
@end

@implementation GMSuspendButton
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event {
    UITouch *t = [touches anyObject];
    self.beginPt = [t locationInView:self.superview];
    self.origC = self.center;
    [super touchesBegan:touches withEvent:event];
}
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event {
    if (!self.superview) return;
    UITouch *t = [touches anyObject];
    CGPoint p = [t locationInView:self.superview];
    CGRect b = self.superview.bounds;
    CGFloat cx = self.origC.x + (p.x - self.beginPt.x);
    CGFloat cy = self.origC.y + (p.y - self.beginPt.y);
    cx = MAX(self.bounds.size.width / 2.0, MIN(cx, b.size.width - self.bounds.size.width / 2.0));
    cy = MAX(self.bounds.size.height / 2.0, MIN(cy, b.size.height - self.bounds.size.height / 2.0));
    self.center = CGPointMake(cx, cy);
    [super touchesMoved:touches withEvent:event];
}
@end

#pragma mark - ivar 工具
// 逐级扫描 ivar（含继承链），对每个匹配的 ivar 回调 (名字, 值)
static void GM_scanIvars(id obj, NSString *contain, void (^cb)(NSString *, id)) {
    Class cls = [obj class];
    while (cls && cls != [NSObject class]) {
        unsigned n = 0;
        Ivar *ivs = class_copyIvarList(cls, &n);
        for (unsigned i = 0; i < n; i++) {
            const char *nm = ivar_getName(ivs[i]);
            if (!nm || !nm[0]) continue;
            NSString *name = [NSString stringWithUTF8String:nm];
            if (!contain || [name rangeOfString:contain].location != NSNotFound) {
                cb(name, object_getIvar((id)obj, ivs[i]));
            }
        }
        free(ivs);
        cls = class_getSuperclass(cls);
    }
}

static id GM_ivarValue(id obj, NSString *name) {
    Class cls = [obj class];
    while (cls && cls != [NSObject class]) {
        unsigned n = 0;
        Ivar *ivs = class_copyIvarList(cls, &n);
        for (unsigned i = 0; i < n; i++) {
            if (strcmp(ivar_getName(ivs[i]), name.UTF8String) == 0) {
                id v = object_getIvar(obj, ivs[i]);
                free(ivs);
                return v;
            }
        }
        free(ivs);
        cls = class_getSuperclass(cls);
    }
    return nil;
}

#pragma mark - 主逻辑
@implementation UIViewController (GMUnlocker2)

+ (void)load {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Method o = class_getInstanceMethod(self, @selector(viewDidAppear:));
        Method m = class_getInstanceMethod(self, @selector(gm2_viewDidAppear:));
        method_exchangeImplementations(o, m);
    });
}

- (void)gm2_viewDidAppear:(BOOL)animated {
    [self gm2_viewDidAppear:animated];
    NSString *cn = NSStringFromClass([self class]);
    if ([cn containsString:@"BagViewController"] && ![self.view viewWithTag:GM_BTN_TAG]) {
        dispatch_async(dispatch_get_main_queue(), ^{ [self gm2_install]; });
    }
}

- (void)gm2_install {
    GMSuspendButton *btn = [GMSuspendButton buttonWithType:UIButtonTypeCustom];
    btn.tag = GM_BTN_TAG;
    btn.frame = CGRectMake(self.view.bounds.size.width - 90, 100, 75, 36);
    [btn setTitle:@"\u2605GM\u2605" forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [btn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    btn.backgroundColor = [UIColor colorWithRed:0.85 green:0.2 blue:0.15 alpha:0.92];
    btn.layer.cornerRadius = 18;
    btn.layer.borderWidth = 1.5;
    btn.layer.borderColor = [UIColor whiteColor].CGColor;
    btn.layer.masksToBounds = YES;
    [btn addTarget:self action:@selector(gm2_tap:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:btn];
    [self.view bringSubviewToFront:btn];
    NSLog(@"[GM2] floating button installed on %@", NSStringFromClass([self class]));
}

- (void)gm2_tap:(GMSuspendButton *)sender {
    if (sender.busy) return;

    NSMutableString *diag = [NSMutableString stringWithFormat:@"class=%@\n",
                             NSStringFromClass([self class])];
    NSMutableArray<UIView *> *gmViews = [NSMutableArray array];
    __block id realBtn = nil; // 修复 1：添加 __block 修饰

    GM_scanIvars(self, @"GM", ^(NSString *nm, id v) {
        [diag appendFormat:@"- ivar %@ = %@\n", nm,
         [v isKindOfClass:UIView.class]
         ? [NSString stringWithFormat:@"<View hidden=%@ alpha=%.2f sup=%@>",
            ((UIView *)v).hidden ? @"Y" : @"N", ((UIView *)v).alpha,
            ((UIView *)v).superview ? @"Y" : @"N"]
         : (v ? [v description] : @"nil")];
        if ([v isKindOfClass:UIView.class]) {
            [gmViews addObject:(UIView *)v];
            if ([nm.uppercaseString rangeOfString:@"LPGMBUTTON"].location != NSNotFound)
                realBtn = v;
        }
    });
    GM_scanIvars(self, @"LP", ^(NSString *nm, id v) {
        [diag appendFormat:@"- ivar %@ = %@\n", nm,
         [v isKindOfClass:UIView.class]
         ? [NSString stringWithFormat:@"<View hidden=%@ alpha=%.2f sup=%@>",
            ((UIView *)v).hidden ? @"Y" : @"N", ((UIView *)v).alpha,
            ((UIView *)v).superview ? @"Y" : @"N"]
         : (v ? [v description] : @"nil")];
        if ([v isKindOfClass:UIView.class]) [gmViews addObject:(UIView *)v];
    });
    for (NSString *s in @[@"bagType", @"istableopen", @"showType"]) {
        id v = GM_ivarValue(self, s);
        [diag appendFormat:@"state %@ = %@\n", s, v ? [v description] : @"no ivar"];
    }

    // 成功后再点 = 直接弹诊断
    if (sender.isUnlocked) {
        [self gm2_showDiag:diag on:sender reuse:NO];
        return;
    }

    sender.busy = YES;
    SEL s1 = NSSelectorFromString(@"clickGMButtonWithButton:");
    BOOL has = [self respondsToSelector:s1];
    [diag appendFormat:@"responds(clickGMButtonWithButton:)=%@\n", has ? @"Y" : @"N"];

    if (has) {
        // 策略 1：真按钮当 sender
        id payload = [realBtn isKindOfClass:UIButton.class] ? realBtn : self;
        ((void (*)(id, SEL, id))objc_msgSend)(self, s1, payload);
        
        // 修复 2：使用标准的 C 指针判等代替不存在的 isSameObject:
        [diag appendFormat:@"call#1 payload=%@\n",
         (payload == self) ? @"self" : @"real LPGMButton"];
    }
    [self gm2_step:1 diag:diag views:gmViews sender:sender realBtn:realBtn];
}

- (void)gm2_step:(int)step
            diag:(NSMutableString *)diag
           views:(NSArray<UIView *> *)gmViews
          sender:(GMSuspendButton *)sender
         realBtn:(id)realBtn {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        BOOL visible = NO;
        for (UIView *v in gmViews) {
            if (v.superview && !v.hidden && v.alpha > 0.05) { visible = YES; break; }
        }
        if (visible) { [self gm2_done:sender diag:diag ok:YES]; return; }

        if (step == 1) {
            SEL s1 = NSSelectorFromString(@"clickGMButtonWithButton:");
            if ([self respondsToSelector:s1]) {
                // 策略 2：self 当 sender 再调一次
                ((void (*)(id, SEL, id))objc_msgSend)(self, s1, self);
                [diag appendString:@"call#2 payload=self\n"];
                [self gm2_step:2 diag:diag views:gmViews sender:sender realBtn:realBtn];
            } else if (realBtn && [realBtn isKindOfClass:UIButton.class]) {
                // 策略 1b：真按钮 sender
                ((void (*)(id, SEL, id))objc_msgSend)(self, s1, realBtn);
                [diag appendString:@"call#2 payload=real\n"];
                [self gm2_step:2 diag:diag views:gmViews sender:sender realBtn:realBtn];
            } else {
                [self gm2_step:3 diag:diag views:gmViews sender:sender realBtn:realBtn];
            }
        } else if (step == 2) {
            [diag appendString:@"step3 -> force-unhide GM/LP views\n"];
            // 策略 3：绕过方法，直接把面板视图解隐并置顶
            for (UIView *v in gmViews) {
                if (!v.superview) [self.view addSubview:v];
                v.hidden = NO;
                v.alpha = 1.0;
                [v.superview bringSubviewToFront:v];
            }
            [self gm2_step:3 diag:diag views:gmViews sender:sender realBtn:realBtn];
        } else {
            [self gm2_done:sender diag:diag ok:NO];
        }
    });
}

- (void)gm2_done:(GMSuspendButton *)sender diag:(NSString *)diag ok:(BOOL)ok {
    sender.busy = NO;
    NSLog(@"[GM2] ===== %@ =====\n%@", ok ? @"SUCCESS" : @"FAILED", diag);
    if (ok) {
        sender.isUnlocked = YES;
        [sender setTitle:@"\u2713GM" forState:UIControlStateNormal];
        // 1.5s 后恢复标题（再点 = 弹诊断）
        __weak GMSuspendButton *w = sender;
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
                           [w setTitle:@"\u2605GM\u2605" forState:UIControlStateNormal];
                       });
    } else {
        [self gm2_showDiag:diag on:sender reuse:YES];
    }
}

- (void)gm2_showDiag:(NSString *)diag on:(GMSuspendButton *)sender reuse:(BOOL)afterFail {
    NSString *body = diag;
    
    // 修复 3：使用 stringByAppendingString 代替 + 号拼接字符串
    if (body.length > 1400) {
        body = [[body substringToIndex:1400] stringByAppendingString:@"\u2026(\u622a\u65ad)"];
    }
    
    UIAlertController *alert = [UIAlertController
        alertControllerWithTitle:[NSString stringWithFormat:@"GM \u8bca\u65ad (%@)",
                                  afterFail ? @"\u5931\u8d25" : @"\u8be6\u60c5"]
                         message:body
                  preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"\u622a\u56fe\u53d1\u7ed9\u52a9\u624b"
                                               style:UIAlertActionStyleDefault
                                              handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
