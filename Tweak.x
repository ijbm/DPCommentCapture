// DPCommentCapture v2 - 大众点评评论抓取插件
// 全面重写：无关键词过滤、递归遍历视图、二进制数据提取、模型Hook

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ==================== 评论数据模型 ====================
@interface DPComment : NSObject
@property (copy,nonatomic) NSString *author;
@property (copy,nonatomic) NSString *userId;
@property (copy,nonatomic) NSString *content;
@property (copy,nonatomic) NSString *rating;
@property (copy,nonatomic) NSString *date;
@property (copy,nonatomic) NSString *shopName;
@property (copy,nonatomic) NSString *commentId;
@property (copy,nonatomic) NSString *source;
@property (copy,nonatomic) NSString *avatar;
@property (copy,nonatomic) NSString *shareUrl;
@property (copy,nonatomic) NSString *recommendText;
@property (copy,nonatomic) NSString *mediaUrls;
@property (assign,nonatomic) int mediaCount;
- (NSDictionary *)toDictionary;
@end

@implementation DPComment
- (NSDictionary *)toDictionary {
    return @{
        @"author": self.author ?: @"",
        @"userId": self.userId ?: @"",
        @"content": self.content ?: @"",
        @"rating": self.rating ?: @"",
        @"date": self.date ?: @"",
        @"shopName": self.shopName ?: @"",
        @"commentId": self.commentId ?: @"",
        @"source": self.source ?: @"",
        @"avatar": self.avatar ?: @"",
        @"shareUrl": self.shareUrl ?: @"",
        @"recommendText": self.recommendText ?: @"",
        @"mediaUrls": self.mediaUrls ?: @"",
        @"mediaCount": @(self.mediaCount)
    };
}
@end

// ==================== 抓取管理器 ====================
@interface DPCaptureManager : NSObject
@property (strong,nonatomic) NSMutableArray<DPComment*> *comments;
@property (strong,nonatomic) NSMutableSet *seenTexts;
@property (assign,nonatomic) BOOL isCapturing;
@property (copy,nonatomic) NSString *currentShopName;
@property (assign,nonatomic) BOOL inReviewPage;
+ (instancetype)shared;
- (void)addComment:(DPComment *)c;
- (void)addText:(NSString *)text source:(NSString *)src;
- (void)clear;
- (NSString *)exportCSV;
- (NSString *)exportJSON;
- (void)scanAllVisibleViews;
- (void)scanView:(UIView *)view depth:(int)depth;
- (void)extractTextsFromView:(UIView *)view;
@end

// ==================== 悬浮窗UI ====================
@interface DPFloatWindow : UIWindow
@property (strong,nonatomic) UIButton *toggleBtn;
@property (strong,nonatomic) UIButton *exportCSVBtn;
@property (strong,nonatomic) UIButton *exportJSONBtn;
@property (strong,nonatomic) UIButton *scanBtn;
@property (strong,nonatomic) UIButton *clearBtn;
@property (strong,nonatomic) UILabel *countLabel;
@property (strong,nonatomic) UIView *panel;
@property (strong,nonatomic) UIButton *collapseBtn;
@property (assign,nonatomic) BOOL panelExpanded;
@property (assign,nonatomic) BOOL panelCollapsed;
+ (instancetype)shared;
- (void)show;
- (void)updateCount;
@end

@implementation DPCaptureManager

+ (instancetype)shared {
    static DPCaptureManager *m; static dispatch_once_t t;
    dispatch_once(&t,^{ m = [DPCaptureManager new]; m.comments = [NSMutableArray array]; m.seenTexts = [NSMutableSet set]; });
    return m;
}

- (void)addComment:(DPComment *)c {
    if (!self.isCapturing) return;
    NSString *dedupKey = c.commentId.length > 0 ? c.commentId : c.content;
    if (dedupKey.length > 0 && [self.seenTexts containsObject:dedupKey]) return;
    if (c.content.length < 2) return;
    [self.seenTexts addObject:dedupKey];
    c.shopName = self.currentShopName ?: c.shopName ?: @"";
    [self.comments addObject:c];
}

