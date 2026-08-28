// DPCommentCapture v2 - 大众点评评论抓取插件
// 全面重写：无关键词过滤、递归遍历视图、二进制数据提取、模型Hook

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <objc/runtime.h>

// ==================== 评论数据模型 ====================
@interface DPComment : NSObject
@property (copy,nonatomic) NSString *author;
@property (copy,nonatomic) NSString *content;
@property (copy,nonatomic) NSString *rating;
@property (copy,nonatomic) NSString *date;
@property (copy,nonatomic) NSString *shopName;
@property (copy,nonatomic) NSString *commentId;
@property (copy,nonatomic) NSString *source;
- (NSDictionary *)toDictionary;
@end

@implementation DPComment
- (NSDictionary *)toDictionary {
    return @{
        @"author": self.author ?: @"",
        @"content": self.content ?: @"",
        @"rating": self.rating ?: @"",
        @"date": self.date ?: @"",
        @"shopName": self.shopName ?: @"",
        @"commentId": self.commentId ?: @"",
        @"source": self.source ?: @""
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
@property (assign,nonatomic) BOOL panelExpanded;
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

- (void)addText:(NSString *)text source:(NSString *)src {
    if (!self.isCapturing || text.length < 5) return;
    if ([self.seenTexts containsObject:text]) return;
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
    NSMutableString *s = [NSMutableString stringWithString:@"作者,评分,日期,商家,评论ID,来源,内容\n"];
    for (DPComment *c in self.comments) {
        NSString *content = [c.content stringByReplacingOccurrencesOfString:@"\n" withString:@" "];
        content = [content stringByReplacingOccurrencesOfString:@"," withString:@"，"];
        [s appendFormat:@"%@,%@,%@,%@,%@,%@,%@\n",
            c.author ?: @"",c.rating ?: @"",c.date ?: @"",
            c.shopName ?: @"",c.commentId ?: @"",
            c.source ?: @"",content];
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
    dispatch_once(&t,^{ w = [[DPFloatWindow alloc] initWithFrame:CGRectMake(0,0,90,44)]; });
    return w;
}
- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.windowLevel = UIWindowLevelAlert + 100;
        self.backgroundColor = [UIColor clearColor];
        self.rootViewController = [UIViewController new];
        [self makePanel];
    }
    return self;
}
- (void)makePanel {
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(0,0,90,44)];
    self.panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:0.9 alpha:0.95];
    self.panel.layer.cornerRadius = 22;
    self.panel.layer.masksToBounds = YES;
    [self.rootViewController.view addSubview:self.panel];

    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleBtn.frame = CGRectMake(0,0,90,44);
    [self.toggleBtn setTitle:@"开始" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.toggleBtn addTarget:self action:@selector(onToggle) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.toggleBtn];

    self.countLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,44,90,18)];
    self.countLabel.text = @"0条";
    self.countLabel.textColor = [UIColor whiteColor];
    self.countLabel.font = [UIFont systemFontOfSize:11];
    self.countLabel.textAlignment = NSTextAlignmentCenter;
    self.countLabel.backgroundColor = [UIColor colorWithRed:0.1 green:0.4 blue:0.8 alpha:0.95];
    self.countLabel.hidden = YES;
    [self.panel addSubview:self.countLabel];

    // 手动扫描按钮
    self.scanBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.scanBtn.frame = CGRectMake(0,62,90,28);
    [self.scanBtn setTitle:@"扫描当前页" forState:UIControlStateNormal];
    [self.scanBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.scanBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    self.scanBtn.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.8 alpha:0.95];
    self.scanBtn.hidden = YES;
    [self.scanBtn addTarget:self action:@selector(onScan) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.scanBtn];

    self.exportCSVBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.exportCSVBtn.frame = CGRectMake(0,90,45,28);
    [self.exportCSVBtn setTitle:@"CSV" forState:UIControlStateNormal];
    [self.exportCSVBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exportCSVBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    self.exportCSVBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.3 alpha:0.95];
    self.exportCSVBtn.hidden = YES;
    [self.exportCSVBtn addTarget:self action:@selector(onExportCSV) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.exportCSVBtn];

    self.exportJSONBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.exportJSONBtn.frame = CGRectMake(45,90,45,28);
    [self.exportJSONBtn setTitle:@"JSON" forState:UIControlStateNormal];
    [self.exportJSONBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exportJSONBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    self.exportJSONBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.2 alpha:0.95];
    self.exportJSONBtn.hidden = YES;
    [self.exportJSONBtn addTarget:self action:@selector(onExportJSON) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.exportJSONBtn];

    // 清空按钮
    self.clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearBtn.frame = CGRectMake(0,118,90,24);
    [self.clearBtn setTitle:@"清空" forState:UIControlStateNormal];
    [self.clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.clearBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    self.clearBtn.backgroundColor = [UIColor colorWithRed:0.5 green:0.1 blue:0.1 alpha:0.95];
    self.clearBtn.hidden = YES;
    [self.clearBtn addTarget:self action:@selector(onClear) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.clearBtn];

    UIPanGestureRecognizer *pan = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(onPan:)];
    [self.panel addGestureRecognizer:pan];
}
- (void)onPan:(UIPanGestureRecognizer *)g {
    CGPoint t = [g translationInView:self];
    self.center = CGPointMake(self.center.x + t.x, self.center.y + t.y);
    [g setTranslation:CGPointZero inView:self];
}
- (void)onToggle {
    DPCaptureManager *m = [DPCaptureManager shared];
    m.isCapturing = !m.isCapturing;
    if (m.isCapturing) {
        [self.toggleBtn setTitle:@"停止" forState:UIControlStateNormal];
        self.panel.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.95];
        self.panelExpanded = YES;
        self.countLabel.hidden = NO;
        self.scanBtn.hidden = NO;
        self.exportCSVBtn.hidden = NO;
        self.exportJSONBtn.hidden = NO;
        self.clearBtn.hidden = NO;
        self.panel.frame = CGRectMake(0,0,90,142);
        self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 90, 142);
    } else {
        [self.toggleBtn setTitle:@"开始" forState:UIControlStateNormal];
        self.panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:0.9 alpha:0.95];
        self.panelExpanded = NO;
        self.countLabel.hidden = YES;
        self.scanBtn.hidden = YES;
        self.exportCSVBtn.hidden = YES;
        self.exportJSONBtn.hidden = YES;
        self.clearBtn.hidden = YES;
        self.panel.frame = CGRectMake(0,0,90,44);
        self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 90, 44);
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
    self.hidden = NO;
    self.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 100, 120, 90, 44);
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

