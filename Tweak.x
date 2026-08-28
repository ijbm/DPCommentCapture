// DPCommentCapture - 大众点评评论抓取插件
// Hook评论相关类，悬浮窗UI控制抓取/导出

#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>

// ==================== 评论数据模型 ====================
@interface DPComment : NSObject
@property (copy,nonatomic) NSString *author;
@property (copy,nonatomic) NSString *content;
@property (copy,nonatomic) NSString *rating;
@property (copy,nonatomic) NSString *date;
@property (copy,nonatomic) NSString *shopName;
@property (copy,nonatomic) NSString *commentId;
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
        @"commentId": self.commentId ?: @""
    };
}
@end

// ==================== 抓取管理器 ====================
@interface DPCaptureManager : NSObject
@property (strong,nonatomic) NSMutableArray<DPComment*> *comments;
@property (assign,nonatomic) BOOL isCapturing;
@property (copy,nonatomic) NSString *currentShopName;
+ (instancetype)shared;
- (void)addComment:(DPComment *)c;
- (void)clear;
- (NSString *)exportCSV;
- (NSString *)exportJSON;
@end

@implementation DPCaptureManager
+ (instancetype)shared {
    static DPCaptureManager *m; static dispatch_once_t t;
    dispatch_once(&t,^{ m = [DPCaptureManager new]; m.comments = [NSMutableArray array]; });
    return m;
}
- (void)addComment:(DPComment *)c {
    if (!self.isCapturing) return;
    if (c.commentId.length > 0) {
        for (DPComment *e in self.comments) {
            if ([e.commentId isEqualToString:c.commentId]) return;
        }
    }
    c.shopName = self.currentShopName ?: c.shopName;
    [self.comments addObject:c];
}
- (void)clear { [self.comments removeAllObjects]; }
- (NSString *)exportCSV {
    NSMutableString *s = [NSMutableString stringWithString:@"作者,评分,日期,商家,评论ID,内容\n"];
    for (DPComment *c in self.comments) {
        [s appendFormat:@"%@,%@,%@,%@,%@,%@\n",
            c.author ?: @"",c.rating ?: @"",c.date ?: @"",
            c.shopName ?: @"",c.commentId ?: @"",
            [c.content stringByReplacingOccurrencesOfString:@"\n" withString:@" "]];
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
@end

// ==================== 悬浮窗UI ====================
@interface DPFloatWindow : UIWindow
@property (strong,nonatomic) UIButton *toggleBtn;
@property (strong,nonatomic) UIButton *exportBtn;
@property (strong,nonatomic) UIButton *clearBtn;
@property (strong,nonatomic) UILabel *countLabel;
@property (strong,nonatomic) UIView *panel;
@property (assign,nonatomic) BOOL panelExpanded;
+ (instancetype)shared;
- (void)show;
@end

@implementation DPFloatWindow
+ (instancetype)shared {
    static DPFloatWindow *w; static dispatch_once_t t;
    dispatch_once(&t,^{ w = [[DPFloatWindow alloc] initWithFrame:CGRectMake(0,0,80,44)]; });
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
    self.panel = [[UIView alloc] initWithFrame:CGRectMake(0,0,80,44)];
    self.panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:0.9 alpha:0.9];
    self.panel.layer.cornerRadius = 22;
    self.panel.layer.masksToBounds = YES;
    [self.rootViewController.view addSubview:self.panel];

    self.toggleBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.toggleBtn.frame = CGRectMake(0,0,80,44);
    [self.toggleBtn setTitle:@"开始" forState:UIControlStateNormal];
    [self.toggleBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.toggleBtn.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self.toggleBtn addTarget:self action:@selector(onToggle) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.toggleBtn];

    // 展开后的额外按钮
    self.countLabel = [[UILabel alloc] initWithFrame:CGRectMake(0,44,80,20)];
    self.countLabel.text = @"0条";
    self.countLabel.textColor = [UIColor whiteColor];
    self.countLabel.font = [UIFont systemFontOfSize:11];
    self.countLabel.textAlignment = NSTextAlignmentCenter;
    self.countLabel.backgroundColor = [UIColor colorWithRed:0.1 green:0.4 blue:0.8 alpha:0.9];
    self.countLabel.hidden = YES;
    [self.panel addSubview:self.countLabel];

    self.exportBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.exportBtn.frame = CGRectMake(0,64,40,30);
    [self.exportBtn setTitle:@"CSV" forState:UIControlStateNormal];
    [self.exportBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exportBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    self.exportBtn.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.3 alpha:0.9];
    self.exportBtn.hidden = YES;
    [self.exportBtn addTarget:self action:@selector(onExportCSV) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.exportBtn];

    self.clearBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    self.clearBtn.frame = CGRectMake(40,64,40,30);
    [self.clearBtn setTitle:@"JSON" forState:UIControlStateNormal];
    [self.clearBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.clearBtn.titleLabel.font = [UIFont systemFontOfSize:12];
    self.clearBtn.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.2 alpha:0.9];
    self.clearBtn.hidden = YES;
    [self.clearBtn addTarget:self action:@selector(onExportJSON) forControlEvents:UIControlEventTouchUpInside];
    [self.panel addSubview:self.clearBtn];

    // 拖动手势
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
        self.panel.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
        self.panelExpanded = YES;
        self.countLabel.hidden = NO;
        self.exportBtn.hidden = NO;
        self.clearBtn.hidden = NO;
        self.panel.frame = CGRectMake(0,0,80,94);
        self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 80, 94);
    } else {
        [self.toggleBtn setTitle:@"开始" forState:UIControlStateNormal];
        self.panel.backgroundColor = [UIColor colorWithRed:0.1 green:0.5 blue:0.9 alpha:0.9];
        self.panelExpanded = NO;
        self.countLabel.hidden = YES;
        self.exportBtn.hidden = YES;
        self.clearBtn.hidden = YES;
        self.panel.frame = CGRectMake(0,0,80,44);
        self.frame = CGRectMake(self.frame.origin.x, self.frame.origin.y, 80, 44);
    }
    [self updateCount];
}
- (void)updateCount {
    self.countLabel.text = [NSString stringWithFormat:@"%lu条", (unsigned long)[DPCaptureManager shared].comments.count];
}
- (void)onExportCSV {
    NSString *csv = [[DPCaptureManager shared] exportCSV];
    [self saveFile:csv name:@"dianping_comments.csv"];
}
- (void)onExportJSON {
    NSString *json = [[DPCaptureManager shared] exportJSON];
    [self saveFile:json name:@"dianping_comments.json"];
}
- (void)saveFile:(NSString *)content name:(NSString *)name {
    NSString *dir = @"/var/mobile/Documents/DPCommentCapture";
    [[NSFileManager defaultManager] createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *path = [dir stringByAppendingPathComponent:name];
    [content writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"导出成功" message:path preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [[self rootViewController] presentViewController:a animated:YES completion:nil];
    [self updateCount];
}
- (void)show {
    self.hidden = NO;
    self.frame = CGRectMake([UIScreen mainScreen].bounds.size.width - 90, 120, 80, 44);
}
@end

// ==================== Hook: 评论Cell ====================
// Hook UGCFeedDetailController 获取评论详情
%hook UGCFeedDetailController
- (void)viewDidLoad {
    %orig;
    [[DPCaptureManager shared] setCurrentShopName:@"UnknownShop"];
}
- (void)viewDidAppear:(BOOL)animated {
    %orig;
    @try {
        UINavigationItem *navItem = [(UIViewController *)self navigationItem];
        NSString *title = navItem.title;
        if (title.length > 0) {
            [[DPCaptureManager shared] setCurrentShopName:title];
        }
    } @catch(id e) {}
}
%end

// Hook UGCNewReviewListController 评论列表
%hook UGCNewReviewListController
- (void)viewDidLoad {
    %orig;
    @try {
        UINavigationItem *navItem = [(UIViewController *)self navigationItem];
        NSString *title = navItem.title;
        if (title.length > 0) {
            [[DPCaptureManager shared] setCurrentShopName:title];
        }
    } @catch(id e) {}
}
%end

// Hook NVShopInfoReviewASModule 商家详情页评论模块
%hook NVShopInfoReviewASModule
- (void)viewDidLoad {
    %orig;
}
%end

// Hook UITableViewCell 将评论数据提取
%hook UITableViewCell
- (void)layoutSubviews {
    %orig;
    if (![DPCaptureManager shared].isCapturing) return;

    // 从cell的textLabel和detailTextLabel提取评论
    NSString *text = self.textLabel.text;
    NSString *detail = self.detailTextLabel.text;

    if (text.length > 5 && detail.length > 0) {
        DPComment *c = [DPComment new];
        c.content = text;
        c.author = detail;
        c.commentId = [NSString stringWithFormat:@"%ld", (long)self.tag];
        [[DPCaptureManager shared] addComment:c];
        [[DPFloatWindow shared] updateCount];
    }
}
%end

// Hook UILabel 文本渲染时抓取
%hook UILabel
- (void)setText:(NSString *)text {
    %orig;
    if (![DPCaptureManager shared].isCapturing || text.length < 10) return;

    // 尝试从superview层级判断是否为评论内容
    UIView *sv = self.superview;
    if (sv && [sv isKindOfClass:NSClassFromString(@"UITableViewCellContentView")]) {
        // 检查是否包含评论关键词
        if ([text containsString:@"条评论"] || [text containsString:@"分"] ||
            [text containsString:@"星"] || [text containsString:@"推荐"] ||
            [text containsString:@"好吃"] || [text containsString:@"不错"] ||
            [text containsString:@"环境"] || [text containsString:@"服务"]) {
            DPComment *c = [DPComment new];
            c.content = text;
            c.commentId = [NSString stringWithFormat:@"lbl_%ld", (long)self.tag];
            [[DPCaptureManager shared] addComment:c];
            [[DPFloatWindow shared] updateCount];
        }
    }
}
%end

// Hook NSURLSessionDataTask 抓取网络请求返回的评论数据
%hook NSURLSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))handler {
    NSString *url = request.URL.absoluteString;
    if ([DPCaptureManager shared].isCapturing &&
        ([url containsString:@"reviewlist"] || [url containsString:@"shopreviewlist"] ||
         [url containsString:@"dishreviewlist"] || [url containsString:@"extrareviewlist"] ||
         [url containsString:@"commentlist"] || [url containsString:@"feeddetail"])) {

        return %orig(request, ^(NSData *data, NSURLResponse *response, NSError *error) {
            // 尝试解析返回数据中的评论
            if (data && data.length > 0) {
                @try {
                    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
                    if (json) {
                        SEL sel = NSSelectorFromString(@"parseReviewJSON:");
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Warc-performSelector-leaks"
                        [[DPCaptureManager shared] performSelector:sel withObject:json];
#pragma clang diagnostic pop
                    }
                } @catch(id e) {}
            }
            handler(data, response, error);
        });
    }
    return %orig;
}
%end