- (BOOL)isNoiseText:(NSString *)text {
    // 排除UI标签、价格、日期等噪声文本
    if (text.length < 15) return YES; // 评论内容至少15字
    if ([text hasPrefix:@"¥"] || [text hasPrefix:@"￥"]) return YES;
    if ([text containsString:@"发布于"]) return YES;
    if ([text containsString:@"搜索"]) return YES;
    if ([text containsString:@"查看全部"] || [text containsString:@"查看更多"]) return YES;
    if ([text containsString:@"说点什么"]) return YES;
    if ([text containsString:@"继续上滑"] || [text containsString:@"松手后"]) return YES;
    if ([text containsString:@"已为你跳转"]) return YES;
    if ([text containsString:@"AI结合"] || [text containsString:@"上百种模型"]) return YES;
    if ([text containsString:@"带图/视频"] || [text containsString:@"搜索评价"]) return YES;
    if ([text containsString:@"当前为您定位"] || [text containsString:@"看完啦"]) return YES;
    if ([text containsString:@"星级分排名"] || [text containsString:@"近30天"]) return YES;
    if ([text containsString:@"当前客流"] || [text containsString:@"行李寄存"]) return YES;
    if ([text containsString:@"月售"] || [text containsString:@"满2人"]) return YES;
    if ([text containsString:@"最多50人"] || [text containsString:@"最多20人"]) return YES;
    if ([text containsString:@"比单买省"] || [text containsString:@"立减"]) return YES;
    if ([text containsString:@"距景点"] || [text containsString:@"低价房"]) return YES;
    if ([text containsString:@"30天低价"] || [text containsString:@"新开业"]) return YES;
    if ([text containsString:@"万+消费"] || [text containsString:@"消费"]) return YES;
    // 纯日期格式
    NSRegularExpression *dateRe = [NSRegularExpression regularExpressionWithPattern:@"^\\d{4}年\\d{1,2}月\\d{1,2}日$" options:0 error:nil];
    if ([dateRe firstMatchInString:text options:0 range:NSMakeRange(0, text.length)]) return YES;
    // 纯数字+条
    if ([text hasSuffix:@"条"] && text.length < 10) return YES;
    // 纯英文用户名（短）
    if (text.length < 20 && [text rangeOfCharacterFromSet:[NSCharacterSet letterCharacterSet]].length == text.length) return YES;
    return NO;
}

- (void)addText:(NSString *)text source:(NSString *)src {
    if (!self.isCapturing || text.length < 5) return;
    if ([self.seenTexts containsObject:text]) return;
    // UILabel/UITextView文本需要过滤噪声
    if ([src hasPrefix:@"UILabel"] || [src hasPrefix:@"UITextView"] || [src hasPrefix:@"KVC"]) {
        if ([self isNoiseText:text]) return;
    }
    [self.seenTexts addObject:text];
    DPComment *c = [DPComment new];
    c.content = text;
    c.source = src;
    c.shopName = self.currentShopName ?: @"";
    c.commentId = [NSString stringWithFormat:@"auto_%lu", (unsigned long)self.comments.count];
    [self.comments addObject:c];
}

- (void)clear { [self.comments removeAllObjects]; [self.seenTexts removeAllObjects]; }