// ==================== Hook: UILabel 无过滤抓取 ====================
%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (!m.isCapturing || text.length < 5) return;
    // 不再检查superview，直接抓取所有文本
    [m addText:text source:@"UILabel"];
    [[DPFloatWindow shared] updateCount];
}
- (void)setAttributedText:(NSAttributedString *)attrText {
    %orig;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (!m.isCapturing) return;
    NSString *text = attrText.string;
    if (text.length > 5) {
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
    NSString *url = request.URL.absoluteString;
    DPCaptureManager *m = [DPCaptureManager shared];
    if (m.isCapturing && ([url containsString:@"review"] || [url containsString:@"comment"] ||
         [url containsString:@"feed"] || [url containsString:@"ugc"] ||
         [url containsString:@"checkin"] || [url containsString:@"note"] ||
         [url containsString:@"shop"] || [url containsString:@"dish"])) {

        return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {
            if (data && data.length > 0) {
                @try {
                    // 先尝试JSON
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
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
%end

// ==================== DPCaptureManager 扩展: JSON解析 + 二进制提取 ====================
@interface DPCaptureManager (Ext)
- (void)parseReviewJSON:(NSDictionary *)json;
- (void)extractStringsFromData:(NSData *)data;
@end

@implementation DPCaptureManager (Ext)
- (void)parseReviewJSON:(NSDictionary *)json {
    [self searchDict:json];
}
- (void)searchDict:(id)obj {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        // 检查这个字典本身是否是评论
        NSString *content = d[@"content"] ?: d[@"reviewText"] ?: d[@"body"] ?: d[@"text"] ?: d[@"reviewBody"];
        if (content && [content isKindOfClass:[NSString class]] && content.length > 3) {
            DPComment *c = [DPComment new];
            c.content = content;
            c.author = d[@"userName"] ?: d[@"author"] ?: d[@"nickName"] ?: d[@"userNick"] ?: d[@"userNameStr"] ?: @"";
            c.rating = [NSString stringWithFormat:@"%@", d[@"score"] ?: d[@"star"] ?: d[@"rating"] ?: d[@"reviewStar"] ?: @""];
            c.date = d[@"date"] ?: d[@"createTime"] ?: d[@"publishedTime"] ?: d[@"publishTime"] ?: @"";
            c.commentId = [NSString stringWithFormat:@"%@", d[@"id"] ?: d[@"reviewId"] ?: d[@"feedId"] ?: @""];
            c.source = @"network_json";
            [self addComment:c];
            [[DPFloatWindow shared] updateCount];
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
    NSLog(@"[DPCommentCapture] v2 loaded for Dianping");
}
