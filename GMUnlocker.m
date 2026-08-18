#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <objc/message.h>

#define GM_BUTTON_TAG 88888

// 悬浮可拖拽按钮实现
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
    CGPoint currentPosition = [touch locationInView:self.superview];
    self.center = CGPointMake(currentPosition.x - self.beginPoint.x + self.bounds.size.width / 2.0,
                              currentPosition.y - self.beginPoint.y + self.bounds.size.height / 2.0);
}

@end

// 静态 Swizzle 函数
static void swizzleMethod(Class class, SEL originalSelector, SEL swizzledSelector) {
    Method originalMethod = class_getInstanceMethod(class, originalSelector);
    Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
    
    BOOL didAddMethod = class_addMethod(class,
                                        originalSelector,
                                        method_getImplementation(swizzledMethod),
                                        method_getTypeEncoding(swizzledMethod));
    if (didAddMethod) {
        class_replaceMethod(class,
                            swizzledSelector,
                            method_getImplementation(originalMethod),
                            method_getTypeEncoding(originalMethod));
    } else {
        method_exchangeImplementations(originalMethod, swizzledMethod);
    }
}

@implementation UIViewController (GMUnlocker)

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        Class class = [UIViewController class];
        swizzleMethod(class, @selector(viewDidAppear:), @selector(gm_viewDidAppear:));
    });
}

- (void)gm_viewDidAppear:(BOOL)animated {
    [self gm_viewDidAppear:animated];
    
    NSString *className = NSStringFromClass([self class]);
    
    // 动态匹配 BagViewController（兼容 Swift 命名混淆）
    if ([className containsString:@"BagViewController"]) {
        if (![self.view viewWithTag:GM_BUTTON_TAG]) {
            dispatch_async(dispatch_get_main_queue(), ^{
                GMSuspendButton *gmBtn = [GMSuspendButton buttonWithType:UIButtonTypeCustom];
                gmBtn.tag = GM_BUTTON_TAG;
                gmBtn.frame = CGRectMake(self.view.bounds.size.width - 90, 100, 75, 36);
                [gmBtn setTitle:@"★ GM ★" forState:UIControlStateNormal];
                gmBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
                [gmBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                gmBtn.backgroundColor = [UIColor colorWithRed:0.9 green:0.2 blue:0.2 alpha:0.9];
                gmBtn.layer.cornerRadius = 18;
                gmBtn.layer.borderWidth = 1.5;
                gmBtn.layer.borderColor = [UIColor whiteColor].CGColor;
                gmBtn.layer.masksToBounds = YES;
                
                // 绑定原生的 clickGMButtonWithButton: 事件
                [gmBtn addTarget:self 
                          action:@selector(gm_triggerAction:) 
                forControlEvents:UIControlEventTouchUpInside];
                
                [self.view addSubview:gmBtn];
                [self.view bringSubviewToFront:gmBtn];
            });
        }
    }
}

- (void)gm_triggerAction:(UIButton *)sender {
    SEL gmSelector = NSSelectorFromString(@"clickGMButtonWithButton:");
    if ([self respondsToSelector:gmSelector]) {
        // 调用原生 GM 方法
        ((void (*)(id, SEL, id))objc_msgSend)(self, gmSelector, sender);
    } else {
        // 若找不到带参方法，降级尝试无参调用
        SEL gmNoParam = NSSelectorFromString(@"clickGMButton:");
        if ([self respondsToSelector:gmNoParam]) {
            ((void (*)(id, SEL, id))objc_msgSend)(self, gmNoParam, sender);
        } else {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" 
                                                                           message:@"未找到 GM 方法响应" 
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}

@end