- (NSString *)exportCSV {
    NSMutableString *s = [NSMutableString stringWithString:@"\uFEFF序号,用户ID,用户名,头像,评分,发布时间,商家,评论ID,来源,内容,分享链接,推荐文本,媒体数量,媒体链接\n"];
    int idx = 0;
    for (DPComment *c in self.comments) {
        idx++;
        NSString *content = c.content ?: @"";
        content = [content stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        content = [content stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
        NSString *author = [c.author stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""] ?: @"";
        NSString *shop = [c.shopName stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""] ?: @"";
        NSString *rec = [c.recommendText stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""] ?: @"";
        NSString *media = [c.mediaUrls stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""] ?: @"";
        [s appendFormat:@"%d,\"%@\",\"%@\",\"%@\",\"%@\",\"%@\",\"%@\",\"%@\",\"%@\",\"%@\",\"%@\",\"%@\",%d,\"%@\"\n",
            idx, c.userId ?: @"", author, c.avatar ?: @"",
            c.rating ?: @"", c.date ?: @"", shop,
            c.commentId ?: @"", c.source ?: @"", content,
            c.shareUrl ?: @"", rec, c.mediaCount, media];
    }
    return s;
}

- (NSString *)exportJSON {
    NSMutableArray *arr = [NSMutableArray array];
    for (DPComment *c in self.comments) [arr addObject:[c toDictionary]];
    return [[NSString alloc] initWithData:
        [NSJSONSerialization dataWithJSONObject:arr options:NSJSONWritingPrettyPrinted error:nil]
        encoding:NSUTF8StringEncoding] ?: @"[]";
}

// ==================== 递归扫描视图提取文本 ====================
- (void)scanAllVisibleViews {
    if (!self.isCapturing) return;
    UIWindow *keyWindow = [UIApplication sharedApplication].keyWindow;
    if (!keyWindow) return;
    [self scanView:keyWindow depth:0];
    [[DPFloatWindow shared] updateCount];
}

- (void)scanView:(UIView *)view depth:(int)depth {
    if (depth > 15) return;
    if (!view || view.hidden || view.alpha < 0.01) return;

    // 跳过我们自己的悬浮窗（检查windowLevel）
    if ([view isKindOfClass:[UIWindow class]]) {
        UIWindow *w = (UIWindow *)view;
        if (w.windowLevel > UIWindowLevelStatusBar) return;
    }

    [self extractTextsFromView:view];

    for (UIView *sub in view.subviews) {
        [self scanView:sub depth:depth + 1];
    }
}

- (void)extractTextsFromView:(UIView *)view {
    @try {
        // UILabel - 提取text和attributedText
        if ([view isKindOfClass:[UILabel class]]) {
            UILabel *lbl = (UILabel *)view;
            NSString *text = lbl.text;
            if (text.length > 5 && ![text containsString:@"DPCommentCapture"]) {
                [self addText:text source:@"UILabel"];
            }
            NSString *attrText = lbl.attributedText.string;
            if (attrText.length > 5 && ![attrText isEqualToString:text]) {
                [self addText:attrText source:@"UILabel_Attr"];
            }
        }
        // UITextView
        else if ([view isKindOfClass:[UITextView class]]) {
            UITextView *tv = (UITextView *)view;
            if (tv.text.length > 5) [self addText:tv.text source:@"UITextView"];
        }
        // UIButton - 提取标题
        else if ([view isKindOfClass:[UIButton class]]) {
            UIButton *btn = (UIButton *)view;
            NSString *title = [btn titleForState:UIControlStateNormal];
            if (title.length > 5) [self addText:title source:@"UIButton"];
        }
        // 尝试KVC获取text属性（适用于自定义视图）
        else {
            @try {
                id textVal = [view valueForKey:@"text"];
                if ([textVal isKindOfClass:[NSString class]] && [textVal length] > 5) {
                    [self addText:textVal source:@"KVC_text"];
                }
            } @catch(id e) {}
            @try {
                id titleVal = [view valueForKey:@"title"];
                if ([titleVal isKindOfClass:[NSString class]] && [titleVal length] > 5) {
                    [self addText:titleVal source:@"KVC_title"];
                }
            } @catch(id e) {}
        }
    } @catch(id e) {}
}
@end

@implementation DPFloatWindow
+ (instancetype)shared {
    static DPFloatWindow *w; static dispatch_once_t t;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    dispatch_once(&t,^{ w = [[DPFloatWindow alloc] initWithFrame:CGRectMake(0,0,sw,sh)]; });
    return w;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        self.rootViewController.view.backgroundColor = [UIColor clearColor];
        [self makePanel];
    }
    return self;
}
- (UIView *)hitTest:(CGPoint)point withEvent:(UIEvent *)event {
    // 只在panel范围内拦截触摸，其余穿透到下面的App
    if (self.panel && !self.panel.hidden && CGRectContainsPoint(self.panel.frame, point)) {
        return [super hitTest:point withEvent:event];
    }
    return nil;
}
- (void)makePanel {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    // 浮动条 - 全屏宽，默认在屏幕中间偏上
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(0, sh * 0.3, sw, 44)];
    self.panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:0.9 alpha:0.95];
    [self.rootViewController.view addSubview:self.panel];

    // 左侧：开始/停止按钮
    CGFloat btnW = (sw - 80) / 4.0;
    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleBtn.frame = CGRectMake(0,0,btnW,44);
    [self.toggleBtn setTitle:@"开始抓取" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    [self.toggleBtn addTarget:self action:@selector(onToggle) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.toggleBtn];

    // 计数标签
    self.countLabel = [[UILabel alloc] initWithFrame:CGRectMake(btnW,0,80,44)];
    self.countLabel.text = @"0条";
    self.countLabel.textColor = [UIColor whiteColor];
    self.countLabel.font = [UIFont boldSystemFontOfSize:14];
    self.countLabel.textAlignment = NSTextAlignmentCenter;
    [self.panel addSubview:self.countLabel];

    // 扫描按钮
    self.scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.scanBtn.frame = CGRectMake(btnW+80,0,btnW,44);
    [self.scanBtn setTitle:@"扫描" forState:UIControlStateNormal];
    [self.scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.scanBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.scanBtn addTarget:self action:@selector(onScan) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.scanBtn];

    // CSV导出
    self.exportCSVBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.exportCSVBtn.frame = CGRectMake((btnW+80)*2,0,btnW,44);
    [self.exportCSVBtn setTitle:@"CSV" forState:UIControlStateNormal];
    [self.exportCSVBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exportCSVBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.exportCSVBtn addTarget:self action:@selector(onExportCSV) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.exportCSVBtn];

    // JSON导出
    self.exportJSONBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.exportJSONBtn.frame = CGRectMake((btnW+80)*3,0,btnW,44);
    [self.exportJSONBtn setTitle:@"JSON" forState:UIControlStateNormal];
    [self.exportJSONBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exportJSONBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    [self.exportJSONBtn addTarget:self action:@selector(onExportJSON) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.exportJSONBtn];

    // 清空按钮（第二行，展开时显示）
    self.clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearBtn.frame = CGRectMake(0,44,sw,36);
    [self.clearBtn setTitle:@"清空全部" forState:UIControlStateNormal];
    [self.clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.clearBtn.titleLabel.font = [UIFont systemFontOfSize:14];
    self.clearBtn.backgroundColor = [UIColor colorWithRed:0.5 green:0.1 blue:0.1 alpha:0.95];
    self.clearBtn.hidden = YES;
    [self.clearBtn addTarget:self action:@selector(onClear) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.clearBtn];

    // 收缩/展开按钮（右侧小圆点）
    self.collapseBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.collapseBtn.frame = CGRectMake(sw - 36, 0, 36, 44);
    [self.collapseBtn setTitle:@"›" forState:UIControlStateNormal];
    [self.collapseBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.collapseBtn.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    [self.collapseBtn addTarget:self action:@selector(onCollapse) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.collapseBtn];

    // 拖动手势（仅垂直拖动）
    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [self.panel addGestureRecognizer:pan];
}
- (void)onCollapse {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat top = self.panel.frame.origin.y;
    if (!self.panelCollapsed) {
        // 收缩：只显示一个小圆点
        self.panelCollapsed = YES;
        self.panel.frame = CGRectMake(sw - 44, top, 44, 44);
        self.panel.layer.cornerRadius = 22;
        self.panel.layer.masksToBounds = YES;
        self.toggleBtn.hidden = YES;
        self.countLabel.hidden = YES;
        self.scanBtn.hidden = YES;
        self.exportCSVBtn.hidden = YES;
        self.exportJSONBtn.hidden = YES;
        self.clearBtn.hidden = YES;
        [self.collapseBtn setTitle:@"‹" forState:UIControlStateNormal];
        [self.collapseBtn setFrame:CGRectMake(0, 0, 44, 44)];
    } else {
        // 展开：恢复全宽
        self.panelCollapsed = NO;
        self.panel.frame = CGRectMake(0, top, sw, self.panelExpanded ? 80 : 44);
        self.panel.layer.cornerRadius = 0;
        self.panel.layer.masksToBounds = NO;
        self.toggleBtn.hidden = NO;
        self.countLabel.hidden = NO;
        self.scanBtn.hidden = NO;
        self.exportCSVBtn.hidden = NO;
        self.exportJSONBtn.hidden = NO;
        if (self.panelExpanded) self.clearBtn.hidden = NO;
        [self.collapseBtn setTitle:@"›" forState:UIControlStateNormal];
        [self.collapseBtn setFrame:CGRectMake(sw - 36, 0, 36, 44)];
    }
}
- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    // 移动panel，限制在屏幕范围内
    CGRect pf = self.panel.frame;
    pf.origin.y += t.y;
    pf.origin.y = MAX(0, MIN(sh - pf.size.height, pf.origin.y));
    self.panel.frame = pf;
    [g setTranslation:CGPointZero inView:self];
}
- (void)onToggle {
    DPCaptureManager *m = [DPCaptureManager shared];
    m.isCapturing = !m.isCapturing;
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    if (m.isCapturing) {
        [self.toggleBtn setTitle:@"停止抓取" forState:UIControlStateNormal];
        self.panel.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.95];
        self.panelExpanded = YES;
        self.clearBtn.hidden = NO;
        // 展开时保持顶部位置不变
        CGFloat top = self.panel.frame.origin.y;
        self.panel.frame = CGRectMake(0, top, sw, 80);
    } else {
        [self.toggleBtn setTitle:@"开始抓取" forState:UIControlStateNormal];
        self.panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:0.9 alpha:0.95];
        self.panelExpanded = NO;
        self.clearBtn.hidden = YES;
        CGFloat top = self.panel.frame.origin.y;
        self.panel.frame = CGRectMake(0, top, sw, 44);
    }
    [self updateCount];
}
- (void)updateCount {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.countLabel.text = [NSString stringWithFormat:@"%lu条", (unsigned long)[DPCaptureManager shared].comments.count];
    });
}
- (void)onScan {
    [[DPCaptureManager shared] scanAllVisibleViews];
    [self updateCount];
}
- (void)onExportCSV {
    NSString *csv = [[DPCaptureManager shared] exportCSV];
    [self shareFile:csv name:@"dianping_comments.csv"];
}
- (void)onExportJSON {
    NSString *json = [[DPCaptureManager shared] exportJSON];
    [self shareFile:json name:@"dianping_comments.json"];
}
- (void)onClear {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"清空确认" message:[NSString stringWithFormat:@"确认清空 %lu 条评论？", (unsigned long)[DPCaptureManager shared].comments.count] preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"清空" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
        [[DPCaptureManager shared] clear];
        [self updateCount];
    }]];
    [[self rootViewController] presentViewController:a animated:YES completion:nil];
}
- (void)shareFile:(NSString *)content name:(NSString *)name {
    if ([DPCaptureManager shared].comments.count == 0) {
        UIAlertController *a = [UIAlertController alertControllerWithTitle:@"无数据" message:@"没有可导出的评论" preferredStyle:UIAlertControllerStyleAlert];
        [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
        [[self rootViewController] presentViewController:a animated:YES completion:nil];
        return;
    }
    // 写入临时文件
    NSString *tmpDir = NSTemporaryDirectory();
    NSString *ts = [NSString stringWithFormat:@"%ld", (long)[[NSDate date] timeIntervalSince1970]];
    NSString *fileName = [NSString stringWithFormat:@"%@_%@", ts, name];
    NSString *filePath = [tmpDir stringByAppendingPathComponent:fileName];
    [content writeToFile:filePath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    // 用系统分享面板让用户选择保存位置
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] applicationActivities:nil];
    activityVC.completionWithItemsHandler = ^(NSString *activityType, BOOL completed, NSArray *returnedItems, NSError *activityError) {
        if (completed) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导出成功" message:[NSString stringWithFormat:@"已通过 %@ 导出", activityType ?: @"分享"] preferredStyle:UIAlertControllerStyleAlert];
                [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
                [[self rootViewController] presentViewController:a animated:YES completion:nil];
            });
        }
        // 清理临时文件
        [[NSFileManager defaultManager] removeItemAtPath:filePath error:nil];
    };
    // 在iPad上需要popover
    if ([activityVC respondsToSelector:@selector(popoverPresentationController)]) {
        activityVC.popoverPresentationController.sourceView = self.panel;
        activityVC.popoverPresentationController.sourceRect = self.panel.bounds;
    }
    [[self rootViewController] presentViewController:activityVC animated:YES completion:nil];
}
- (void)show {
    CGFloat sw = [UIScreen mainScreen].bounds.size.width;
    CGFloat sh = [UIScreen mainScreen].bounds.size.height;
    self.hidden = NO;
    // 窗口全屏，panel浮动在屏幕中间偏上
    self.frame = CGRectMake(0, 0, sw, sh);
    self.panel.frame = CGRectMake(0, sh * 0.3, sw, 44);
}
@end