// ==================== DPCaptureManager JSON解析扩展 ====================
@interface DPCaptureManager (JSONParse)
- (void)parseReviewJSON:(NSDictionary *)json;
@end
@implementation DPCaptureManager (JSONParse)
- (void)parseReviewJSON:(NSDictionary *)json {
    // 递归搜索JSON中的评论数据
    [self searchDict:json forKey:@"reviewList"];
    [self searchDict:json forKey:@"comments"];
    [self searchDict:json forKey:@"feedList"];
    [self searchDict:json forKey:@"reviewFeedList"];
}
- (void)searchDict:(id)obj forKey:(NSString *)key {
    if ([obj isKindOfClass:[NSDictionary class]]) {
        NSDictionary *d = obj;
        id val = d[key];
        if (val) {
            [self extractComments:val];
        }
        for (NSString *k in d) {
            [self searchDict:d[k] forKey:key];
        }
    } else if ([obj isKindOfClass:[NSArray class]]) {
        for (id item in obj) {
            [self searchDict:item forKey:key];
        }
    }
}
- (void)extractComments:(id)obj {
    if (![obj isKindOfClass:[NSArray class]]) return;
    for (id item in obj) {
        if (![item isKindOfClass:[NSDictionary class]]) continue;
        NSDictionary *d = item;
        DPComment *c = [DPComment new];
        c.author = d[@"userName"] ?: d[@"author"] ?: d[@"nickName"] ?: d[@"userNick"] ?: @"";
        c.content = d[@"content"] ?: d[@"reviewText"] ?: d[@"body"] ?: d[@"text"] ?: @"";
        c.rating = [NSString stringWithFormat:@"%@", d[@"score"] ?: d[@"star"] ?: d[@"rating"] ?: @""];
        c.date = d[@"date"] ?: d[@"createTime"] ?: d[@"publishedTime"] ?: @"";
        c.commentId = [NSString stringWithFormat:@"%@", d[@"id"] ?: d[@"reviewId"] ?: d[@"feedId"] ?: @""];
        if (c.content.length > 0) {
            [self addComment:c];
            [[DPFloatWindow shared] updateCount];
        }
    }
}
@end

// ==================== 入口 ====================
%ctor {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[DPFloatWindow shared] show];
    });
    NSLog(@"[DPCommentCapture] Tweak loaded for Dianping");
}