// ==================== Hook: 所有ViewController进入 ====================
// 标记当前是否在评论相关页面
%hook UIViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]);
    // 检测评论相关页面
    if ([clsName containsString:@"Review"] || [clsName containsString:@"review"] ||
        [clsName containsString:@"Comment"] || [clsName containsString:@"comment"] ||
        [clsName containsString:@"Feed"] || [clsName containsString:@"feed"] ||
        [clsName containsString:@"UGC"] || [clsName containsString:@"ugc"] ||
        [clsName containsString:@"ShopInfo"] || [clsName containsString:@"Detail"]) {
        [[DPCaptureManager shared] setInReviewPage:YES];
        // 尝试获取商家名
        @try {
            UINavigationItem *navItem = [(UIViewController *)self navigationItem];
            NSString *title = navItem.title;
            if (title.length > 0) {
                [[DPCaptureManager shared] setCurrentShopName:title];
            }
        } @catch(id e) {}
    }
}
- (void)viewDidDisappear:(BOOL)animated {
    %orig;
    NSString *clsName = NSStringFromClass([self class]);
    if ([clsName containsString:@"Review"] || [clsName containsString:@"Feed"] ||
        [clsName containsString:@"UGC"] || [clsName containsString:@"ShopInfo"]) {
        [[DPCaptureManager shared] setInReviewPage:NO];
    }
}
%end

// ==================== Hook: UILabel 带过滤抓取 ====================
%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (!m.isCapturing || text.length < 15) return;
    [m addText:text source:@"UILabel"];
    [[DPFloatWindow shared] updateCount];
}
- (void)setAttributedText:(NSAttributedString *)attrText {
    %orig;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (!m.isCapturing) return;
    NSString *text = attrText.string;
    if (text.length > 15) {
        [m addText:text source:@"UILabel_Attr"];
        [[DPFloatWindow shared] updateCount];
    }
}
%end

// ==================== Hook: UITextView ====================
%hook UITextView
- (void)setText:(NSString *)text {
    %orig;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (!m.isCapturing || text.length < 5) return;
    [m addText:text source:@"UITextView"];
    [[DPFloatWindow shared] updateCount];
}
%end

// ==================== Hook: UIScrollView 滚动时自动扫描 ====================
%hook UIScrollView
- (void)layoutSubviews {
    %orig;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (!m.isCapturing || !m.inReviewPage) return;
    // 滚动时延迟扫描（避免过于频繁）
    static dispatch_once_t onceToken;
    static dispatch_queue_t scanQueue;
    dispatch_once(&onceToken, ^{ scanQueue = dispatch_queue_create("dp.scan", DISPATCH_QUEUE_SERIAL); });
    static int skipCount = 0;
    skipCount++;
    if (skipCount < 10) return;
    skipCount = 0;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), scanQueue, ^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [[DPCaptureManager shared] scanAllVisibleViews];
        });
    });
}
%end

// ==================== Hook: NSURLSession 抓取网络数据 ====================
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    DPCaptureManager *m = [DPCaptureManager shared];
    if (m.isCapturing) {
        // 对所有请求都尝试拦截，不过滤URL
        return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && data.length > 0) {
                @try {
                    // 先尝试JSON
                    id json = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:nil];
                    if (json) {
                        SEL sel = NSSelectorFromString(@"parseReviewJSON:");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [m performSelector:sel withObject:json];
#pragma clang diagnostic pop
                    }
                    // 无论JSON是否成功，都尝试从二进制中提取字符串
                    SEL sel2 = NSSelectorFromString(@"extractStringsFromData:");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                    [m performSelector:sel2 withObject:data];
#pragma clang diagnostic pop
                } @catch(id e) {}
            }
            handler(data, response, error);
        });
    }
    return %orig;
}
// 也hook无completionHandler的版本（delegate模式）
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request {
    NSString *url = request.URL.absoluteString;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (m.isCapturing) {
        NSLog(@"[DPCommentCapture] network delegate-mode: %@", url);
    }
    return %orig;
}
%end

// ==================== Hook: NSURLSessionTask resume ====================
// 拦截所有网络任务启动，记录URL
%hook NSURLSessionTask
- (void)resume {
    %orig;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (m.isCapturing) {
        NSString *url = self.originalRequest.URL.absoluteString;
        NSString *lowerUrl = [url lowercaseString];
        if ([lowerUrl containsString:@"review"] || [lowerUrl containsString:@"comment"] ||
            [lowerUrl containsString:@"feed"] || [lowerUrl containsString:@"ugc"] ||
            [lowerUrl containsString:@"shop"] || [lowerUrl containsString:@"dish"] ||
            [lowerUrl containsString:@"note"] || [lowerUrl containsString:@"checkin"] ||
            [lowerUrl containsString:@"outsidesifted"] || [lowerUrl containsString:@"sift"]) {
            NSLog(@"[DPCommentCapture] >>> review API: %@", url);
        }
    }
}
%end

// ==================== DPCaptureManager 扩展: JSON解析 + 二进制提取 ====================
@interface DPCaptureManager (Ext)
- (void)parseReviewJSON:(id)json;
- (void)extractStringsFromData:(NSData *)data;
@end

@implementation DPCaptureManager (Ext)
- (void)parseReviewJSON:(id)json {
    // 参考浏览器扩展的解析逻辑
    // 1. 先找数组：list / data / reviews / result / 第一个对象数组
    NSArray *list = nil;
    if ([json isKindOfClass:[NSArray class]]) {
        list = (NSArray *)json;
    } else if ([json isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = (NSDictionary *)json;
        if ([d[@"list"] isKindOfClass:[NSArray class]]) list = d[@"list"];
        else if ([d[@"data"] isKindOfClass:[NSArray class]]) list = d[@"data"];
        else if ([d[@"reviews"] isKindOfClass:[NSArray class]]) list = d[@"reviews"];
        else if ([d[@"result"] isKindOfClass:[NSArray class]]) list = d[@"result"];
        else if ([d[@"reviewList"] isKindOfClass:[NSArray class]]) list = d[@"reviewList"];
        else if ([d[@"feedList"] isKindOfClass:[NSArray class]]) list = d[@"feedList"];
        else {
            // 搜索第一个对象数组
            for (NSString *key in d) {
                id val = d[key];
                if ([val isKindOfClass:[NSArray class]] && [(NSArray *)val count] > 0 &&
                    [[(NSArray *)val firstObject] isKindOfClass:[NSDictionary class]]) {
                    list = val;
                    break;
                }
            }
        }
        // 如果没找到数组，递归搜索
        if (!list) {
            [self searchDict:json];
            return;
        }
    }
    if (list) {
        NSLog(@"[DPCommentCapture] found list with %lu items", (unsigned long)list.count);
        for (id item in list) {
            if ([item isKindOfClass:[NSDictionary class]]) {
                [self extractReviewFromDict:item];
            }
        }
    }
}
- (void)extractReviewFromDict:(NSDictionary *)r {
    // 参考浏览器扩展的字段映射
    NSDictionary *user = r[@"feedUser"] ?: r[@"user"] ?: @{};
    if (![user isKindOfClass:[NSDictionary class]]) user = @{};
    
    NSString *content = r[@"content"] ?: r[@"reviewBody"] ?: r[@"text"] ?: r[@"reviewText"] ?: @"";
    if (![content isKindOfClass:[NSString class]] || content.length < 2) return;
    
    DPComment *c = [DPComment new];
    c.content = content;
    c.userId = [NSString stringWithFormat:@"%@", user[@"userId"] ?: @""];
    c.author = user[@"userName"] ?: user[@"nickName"] ?: user[@"name"] ?: @"";
    c.avatar = user[@"avatar"] ?: @"";
    c.rating = [NSString stringWithFormat:@"%@", r[@"star"] ?: r[@"score"] ?: r[@"rating"] ?: @""];
    c.date = r[@"time"] ?: r[@"addTime"] ?: r[@"addDate"] ?: r[@"publishTime"] ?: r[@"publishedTime"] ?: @"";
    c.commentId = [NSString stringWithFormat:@"%@", r[@"id"] ?: r[@"reviewId"] ?: r[@"feedId"] ?: @""];
    c.shareUrl = r[@"shareUrl"] ?: @"";
    c.recommendText = r[@"recommendText"] ?: @"";
    c.source = @"network_json";
    
    // 媒体信息
    NSArray *pictures = r[@"pictures"];
    if ([pictures isKindOfClass:[NSArray class]]) {
        c.mediaCount = (int)pictures.count;
        NSMutableArray *urls = [NSMutableArray array];
        for (id pic in pictures) {
            if ([pic isKindOfClass:[NSDictionary class]]) {
                NSDictionary *p = pic;
                int ptype = [p[@"type"] intValue];
                if (ptype == 4) {
                    [urls addObject:[NSString stringWithFormat:@"视频:%@", p[@"livePicVideoUrl"] ?: @"N/A"]];
                } else {
                    [urls addObject:[NSString stringWithFormat:@"图片:%@", p[@"bigUrl"] ?: @"N/A"]];
                }
            }
        }
        if (urls.count > 0) c.mediaUrls = [urls componentsJoinedByString:@"; "];
    }
    
    [self addComment:c];
    [[DPFloatWindow shared] updateCount];
}
- (void)searchDict:(id)obj {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        // 检查是否是评论对象（有content且有user/feedUser）
        NSString *content = d[@"content"] ?: d[@"reviewBody"] ?: d[@"reviewText"] ?: d[@"text"];
        if (content && [content isKindOfClass:[NSString class]] && content.length > 3) {
            // 有user或feedUser字段说明是评论对象
            if (d[@"feedUser"] || d[@"user"] || d[@"star"] || d[@"reviewBody"]) {
                [self extractReviewFromDict:d];
            }
        }
        for (NSString *k in d) {
            [self searchDict:d[k]];
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in obj) { [self searchDict:item]; }
    }
}
- (void)extractStringsFromData:(NSData *)data {
    // 从二进制数据中提取UTF8字符串
    const char *bytes = (const char *)data.bytes;
    NSUInteger length = data.length;
    if (length < 10) return;

    NSMutableString *result = [NSMutableString string];
    NSUInteger i = 0;
    NSUInteger consecutive = 0;

    while (i < length) {
        // 检测UTF8中文字符（3字节）和ASCII可打印字符
        unsigned char c = bytes[i];
        if (c >= 0x20 && c <= 0x7E) {
            [result appendFormat:@"%c", c];
            consecutive++;
            i++;
        } else if (c >= 0xC0 && i + 1 < length) {
            // UTF8多字节字符
            int charLen = 1;
            if ((c & 0xE0) == 0xC0) charLen = 2;
            else if ((c & 0xF0) == 0xE0) charLen = 3;
            else if ((c & 0xF8) == 0xF0) charLen = 4;

            if (i + charLen <= length) {
                NSString *str = [[NSString alloc] initWithBytes:bytes + i length:charLen encoding:NSUTF8StringEncoding];
                if (str) {
                    [result appendString:str];
                    consecutive += charLen;
                }
                i += charLen;
            } else {
                if (consecutive > 15) {
                    NSString *clean = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                    if (clean.length > 10) {
                        [self addText:clean source:@"network_binary"];
                        [[DPFloatWindow shared] updateCount];
                    }
                }
                [result setString:@""];
                consecutive = 0;
                i++;
            }
        } else {
            if (consecutive > 15) {
                NSString *clean = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if (clean.length > 10) {
                    [self addText:clean source:@"network_binary"];
                    [[DPFloatWindow shared] updateCount];
                }
            }
            [result setString:@""];
            consecutive = 0;
            i++;
        }
    }
    // 处理最后一段
    if (consecutive > 15) {
        NSString *clean = [result stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if (clean.length > 10) {
            [self addText:clean source:@"network_binary"];
            [[DPFloatWindow shared] updateCount];
        }
    }
}
@end

// ==================== Hook: 模型类 KVC ====================
// Hook NSObject setValue:forKey: 捕获模型赋值
%hook NSObject
- (void)setValue:(id)value forKey:(NSString *)key {
    %orig;
    if (![DPCaptureManager shared].isCapturing) return;
    if (![value isKindOfClass:[NSString class]]) return;
    NSString *text = (NSString *)value;
    if (text.length < 5) return;
    // 捕获评论相关属性赋值
    if ([key containsString:@"review"] || [key containsString:@"content"] ||
        [key containsString:@"comment"] || [key containsString:@"body"] ||
        [key containsString:@"text"] || [key containsString:@"desc"]) {
        NSString *clsName = NSStringFromClass([self class]);
        if ([clsName containsString:@"Review"] || [clsName containsString:@"Comment"] ||
            [clsName containsString:@"Feed"] || [clsName containsString:@"UGC"] ||
            [clsName containsString:@"Model"] || [clsName containsString:@"Cell"]) {
            [[DPCaptureManager shared] addText:text source:[NSString stringWithFormat:@"KVC_%@.%@", clsName, key]];
            [[DPFloatWindow shared] updateCount];
        }
    }
}
%end

// ==================== 入口 ====================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DPFloatWindow shared] show];
    });
    NSLog(@"[DPCommentCapture] v4 loaded for Dianping");
}
